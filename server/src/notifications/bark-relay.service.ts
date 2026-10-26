import { BadRequestException, Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DatabaseService } from '../database/database.service';
import { RealtimeGateway } from '../realtime/realtime.gateway';

/** Bark's built-in sounds (https://github.com/Finb/Bark/tree/master/Sounds). */
export const BARK_BUILTIN_SOUNDS = [
  'alarm', 'anticipate', 'bell', 'birdsong', 'bloom', 'calypso', 'chime', 'choo', 'descent',
  'electronic', 'fanfare', 'glass', 'gotosleep', 'healthnotification', 'horn', 'ladder',
  'mailsent', 'minuet', 'multiwayinvitation', 'newmail', 'newsflash', 'noir', 'paymentsuccess',
  'shake', 'sherwoodforest', 'silence', 'spell', 'suspense', 'telegraph', 'tiptoes',
  'typewriters', 'update',
];

const KEY_PATTERN = /^[A-Za-z0-9]{8,64}$/;
// Built-in names, or a .caf the user imported into Bark (named without ".caf")
const SOUND_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;
// Messages arriving this close together become one alert ("3 new messages") instead of a burst of sounds
const COALESCE_MS = 1000;

type Language = 'en' | 'km';

const TEXT: Record<Language, {
  message: string;
  attachment: string;
  voice: string;
  messages: (count: number) => string;
  incoming: (video: boolean) => string;
  missed: (video: boolean) => string;
  testBody: string;
}> = {
  en: {
    message: 'New message',
    attachment: '📎 Photo or file',
    voice: '🎤 Voice message',
    messages: (count) => `${count} new messages`,
    incoming: (video) => (video ? '📹 Incoming video call' : '📞 Incoming voice call'),
    missed: (video) => (video ? '📹 Missed video call' : '📞 Missed voice call'),
    testBody: 'Notifications are working 🎉',
  },
  km: {
    message: 'សារថ្មី',
    attachment: '📎 រូបភាព ឬឯកសារ',
    voice: '🎤 សារជាសំឡេង',
    messages: (count) => `សារថ្មី ${count}`,
    incoming: (video) => (video ? '📹 ការហៅជាវីដេអូចូល' : '📞 ការហៅជាសំឡេងចូល'),
    missed: (video) => (video ? '📹 ខកខានការហៅជាវីដេអូ' : '📞 ខកខានការហៅជាសំឡេង'),
    testBody: 'ការជូនដំណឹងដំណើរការហើយ 🎉',
  },
};

export interface BarkRelay {
  user_id: string;
  device_key: string;
  is_enabled: boolean;
  message_sound: string;
  call_sound: string;
  language: string;
  last_error: string | null;
}

export interface BarkSettingsUpdate {
  enabled?: boolean;
  message_sound?: string;
  call_sound?: string;
  language?: string;
}

interface PendingAlert {
  timer: NodeJS.Timeout;
  senderUserId: string;
  envelopeType: string;
}

type SendResult = 'sent' | 'key_rejected' | 'failed';

/**
 * Alerts for when Our Chat is closed (swiped away) or in the background.
 *
 * iOS never runs a closed app, and Apple push to Our Chat itself needs a paid developer
 * account, so the server relays the alert through the free Bark app instead
 * (https://bark.day.app). Tapping the alert opens Our Chat on that chat (ourchat://chat/<id>).
 *
 * Messages are end-to-end encrypted, so alerts only say who wrote and what kind of message
 * ("Alice: 🎤 Voice message"), never the text. Each chat has one alert that updates itself and
 * is removed once the chat is read. Nothing is sent while one of the user's apps is on screen:
 * the app shows its own banners then.
 */
@Injectable()
export class BarkRelayService implements OnModuleDestroy {
  private readonly logger = new Logger(BarkRelayService.name);
  private readonly serverUrl: string;
  /** `${userId}:${conversationId}` -> alert waiting to be sent */
  private readonly pending = new Map<string, PendingAlert>();
  /** `${userId}:${conversationId}` whose alert is showing on the phone (removed when read) */
  private readonly showing = new Set<string>();
  /** callId -> users whose phones were rung through Bark */
  private readonly rungCalls = new Map<string, Set<string>>();

  constructor(
    private readonly db: DatabaseService,
    private readonly config: ConfigService,
    private readonly realtime: RealtimeGateway,
  ) {
    // Public Bark server by default; a self-hosted bark-server can be used instead
    this.serverUrl = (this.config.get<string>('BARK_SERVER_URL') || 'https://api.day.app').replace(/\/+$/, '');
  }

  onModuleDestroy() {
    for (const alert of this.pending.values()) clearTimeout(alert.timer);
    this.pending.clear();
  }

  // MARK: - Settings (one Bark key per user)

  async getSettings(userId: string) {
    const relay = await this.findRelay(userId);
    return {
      configured: !!relay,
      enabled: relay?.is_enabled ?? false,
      message_sound: relay?.message_sound ?? 'glass',
      call_sound: relay?.call_sound ?? 'multiwayinvitation',
      language: relay?.language ?? 'en',
      last_error: relay?.last_error ?? null,
      sounds: BARK_BUILTIN_SOUNDS,
    };
  }

  /**
   * Saves the key copied from the Bark app (the full "https://api.day.app/<key>/..." address or
   * just the key) after a test alert to it worked, so a mistyped key is caught right away.
   */
  async saveKey(userId: string, rawKey: string, update: BarkSettingsUpdate = {}) {
    const deviceKey = this.parseKey(rawKey);
    const current = await this.findRelay(userId);
    const relay: BarkRelay = {
      user_id: userId,
      device_key: deviceKey,
      is_enabled: true,
      message_sound: this.cleanSound(update.message_sound) ?? current?.message_sound ?? 'glass',
      call_sound: this.cleanSound(update.call_sound) ?? current?.call_sound ?? 'multiwayinvitation',
      language: this.cleanLanguage(update.language) ?? current?.language ?? 'en',
      last_error: null,
    };

    const result = await this.send(relay, this.testParams(relay), false);
    if (result === 'key_rejected') {
      throw new BadRequestException(
        'Bark does not know this key. Open Bark, copy the address on its first screen, and paste it again.',
      );
    }
    if (result === 'failed') {
      throw new BadRequestException('Could not reach the Bark server. Check the internet connection and try again.');
    }

    await this.db.query(
      `INSERT INTO bark_relays (user_id, device_key, is_enabled, message_sound, call_sound, language, last_error, updated_at)
       VALUES ($1, $2, TRUE, $3, $4, $5, NULL, NOW())
       ON CONFLICT (user_id) DO UPDATE
       SET device_key = $2, is_enabled = TRUE, message_sound = $3, call_sound = $4, language = $5,
           last_error = NULL, updated_at = NOW()`,
      [userId, deviceKey, relay.message_sound, relay.call_sound, relay.language],
    );
    return this.getSettings(userId);
  }

  async updateSettings(userId: string, update: BarkSettingsUpdate) {
    const relay = await this.findRelay(userId);
    if (!relay) {
      throw new BadRequestException('Set up Bark first');
    }
    if (update.message_sound !== undefined && !this.cleanSound(update.message_sound)) {
      throw new BadRequestException('Invalid message sound name');
    }
    if (update.call_sound !== undefined && !this.cleanSound(update.call_sound)) {
      throw new BadRequestException('Invalid call sound name');
    }

    await this.db.query(
      `UPDATE bark_relays
       SET is_enabled = COALESCE($2::boolean, is_enabled),
           message_sound = COALESCE($3, message_sound),
           call_sound = COALESCE($4, call_sound),
           language = COALESCE($5, language),
           -- Switching it back on retries a key that failed before
           last_error = CASE WHEN $2::boolean IS TRUE THEN NULL ELSE last_error END,
           updated_at = NOW()
       WHERE user_id = $1`,
      [
        userId,
        update.enabled ?? null,
        this.cleanSound(update.message_sound) ?? null,
        this.cleanSound(update.call_sound) ?? null,
        this.cleanLanguage(update.language) ?? null,
      ],
    );
    return this.getSettings(userId);
  }

  async sendTest(userId: string) {
    const relay = await this.findRelay(userId);
    if (!relay) {
      throw new BadRequestException('Set up Bark first');
    }
    const result = await this.send(relay, this.testParams(relay));
    return { sent: result === 'sent', ...(await this.getSettings(userId)) };
  }

  async removeRelay(userId: string) {
    await this.db.query('DELETE FROM bark_relays WHERE user_id = $1', [userId]);
    for (const [key, alert] of this.pending) {
      if (key.startsWith(`${userId}:`)) {
        clearTimeout(alert.timer);
        this.pending.delete(key);
      }
    }
    return this.getSettings(userId);
  }

  // MARK: - Messages

  /** A message was stored: alert the other members whose app isn't on screen. Never throws. */
  async onNewMessage(conversationId: string, senderUserId: string, envelopeType: string) {
    // Call signalling and system notices are not something to alert about
    if (envelopeType === 'e2ee_call_signal' || envelopeType === 'system') return;
    try {
      const res = await this.db.query(
        `SELECT cm.user_id
         FROM conversation_members cm
         JOIN bark_relays b ON b.user_id = cm.user_id AND b.is_enabled = TRUE
         WHERE cm.conversation_id = $1 AND cm.user_id <> $2 AND cm.is_muted = FALSE`,
        [conversationId, senderUserId],
      );
      for (const { user_id: userId } of res.rows) {
        if (this.realtime.isUserInForeground(userId)) continue;
        this.schedule(userId, conversationId, senderUserId, envelopeType);
      }
    } catch (err) {
      this.logger.error(`Bark relay for ${conversationId} failed: ${(err as Error).message}`);
    }
  }

  /** The user read the chat (on any device): take its alert off the phone. Never throws. */
  async onConversationRead(userId: string, conversationId: string) {
    const key = `${userId}:${conversationId}`;
    const waiting = this.pending.get(key);
    if (waiting) {
      clearTimeout(waiting.timer);
      this.pending.delete(key);
    }
    if (!this.showing.delete(key)) return;
    try {
      const relay = await this.findRelay(userId);
      if (relay?.is_enabled) {
        await this.send(relay, { id: this.chatAlertId(conversationId), delete: '1' });
      }
    } catch (err) {
      this.logger.error(`Bark alert removal for ${conversationId} failed: ${(err as Error).message}`);
    }
  }

  private schedule(userId: string, conversationId: string, senderUserId: string, envelopeType: string) {
    const key = `${userId}:${conversationId}`;
    const waiting = this.pending.get(key);
    if (waiting) {
      // Already about to alert for this chat: the alert will name the newest sender
      waiting.senderUserId = senderUserId;
      waiting.envelopeType = envelopeType;
      return;
    }
    const alert: PendingAlert = {
      senderUserId,
      envelopeType,
      timer: setTimeout(() => {
        this.pending.delete(key);
        void this.flush(userId, conversationId, alert);
      }, COALESCE_MS),
    };
    this.pending.set(key, alert);
  }

  private async flush(userId: string, conversationId: string, alert: PendingAlert) {
    try {
      // The user may have opened the app (or read the chat) during the wait
      if (this.realtime.isUserInForeground(userId)) return;

      const res = await this.db.query(
        `SELECT c.type, c.title, (c.last_sequence_id - cm.last_read_sequence_id) AS unread, cm.is_muted,
                b.user_id, b.device_key, b.is_enabled, b.message_sound, b.call_sound, b.language, b.last_error,
                u.display_name AS sender_display_name, u.username AS sender_username
         FROM conversation_members cm
         JOIN conversations c ON c.id = cm.conversation_id
         JOIN bark_relays b ON b.user_id = cm.user_id
         LEFT JOIN users u ON u.id = $3
         WHERE cm.conversation_id = $1 AND cm.user_id = $2`,
        [conversationId, userId, alert.senderUserId],
      );
      const row = res.rows[0];
      if (!row || !row.is_enabled || row.is_muted) return;
      const unread = Number(row.unread);
      if (!(unread > 0)) return;

      const text = TEXT[this.language(row.language)];
      const senderName = row.sender_display_name || row.sender_username || 'Our Chat';
      const what =
        unread > 1
          ? text.messages(unread)
          : alert.envelopeType === 'e2ee_attachment'
            ? text.attachment
            : alert.envelopeType === 'e2ee_voice'
              ? text.voice
              : text.message;
      const isGroup = row.type !== 'direct' && !!row.title;

      const result = await this.send(row as BarkRelay, {
        title: isGroup ? row.title : senderName,
        body: isGroup ? `${senderName}: ${what}` : what,
        sound: row.message_sound,
        group: conversationId,
        id: this.chatAlertId(conversationId),
        url: this.chatUrl(conversationId),
        level: 'active',
        // Bark keeps no copy in its history (the alert is just a pointer to Our Chat)
        isArchive: '0',
      });
      if (result === 'sent') {
        this.showing.add(`${userId}:${conversationId}`);
      }
    } catch (err) {
      this.logger.error(`Bark alert for ${conversationId} failed: ${(err as Error).message}`);
    }
  }

  // MARK: - Calls

  /** Rings the phones of members whose app isn't on screen (repeats the sound for 30 s). Never throws. */
  async onIncomingCall(call: {
    callId: string;
    conversationId: string;
    callerUserId: string;
    callerName: string;
    conversationTitle: string | null;
    callType: 'audio' | 'video';
  }) {
    try {
      const res = await this.db.query(
        `SELECT b.*
         FROM conversation_members cm
         JOIN bark_relays b ON b.user_id = cm.user_id AND b.is_enabled = TRUE
         WHERE cm.conversation_id = $1 AND cm.user_id <> $2`,
        [call.conversationId, call.callerUserId],
      );
      const rung = new Set<string>();
      const video = call.callType === 'video';
      const isGroup = !!call.conversationTitle && call.conversationTitle !== call.callerName;
      for (const relay of res.rows as BarkRelay[]) {
        if (this.realtime.isUserInForeground(relay.user_id)) continue;
        const text = TEXT[this.language(relay.language)];
        const result = await this.send(relay, {
          title: isGroup ? call.conversationTitle! : call.callerName,
          body: isGroup ? `${call.callerName}: ${text.incoming(video)}` : text.incoming(video),
          sound: relay.call_sound,
          call: '1',
          level: 'timeSensitive',
          group: call.conversationId,
          id: this.callAlertId(call.callId),
          url: this.chatUrl(call.conversationId),
          isArchive: '0',
        });
        if (result === 'sent') rung.add(relay.user_id);
      }
      if (rung.size > 0) this.rungCalls.set(call.callId, rung);
    } catch (err) {
      this.logger.error(`Bark call alert for ${call.callId} failed: ${(err as Error).message}`);
    }
  }

  /**
   * The call ended: an answered call's alert is removed; an unanswered one becomes "Missed call"
   * (except for whoever declined it). Never throws.
   */
  async onCallEnded(call: {
    callId: string;
    conversationId: string;
    wasAnswered: boolean;
    endedByUserId: string;
    callerName: string;
    conversationTitle: string | null;
    callType: 'audio' | 'video';
  }) {
    const rung = this.rungCalls.get(call.callId);
    if (!rung) return;
    this.rungCalls.delete(call.callId);
    const video = call.callType === 'video';
    const isGroup = !!call.conversationTitle && call.conversationTitle !== call.callerName;
    try {
      for (const userId of rung) {
        const relay = await this.findRelay(userId);
        if (!relay?.is_enabled) continue;
        if (call.wasAnswered || userId === call.endedByUserId) {
          await this.send(relay, { id: this.callAlertId(call.callId), delete: '1' });
          continue;
        }
        const text = TEXT[this.language(relay.language)];
        await this.send(relay, {
          title: isGroup ? call.conversationTitle! : call.callerName,
          body: isGroup ? `${call.callerName}: ${text.missed(video)}` : text.missed(video),
          sound: relay.message_sound,
          group: call.conversationId,
          id: this.callAlertId(call.callId),
          url: this.chatUrl(call.conversationId),
          isArchive: '0',
        });
      }
    } catch (err) {
      this.logger.error(`Bark missed-call alert for ${call.callId} failed: ${(err as Error).message}`);
    }
  }

  // MARK: - Bark API

  /**
   * POST /push (https://bark.day.app/#/en-us/tutorial). Bark answers `{ code: 200 }` on success
   * and 400 "failed to get device token" for a key it no longer knows (reset in the app, or the
   * app was deleted). Such a key is switched off at once: the public server bans IPs that keep
   * sending failing requests.
   */
  private async send(relay: BarkRelay, params: Record<string, string>, recordResult = true): Promise<SendResult> {
    let status = 0;
    let message = '';
    try {
      const res = await fetch(`${this.serverUrl}/push`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=utf-8', 'User-Agent': 'OurChat-Server/1.0' },
        body: JSON.stringify({ device_key: relay.device_key, ...params }),
        signal: AbortSignal.timeout(10_000),
      });
      const body = (await res.json().catch(() => ({}))) as { code?: number; message?: string };
      status = body.code ?? res.status;
      message = body.message || res.statusText;
      if (res.ok && status === 200) {
        if (recordResult && relay.last_error) {
          await this.db.query('UPDATE bark_relays SET last_error = NULL WHERE user_id = $1', [relay.user_id]);
          relay.last_error = null;
        }
        return 'sent';
      }
    } catch (err) {
      message = (err as Error).message;
    }

    const keyRejected = status === 400 && /device (token|key)/i.test(message);
    this.logger.warn(`Bark push for user ${relay.user_id} failed (${status || 'network'}): ${message}`);
    if (recordResult) {
      await this.db.query(
        `UPDATE bark_relays
         SET last_error = $3, is_enabled = CASE WHEN $4::boolean THEN FALSE ELSE is_enabled END, updated_at = NOW()
         WHERE user_id = $1 AND device_key = $2`,
        [relay.user_id, relay.device_key, keyRejected ? 'key_rejected' : 'unreachable', keyRejected],
      );
      relay.last_error = keyRejected ? 'key_rejected' : 'unreachable';
      if (keyRejected) relay.is_enabled = false;
    }
    return keyRejected ? 'key_rejected' : 'failed';
  }

  private testParams(relay: BarkRelay): Record<string, string> {
    return {
      title: 'Our Chat',
      body: TEXT[this.language(relay.language)].testBody,
      sound: relay.message_sound,
      id: 'ourchat-test',
      url: 'ourchat://',
      isArchive: '0',
    };
  }

  // MARK: - Helpers

  /** Accepts the bare key or any Bark address that contains it ("https://api.day.app/<key>/title"). */
  parseKey(raw: string): string {
    const input = (raw || '').trim();
    if (KEY_PATTERN.test(input)) return input;
    let url: URL;
    try {
      url = new URL(input);
    } catch {
      throw new BadRequestException('Paste the address shown in the Bark app, e.g. https://api.day.app/AbCd1234/');
    }
    const serverHost = new URL(this.serverUrl).host;
    if (url.host !== serverHost) {
      throw new BadRequestException(`That address is not on ${serverHost}, the Bark server this chat uses.`);
    }
    const key = url.pathname.split('/').filter(Boolean)[0] || '';
    if (!KEY_PATTERN.test(key)) {
      throw new BadRequestException('No Bark key found in that address. Copy it again from the Bark app.');
    }
    return key;
  }

  private cleanSound(sound: string | undefined): string | undefined {
    if (sound === undefined) return undefined;
    const name = sound.trim().replace(/\.caf$/i, '');
    return SOUND_PATTERN.test(name) ? name : undefined;
  }

  private cleanLanguage(language: string | undefined): Language | undefined {
    return language === 'en' || language === 'km' ? language : undefined;
  }

  private language(value: string): Language {
    return value === 'km' ? 'km' : 'en';
  }

  private chatAlertId(conversationId: string) {
    return `chat-${conversationId}`;
  }

  private callAlertId(callId: string) {
    return `call-${callId}`;
  }

  private chatUrl(conversationId: string) {
    return `ourchat://chat/${conversationId}`;
  }

  private async findRelay(userId: string): Promise<BarkRelay | null> {
    const res = await this.db.query('SELECT * FROM bark_relays WHERE user_id = $1', [userId]);
    return (res.rows[0] as BarkRelay) ?? null;
  }
}

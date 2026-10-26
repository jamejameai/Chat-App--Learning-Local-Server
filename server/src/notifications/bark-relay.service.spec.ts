import { BadRequestException } from '@nestjs/common';
import { BarkRelayService } from './bark-relay.service';

describe('BarkRelayService', () => {
  const relayRow = {
    user_id: 'bob',
    device_key: 'BobKey12345',
    is_enabled: true,
    message_sound: 'ping',
    call_sound: 'alarm',
    language: 'en',
    last_error: null,
  };

  let query: jest.Mock;
  let fetchMock: jest.SpyInstance;
  let foreground: Set<string>;
  let flushRow: any;
  let service: BarkRelayService;

  const config = { get: () => undefined };
  const sentBodies = () => fetchMock.mock.calls.map(([, init]) => JSON.parse(init.body));
  const barkReplies = (status: number, body: any) =>
    fetchMock.mockResolvedValue({ ok: status === 200, status, statusText: '', json: async () => body } as any);

  beforeEach(() => {
    jest.useFakeTimers();
    foreground = new Set();
    flushRow = {
      ...relayRow,
      type: 'direct',
      title: null,
      unread: '1',
      is_muted: false,
      sender_display_name: 'Alice',
      sender_username: 'alice',
    };
    query = jest.fn(async (sql: string) => {
      if (sql.includes('SELECT cm.user_id')) return { rows: [{ user_id: 'bob' }] };
      if (sql.includes('AS unread')) return { rows: [flushRow] };
      if (sql.includes('SELECT b.*')) return { rows: [relayRow] };
      if (sql.includes('SELECT * FROM bark_relays')) return { rows: [relayRow] };
      return { rows: [] };
    });
    fetchMock = jest.spyOn(global, 'fetch');
    barkReplies(200, { code: 200, message: 'success' });
    service = new BarkRelayService(
      { query } as any,
      config as any,
      { isUserInForeground: (id: string) => foreground.has(id) } as any,
    );
  });

  afterEach(() => {
    service.onModuleDestroy();
    fetchMock.mockRestore();
    jest.useRealTimers();
  });

  describe('parseKey', () => {
    it('accepts the bare key or the address the Bark app shows', () => {
      expect(service.parseKey('AbCd1234efgh')).toBe('AbCd1234efgh');
      expect(service.parseKey(' https://api.day.app/AbCd1234efgh/ ')).toBe('AbCd1234efgh');
      expect(service.parseKey('https://api.day.app/AbCd1234efgh/Title/Body?sound=bell')).toBe('AbCd1234efgh');
    });

    it('refuses other servers (the key would be sent there) and text without a key', () => {
      expect(() => service.parseKey('https://evil.example/AbCd1234efgh/')).toThrow(BadRequestException);
      expect(() => service.parseKey('https://api.day.app/')).toThrow(BadRequestException);
      expect(() => service.parseKey('hello there')).toThrow(BadRequestException);
    });
  });

  describe('messages', () => {
    it('alerts a member whose app is closed, opening the chat on tap, with their sound', async () => {
      await service.onNewMessage('conv-1', 'alice', 'e2ee_voice');
      expect(fetchMock).not.toHaveBeenCalled(); // waits briefly to group a burst of messages
      await jest.advanceTimersByTimeAsync(1000);

      expect(fetchMock).toHaveBeenCalledTimes(1);
      expect(fetchMock.mock.calls[0][0]).toBe('https://api.day.app/push');
      expect(sentBodies()[0]).toEqual({
        device_key: 'BobKey12345',
        title: 'Alice',
        body: '🎤 Voice message',
        sound: 'ping',
        group: 'conv-1',
        id: 'chat-conv-1',
        url: 'ourchat://chat/conv-1',
        level: 'active',
        isArchive: '0',
      });
      // The sender is never alerted about their own message
      expect(query.mock.calls[0][1]).toEqual(['conv-1', 'alice']);
    });

    it('turns a burst of messages into one alert with the unread count', async () => {
      flushRow.unread = '3';
      await service.onNewMessage('conv-1', 'alice', 'e2ee_text');
      await service.onNewMessage('conv-1', 'alice', 'e2ee_text');
      await service.onNewMessage('conv-1', 'alice', 'e2ee_text');
      await jest.advanceTimersByTimeAsync(1000);

      expect(fetchMock).toHaveBeenCalledTimes(1);
      expect(sentBodies()[0]).toEqual(expect.objectContaining({ title: 'Alice', body: '3 new messages' }));
    });

    it('names the group and the sender in a group chat', async () => {
      flushRow.type = 'group';
      flushRow.title = 'Family';
      await service.onNewMessage('conv-1', 'alice', 'e2ee_attachment');
      await jest.advanceTimersByTimeAsync(1000);

      expect(sentBodies()[0]).toEqual(expect.objectContaining({ title: 'Family', body: 'Alice: 📎 Photo or file' }));
    });

    it('writes the alert in Khmer for a Khmer user', async () => {
      flushRow.language = 'km';
      flushRow.unread = '2';
      await service.onNewMessage('conv-1', 'alice', 'e2ee_text');
      await jest.advanceTimersByTimeAsync(1000);

      expect(sentBodies()[0].body).toBe('សារថ្មី 2');
    });

    it('sends nothing while the app is on screen (it shows its own banner)', async () => {
      foreground.add('bob');
      await service.onNewMessage('conv-1', 'alice', 'e2ee_text');
      await jest.advanceTimersByTimeAsync(1000);

      expect(fetchMock).not.toHaveBeenCalled();
    });

    it('sends nothing if the app came on screen or the chat was read during the wait', async () => {
      await service.onNewMessage('conv-1', 'alice', 'e2ee_text');
      foreground.add('bob');
      await jest.advanceTimersByTimeAsync(1000);
      expect(fetchMock).not.toHaveBeenCalled();

      foreground.clear();
      flushRow.unread = '0';
      await service.onNewMessage('conv-1', 'alice', 'e2ee_text');
      await jest.advanceTimersByTimeAsync(1000);
      expect(fetchMock).not.toHaveBeenCalled();
    });

    it('ignores call signalling and system messages', async () => {
      await service.onNewMessage('conv-1', 'alice', 'e2ee_call_signal');
      await service.onNewMessage('conv-1', 'alice', 'system');
      await jest.advanceTimersByTimeAsync(1000);

      expect(query).not.toHaveBeenCalled();
      expect(fetchMock).not.toHaveBeenCalled();
    });

    it('removes the alert from the phone once the chat is read', async () => {
      await service.onNewMessage('conv-1', 'alice', 'e2ee_text');
      await jest.advanceTimersByTimeAsync(1000);
      await service.onConversationRead('bob', 'conv-1');

      expect(sentBodies()[1]).toEqual({ device_key: 'BobKey12345', id: 'chat-conv-1', delete: '1' });

      // Further read receipts for the same chat don't send anything more
      await service.onConversationRead('bob', 'conv-1');
      expect(fetchMock).toHaveBeenCalledTimes(2);
    });

    it('switches off a key Bark no longer knows, so the server is not banned for failing pushes', async () => {
      barkReplies(400, { code: 400, message: 'failed to get device token: failed to get [BobKey12345] device token from database' });
      await service.onNewMessage('conv-1', 'alice', 'e2ee_text');
      await jest.advanceTimersByTimeAsync(1000);

      const disable = query.mock.calls.find(([sql]) => sql.includes('SET last_error'));
      expect(disable[1]).toEqual(['bob', 'BobKey12345', 'key_rejected', true]);
    });

    it('keeps the key on when the Bark server is only unreachable', async () => {
      fetchMock.mockRejectedValue(new Error('getaddrinfo ENOTFOUND api.day.app'));
      await service.onNewMessage('conv-1', 'alice', 'e2ee_text');
      await jest.advanceTimersByTimeAsync(1000);

      const record = query.mock.calls.find(([sql]) => sql.includes('SET last_error'));
      expect(record[1]).toEqual(['bob', 'BobKey12345', 'unreachable', false]);
    });
  });

  describe('saveKey', () => {
    it('sends a test alert first and refuses a key Bark does not know', async () => {
      barkReplies(400, { code: 400, message: 'failed to get device token' });

      await expect(service.saveKey('bob', 'https://api.day.app/WrongKey123/')).rejects.toThrow(BadRequestException);
      expect(query.mock.calls.some(([sql]) => sql.includes('INSERT INTO bark_relays'))).toBe(false);
    });

    it('saves a working key with the chosen sounds', async () => {
      await service.saveKey('bob', 'https://api.day.app/GoodKey123/', { message_sound: 'ping.caf', language: 'km' });

      expect(sentBodies()[0]).toEqual(expect.objectContaining({ device_key: 'GoodKey123', title: 'Our Chat', sound: 'ping' }));
      const insert = query.mock.calls.find(([sql]) => sql.includes('INSERT INTO bark_relays'));
      expect(insert[1]).toEqual(['bob', 'GoodKey123', 'ping', 'alarm', 'km']);
    });
  });

  describe('calls', () => {
    const incoming = {
      callId: 'call-1',
      conversationId: 'conv-1',
      callerUserId: 'alice',
      callerName: 'Alice',
      conversationTitle: 'Alice',
      callType: 'video' as const,
    };

    it('rings a closed app with the repeating call sound', async () => {
      await service.onIncomingCall(incoming);

      expect(sentBodies()[0]).toEqual(expect.objectContaining({
        title: 'Alice',
        body: '📹 Incoming video call',
        sound: 'alarm',
        call: '1',
        level: 'timeSensitive',
        id: 'call-call-1',
        url: 'ourchat://chat/conv-1',
      }));
    });

    it('turns an unanswered call into "Missed call"', async () => {
      await service.onIncomingCall(incoming);
      await service.onCallEnded({ ...incoming, wasAnswered: false, endedByUserId: 'alice' });

      expect(sentBodies()[1]).toEqual(expect.objectContaining({ id: 'call-call-1', body: '📹 Missed video call', sound: 'ping' }));
      expect(sentBodies()[1].call).toBeUndefined();
    });

    it('removes the alert when the call was answered or declined by that person', async () => {
      await service.onIncomingCall(incoming);
      await service.onCallEnded({ ...incoming, wasAnswered: false, endedByUserId: 'bob' });
      expect(sentBodies()[1]).toEqual({ device_key: 'BobKey12345', id: 'call-call-1', delete: '1' });

      await service.onIncomingCall({ ...incoming, callId: 'call-2' });
      await service.onCallEnded({ ...incoming, callId: 'call-2', wasAnswered: true, endedByUserId: 'alice' });
      expect(sentBodies()[3]).toEqual({ device_key: 'BobKey12345', id: 'call-call-2', delete: '1' });
    });

    it('does not ring someone who has the app open', async () => {
      foreground.add('bob');
      await service.onIncomingCall(incoming);
      await service.onCallEnded({ ...incoming, wasAnswered: false, endedByUserId: 'alice' });

      expect(fetchMock).not.toHaveBeenCalled();
    });
  });
});

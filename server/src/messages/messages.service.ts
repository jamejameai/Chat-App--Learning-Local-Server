import {
  Injectable,
  ForbiddenException,
  NotFoundException,
  Logger,
} from '@nestjs/common';
import { DatabaseService } from '../database/database.service';
import { SubmitMessageDto } from './dto/submit-message.dto';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { BarkRelayService } from '../notifications/bark-relay.service';

@Injectable()
export class MessagesService {
  private readonly logger = new Logger(MessagesService.name);

  constructor(
    private readonly db: DatabaseService,
    private readonly realtimeGateway: RealtimeGateway,
    private readonly barkRelay: BarkRelayService,
  ) {}

  async submitMessage(
    userId: string,
    deviceId: string,
    conversationId: string,
    dto: SubmitMessageDto,
  ) {
    // 1. Verify membership
    const memberRes = await this.db.query(
      'SELECT id, role FROM conversation_members WHERE conversation_id = $1 AND user_id = $2',
      [conversationId, userId],
    );

    if (memberRes.rows.length === 0) {
      throw new ForbiddenException('Not an authorized member of this conversation');
    }

    if (memberRes.rows[0].role === 'read_only') {
      throw new ForbiddenException('Read-only members cannot publish messages to this channel');
    }

    // 2. Check for idempotency: if message with this UUID already exists, return it
    const existing = await this.db.query(
      'SELECT id, sequence_id, created_at FROM messages WHERE id = $1',
      [dto.id],
    );
    if (existing.rows.length > 0) {
      return {
        id: existing.rows[0].id,
        conversation_id: conversationId,
        sender_user_id: userId,
        sender_device_id: deviceId,
        sequence_id: existing.rows[0].sequence_id,
        created_at: existing.rows[0].created_at,
        status: 'accepted',
        deduplicated: true,
      };
    }

    // 3. Atomically allocate sequence_id and insert envelope
    const message = await this.db.transaction(async (client) => {
      const seqRes = await client.query(
        `UPDATE conversations
         SET last_sequence_id = last_sequence_id + 1,
             last_message_at = NOW(),
             updated_at = NOW()
         WHERE id = $1
         RETURNING last_sequence_id`,
        [conversationId],
      );

      const sequenceId = seqRes.rows[0].last_sequence_id;

      const insertRes = await client.query(
        `INSERT INTO messages (
          id, conversation_id, sender_user_id, sender_device_id,
          sequence_id, envelope_type, encrypted_payload, iv, reply_to_message_id
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        RETURNING id, sequence_id, created_at`,
        [
          dto.id,
          conversationId,
          userId,
          deviceId,
          sequenceId,
          dto.envelope_type,
          dto.encrypted_payload,
          dto.iv,
          dto.reply_to_message_id || null,
        ],
      );

      // The sender has read their own message: it must never count as unread (badge) for them
      await client.query(
        `UPDATE conversation_members
         SET last_read_sequence_id = GREATEST(last_read_sequence_id, $1)
         WHERE conversation_id = $2 AND user_id = $3`,
        [sequenceId, conversationId, userId],
      );

      return {
        id: insertRes.rows[0].id,
        conversation_id: conversationId,
        sender_user_id: userId,
        sender_device_id: deviceId,
        sequence_id: insertRes.rows[0].sequence_id,
        envelope_type: dto.envelope_type,
        encrypted_payload: dto.encrypted_payload,
        iv: dto.iv,
        reply_to_message_id: dto.reply_to_message_id || null,
        created_at: insertRes.rows[0].created_at,
        status: 'accepted',
        deduplicated: false,
      };
    });

    // 4. Push in real time to the other members (fire-and-forget; the sender is not kept waiting)
    void this.realtimeGateway.notifyNewMessage(conversationId, message);
    // ...and alert those whose app is closed or in the background
    void this.barkRelay.onNewMessage(conversationId, userId, dto.envelope_type);

    return message;
  }

  async recordReceipt(
    userId: string,
    deviceId: string,
    conversationId: string,
    messageId: string,
    status: 'delivered' | 'read',
  ) {
    // 1. Verify message exists
    const msgRes = await this.db.query(
      'SELECT id, sequence_id FROM messages WHERE id = $1 AND conversation_id = $2',
      [messageId, conversationId],
    );
    if (msgRes.rows.length === 0) {
      throw new NotFoundException('Message not found');
    }

    // 2. Insert receipt with deduplication
    await this.db.query(
      `INSERT INTO message_receipts (message_id, user_id, device_id, status, timestamp)
       VALUES ($1, $2, $3, $4, NOW())
       ON CONFLICT (message_id, device_id, status) DO NOTHING`,
      [messageId, userId, deviceId, status],
    );

    // 3. If read, update last_read_sequence_id on conversation_members
    if (status === 'read') {
      const seq = msgRes.rows[0].sequence_id;
      await this.db.query(
        `UPDATE conversation_members
         SET last_read_sequence_id = GREATEST(last_read_sequence_id, $1)
         WHERE conversation_id = $2 AND user_id = $3`,
        [seq, conversationId, userId],
      );
      // The chat has been read: its alert on the phone is no longer needed
      void this.barkRelay.onConversationRead(userId, conversationId);
    }

    const receiptPayload = {
      message_id: messageId,
      // Lets the sender mark every message up to this one as seen
      sequence_id: msgRes.rows[0].sequence_id,
      conversation_id: conversationId,
      user_id: userId,
      device_id: deviceId,
      status,
      timestamp: new Date().toISOString(),
    };

    // 4. Broadcast receipt event over WebSocket
    void this.realtimeGateway.notifyReceipt(conversationId, receiptPayload);

    return { success: true, ...receiptPayload };
  }
}

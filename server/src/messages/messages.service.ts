import {
  Injectable,
  ForbiddenException,
  Logger,
} from '@nestjs/common';
import { DatabaseService } from '../database/database.service';
import { SubmitMessageDto } from './dto/submit-message.dto';

@Injectable()
export class MessagesService {
  private readonly logger = new Logger(MessagesService.name);

  constructor(private readonly db: DatabaseService) {}

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
        sequence_id: existing.rows[0].sequence_id,
        created_at: existing.rows[0].created_at,
        status: 'accepted',
        deduplicated: true,
      };
    }

    // 3. Atomically allocate sequence_id and insert envelope
    return await this.db.transaction(async (client) => {
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

      return {
        id: insertRes.rows[0].id,
        sequence_id: insertRes.rows[0].sequence_id,
        created_at: insertRes.rows[0].created_at,
        status: 'accepted',
        deduplicated: false,
      };
    });
  }
}

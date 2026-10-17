import {
  Injectable,
  NotFoundException,
  ForbiddenException,
  BadRequestException,
  Logger,
} from '@nestjs/common';
import { DatabaseService } from '../database/database.service';
import { CreateConversationDto } from './dto/create-conversation.dto';
import { RealtimeGateway } from '../realtime/realtime.gateway';

@Injectable()
export class ConversationsService {
  private readonly logger = new Logger(ConversationsService.name);

  constructor(
    private readonly db: DatabaseService,
    private readonly realtimeGateway: RealtimeGateway,
  ) {}

  async listConversations(userId: string) {
    const res = await this.db.query(
      `SELECT c.id, c.type, c.title, c.avatar_url, c.last_sequence_id, c.last_message_at, c.created_at,
              cm.role, cm.last_read_sequence_id, cm.is_pinned, cm.is_muted,
              (c.last_sequence_id - cm.last_read_sequence_id) as unread_count,
              (SELECT COUNT(*) FROM conversation_members WHERE conversation_id = c.id) as member_count
       FROM conversations c
       JOIN conversation_members cm ON cm.conversation_id = c.id
       WHERE cm.user_id = $1
       ORDER BY cm.is_pinned DESC, c.last_message_at DESC NULLS LAST, c.created_at DESC`,
      [userId],
    );

    // For direct chats, enhance with recipient's display name and avatar
    const conversations = [];
    for (const conv of res.rows) {
      if (conv.type === 'direct') {
        const otherRes = await this.db.query(
          `SELECT u.id, u.username, u.display_name, u.avatar_url
           FROM conversation_members cm
           JOIN users u ON u.id = cm.user_id
           WHERE cm.conversation_id = $1 AND cm.user_id != $2
           LIMIT 1`,
          [conv.id, userId],
        );
        if (otherRes.rows.length > 0) {
          const other = otherRes.rows[0];
          conv.title = other.display_name || other.username;
          conv.avatar_url = other.avatar_url;
          conv.recipient_user_id = other.id;
        }
      }
      conversations.push(conv);
    }

    return conversations;
  }

  async createConversation(creatorUserId: string, dto: CreateConversationDto) {
    if (dto.type === 'direct') {
      if (dto.participant_user_ids.length !== 1) {
        throw new BadRequestException('Direct conversation requires exactly one other participant');
      }
      const recipientId = dto.participant_user_ids[0];
      if (recipientId === creatorUserId) {
        throw new BadRequestException('Cannot start direct conversation with yourself');
      }

      // Check if direct conversation already exists between these two users
      const existingRes = await this.db.query(
        `SELECT c.id 
         FROM conversations c
         JOIN conversation_members cm1 ON cm1.conversation_id = c.id AND cm1.user_id = $1
         JOIN conversation_members cm2 ON cm2.conversation_id = c.id AND cm2.user_id = $2
         WHERE c.type = 'direct'
         LIMIT 1`,
        [creatorUserId, recipientId],
      );
      if (existingRes.rows.length > 0) {
        return await this.getConversation(existingRes.rows[0].id, creatorUserId);
      }
    }

    return await this.db.transaction(async (client) => {
      // 1. Insert conversation
      const convRes = await client.query(
        `INSERT INTO conversations (type, title, created_by_user_id)
         VALUES ($1, $2, $3)
         RETURNING id, type, title, created_by_user_id, last_sequence_id, created_at`,
        [dto.type, dto.title || null, creatorUserId],
      );
      const conv = convRes.rows[0];

      // 2. Add creator as owner/admin
      await client.query(
        `INSERT INTO conversation_members (conversation_id, user_id, role)
         VALUES ($1, $2, 'owner')`,
        [conv.id, creatorUserId],
      );

      // 3. Add other members
      for (const pId of dto.participant_user_ids) {
        if (pId !== creatorUserId) {
          await client.query(
            `INSERT INTO conversation_members (conversation_id, user_id, role)
             VALUES ($1, $2, 'member')
             ON CONFLICT (conversation_id, user_id) DO NOTHING`,
            [conv.id, pId],
          );
        }
      }

      return conv;
    });
  }

  async getConversation(conversationId: string, userId: string) {
    const memRes = await this.db.query(
      `SELECT cm.role, c.id, c.type, c.title, c.avatar_url, c.last_sequence_id, c.last_message_at, c.created_at
       FROM conversations c
       JOIN conversation_members cm ON cm.conversation_id = c.id
       WHERE c.id = $1 AND cm.user_id = $2`,
      [conversationId, userId],
    );

    if (memRes.rows.length === 0) {
      throw new ForbiddenException('Not a member of this conversation');
    }

    const conv = memRes.rows[0];

    // Fetch members
    const membersRes = await this.db.query(
      `SELECT u.id, u.username, u.display_name, u.avatar_url, cm.role, cm.joined_at
       FROM conversation_members cm
       JOIN users u ON u.id = cm.user_id
       WHERE cm.conversation_id = $1
       ORDER BY cm.role ASC, cm.joined_at ASC`,
      [conversationId],
    );
    conv.members = membersRes.rows;

    return conv;
  }

  async syncConversation(
    conversationId: string,
    userId: string,
    sinceSequence = 0,
    limit = 50,
  ) {
    // 1. Validate membership
    const memRes = await this.db.query(
      'SELECT id, last_read_sequence_id FROM conversation_members WHERE conversation_id = $1 AND user_id = $2',
      [conversationId, userId],
    );
    if (memRes.rows.length === 0) {
      throw new ForbiddenException('Not a member of this conversation');
    }

    // 2. Query messages
    const msgsRes = await this.db.query(
      `SELECT m.id, m.conversation_id, m.sender_user_id, m.sender_device_id,
              m.sequence_id, m.envelope_type, m.encrypted_payload, m.iv,
              m.reply_to_message_id, m.is_edited, m.is_deleted, m.created_at,
              u.username as sender_username, u.display_name as sender_display_name
       FROM messages m
       JOIN users u ON u.id = m.sender_user_id
       WHERE m.conversation_id = $1 AND m.sequence_id > $2
       ORDER BY m.sequence_id ASC
       LIMIT $3`,
      [conversationId, sinceSequence, limit],
    );

    const convRes = await this.db.query(
      'SELECT last_sequence_id FROM conversations WHERE id = $1',
      [conversationId],
    );

    return {
      conversation_id: conversationId,
      messages: msgsRes.rows,
      latest_sequence_id: convRes.rows[0]?.last_sequence_id || 0,
      has_more: msgsRes.rows.length === limit,
    };
  }

  async addMembers(conversationId: string, currentUserId: string, memberUserIds: string[]) {
    // 1. Verify caller has admin/owner privileges in this group
    const callerRes = await this.db.query(
      'SELECT role FROM conversation_members WHERE conversation_id = $1 AND user_id = $2',
      [conversationId, currentUserId],
    );
    if (callerRes.rows.length === 0 || !['owner', 'admin'].includes(callerRes.rows[0].role)) {
      throw new ForbiddenException('Only group owners or admins can add members');
    }

    for (const userId of memberUserIds) {
      await this.db.query(
        `INSERT INTO conversation_members (conversation_id, user_id, role)
         VALUES ($1, $2, 'member')
         ON CONFLICT (conversation_id, user_id) DO NOTHING`,
        [conversationId, userId],
      );
    }

    this.realtimeGateway.server.to(`conv:${conversationId}`).emit('conversation.member_updated', {
      conversation_id: conversationId,
      action: 'added',
      user_ids: memberUserIds,
    });

    return await this.getConversation(conversationId, currentUserId);
  }

  async removeMember(conversationId: string, currentUserId: string, targetUserId: string) {
    const callerRes = await this.db.query(
      'SELECT role FROM conversation_members WHERE conversation_id = $1 AND user_id = $2',
      [conversationId, currentUserId],
    );
    if (callerRes.rows.length === 0) {
      throw new ForbiddenException('Not a member of this conversation');
    }
    const callerRole = callerRes.rows[0].role;

    // Self-leave is permitted; otherwise caller must be owner/admin
    if (currentUserId !== targetUserId) {
      if (!['owner', 'admin'].includes(callerRole)) {
        throw new ForbiddenException('Only owners and admins can remove group members');
      }
      // Check target is not owner
      const targetRes = await this.db.query(
        'SELECT role FROM conversation_members WHERE conversation_id = $1 AND user_id = $2',
        [conversationId, targetUserId],
      );
      if (targetRes.rows.length > 0 && targetRes.rows[0].role === 'owner') {
        throw new ForbiddenException('Group owner cannot be removed');
      }
    }

    await this.db.query(
      'DELETE FROM conversation_members WHERE conversation_id = $1 AND user_id = $2',
      [conversationId, targetUserId],
    );

    // Cryptographic re-key notification: remaining members MUST rotate Sender Key
    this.realtimeGateway.server.to(`conv:${conversationId}`).emit('conversation.rekey_required', {
      conversation_id: conversationId,
      evicted_user_id: targetUserId,
      reason: 'member_removed',
    });

    return { success: true, removed_user_id: targetUserId };
  }

  async updateMemberRole(
    conversationId: string,
    currentUserId: string,
    targetUserId: string,
    role: 'admin' | 'member' | 'read_only',
  ) {
    const callerRes = await this.db.query(
      'SELECT role FROM conversation_members WHERE conversation_id = $1 AND user_id = $2',
      [conversationId, currentUserId],
    );
    if (callerRes.rows.length === 0 || callerRes.rows[0].role !== 'owner') {
      throw new ForbiddenException('Only the group owner can change member roles');
    }

    await this.db.query(
      'UPDATE conversation_members SET role = $1 WHERE conversation_id = $2 AND user_id = $3',
      [role, conversationId, targetUserId],
    );

    this.realtimeGateway.server.to(`conv:${conversationId}`).emit('conversation.member_updated', {
      conversation_id: conversationId,
      action: 'role_changed',
      user_id: targetUserId,
      role,
    });

    return { success: true, user_id: targetUserId, role };
  }
}

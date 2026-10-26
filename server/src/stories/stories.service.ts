import { BadRequestException, Injectable, Logger, NotFoundException } from '@nestjs/common';
import * as crypto from 'crypto';
import { DatabaseService } from '../database/database.service';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { CreateStoryDto } from './dto/create-story.dto';

/**
 * 24-hour photo stories shared with your friends, like Telegram. The feed is grouped by person so
 * the app can draw a coloured ring around anyone with a story you haven't seen yet.
 */
@Injectable()
export class StoriesService {
  private readonly logger = new Logger(StoriesService.name);

  constructor(
    private readonly db: DatabaseService,
    private readonly realtime: RealtimeGateway,
  ) {}

  async createStory(userId: string, dto: CreateStoryDto) {
    const owned = await this.db.query(
      'SELECT id FROM attachments WHERE id = $1 AND uploaded_by_user_id = $2',
      [dto.attachment_id, userId],
    );
    if (owned.rows.length === 0) {
      throw new BadRequestException('Upload the photo before posting it as a story');
    }

    const caption = dto.caption?.trim() || null;
    const res = await this.db.query(
      `INSERT INTO stories (user_id, attachment_id, media_key, media_iv, media_sha256, mime_type, caption)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING id, created_at, expires_at`,
      [userId, dto.attachment_id, dto.media_key, dto.media_iv, dto.media_sha256, dto.mime_type, caption],
    );
    const story = res.rows[0];

    await this.notifyFriends(userId, story.id);
    return story;
  }

  /** My stories and my friends' live stories, grouped by person. */
  async getFeed(userId: string) {
    const res = await this.db.query(
      `SELECT s.id, s.user_id, u.username, u.display_name, u.avatar_url, u.role, u.border_template, u.name_color,
              s.attachment_id, s.media_key, s.media_iv, s.media_sha256, s.mime_type, s.caption,
              s.created_at, s.expires_at,
              EXISTS (SELECT 1 FROM story_views v WHERE v.story_id = s.id AND v.viewer_id = $1) AS viewed,
              (SELECT COUNT(*) FROM story_views v WHERE v.story_id = s.id) AS view_count,
              (
                SELECT COALESCE(json_agg(json_build_object('reaction', sub.reaction, 'count', sub.cnt)), '[]'::json)
                FROM (
                  SELECT reaction, COUNT(*)::int as cnt
                  FROM story_reactions
                  WHERE story_id = s.id
                  GROUP BY reaction
                  ORDER BY cnt DESC
                ) sub
              ) as reactions_summary
       FROM stories s
       JOIN users u ON u.id = s.user_id
       WHERE s.expires_at > NOW()
         AND (s.user_id = $1 OR s.user_id IN (
               SELECT friend_id FROM friendships WHERE user_id = $1 AND status = 'accepted'))
       ORDER BY s.created_at ASC`,
      [userId],
    );

    const groups = new Map<string, any>();
    for (const row of res.rows) {
      const isMe = row.user_id === userId;
      let group = groups.get(row.user_id);
      if (!group) {
        group = {
          user_id: row.user_id,
          username: row.username,
          display_name: row.display_name,
          avatar_url: row.avatar_url,
          role: row.role || 'member',
          border_template: row.border_template || 'platinumExecutive',
          name_color: row.name_color || (row.role === 'owner' || row.username?.toLowerCase() === 'jame.kh' ? '#FF3B30' : null),
          is_me: isMe,
          has_unseen: false,
          latest_at: row.created_at,
          stories: [],
        };
        groups.set(row.user_id, group);
      }
      if (!isMe && !row.viewed) group.has_unseen = true;
      if (new Date(row.created_at) > new Date(group.latest_at)) group.latest_at = row.created_at;
      group.stories.push({
        id: row.id,
        attachment_id: row.attachment_id,
        media_key: row.media_key,
        media_iv: row.media_iv,
        media_sha256: row.media_sha256,
        mime_type: row.mime_type,
        caption: row.caption,
        created_at: row.created_at,
        expires_at: row.expires_at,
        viewed: isMe || row.viewed,
        view_count: isMe ? Number(row.view_count) : null,
        reactions_summary: row.reactions_summary || [],
      });
    }

    // Mine first, then unseen before seen, each newest first
    return [...groups.values()].sort((a, b) => {
      if (a.is_me !== b.is_me) return a.is_me ? -1 : 1;
      if (a.has_unseen !== b.has_unseen) return a.has_unseen ? -1 : 1;
      return new Date(b.latest_at).getTime() - new Date(a.latest_at).getTime();
    });
  }

  async markViewed(storyId: string, viewerId: string) {
    const ownerId = await this.visibleStoryOwner(storyId, viewerId);
    if (ownerId === viewerId) return { success: true };

    await this.db.query(
      `INSERT INTO story_views (story_id, viewer_id) VALUES ($1, $2)
       ON CONFLICT (story_id, viewer_id) DO NOTHING`,
      [storyId, viewerId],
    );
    return { success: true };
  }

  /** Who has seen one of my stories. */
  async getViewers(storyId: string, ownerId: string) {
    await this.ownStory(storyId, ownerId);
    const res = await this.db.query(
      `SELECT u.id AS user_id, u.username, u.display_name, u.avatar_url, v.viewed_at
       FROM story_views v JOIN users u ON u.id = v.viewer_id
       WHERE v.story_id = $1
       ORDER BY v.viewed_at DESC`,
      [storyId],
    );
    return res.rows;
  }

  async deleteStory(storyId: string, ownerId: string) {
    await this.ownStory(storyId, ownerId);
    await this.db.query('DELETE FROM stories WHERE id = $1', [storyId]);
    return { success: true };
  }

  /** Owner of a live story the viewer may see (their own or a friend's); otherwise 404. */
  private async visibleStoryOwner(storyId: string, viewerId: string): Promise<string> {
    const res = await this.db.query(
      `SELECT s.user_id FROM stories s
       WHERE s.id = $1 AND s.expires_at > NOW()
         AND (s.user_id = $2 OR EXISTS (
               SELECT 1 FROM friendships f
               WHERE f.user_id = $2 AND f.friend_id = s.user_id AND f.status = 'accepted'))`,
      [storyId, viewerId],
    );
    if (res.rows.length === 0) throw new NotFoundException('Story not found');
    return res.rows[0].user_id;
  }

  private async ownStory(storyId: string, ownerId: string) {
    const res = await this.db.query('SELECT id FROM stories WHERE id = $1 AND user_id = $2', [storyId, ownerId]);
    if (res.rows.length === 0) throw new NotFoundException('Story not found');
  }

  async reactToStory(storyId: string, userId: string, reaction: string) {
    const storyOwnerId = await this.visibleStoryOwner(storyId, userId);

    await this.db.query(
      `INSERT INTO story_reactions (story_id, user_id, reaction)
       VALUES ($1, $2, $3)
       ON CONFLICT (story_id, user_id) DO UPDATE SET reaction = $3, created_at = NOW()`,
      [storyId, userId, reaction],
    );

    const userRes = await this.db.query(
      'SELECT username, display_name, avatar_url, role, name_color FROM users WHERE id = $1',
      [userId],
    );
    const user = userRes.rows[0] || {};

    const reactionPayload = {
      story_id: storyId,
      user_id: userId,
      username: user.username,
      display_name: user.display_name,
      avatar_url: user.avatar_url,
      role: user.role,
      name_color: user.name_color ?? (user.role === 'owner' || user.username?.toLowerCase() === 'jame.kh' ? '#FF3B30' : null),
      reaction,
    };

    // Broadcast to EVERYONE so all viewers see the live reaction float up
    this.realtime.server.emit('story:reaction', reactionPayload);

    return { success: true, story_id: storyId, reaction };
  }

  async getStoryReactions(storyId: string, viewerId: string) {
    await this.visibleStoryOwner(storyId, viewerId);

    const res = await this.db.query(
      `SELECT r.reaction, r.created_at, u.id as user_id, u.username, u.display_name, u.avatar_url, u.role, u.name_color
       FROM story_reactions r
       JOIN users u ON u.id = r.user_id
       WHERE r.story_id = $1
       ORDER BY r.created_at DESC`,
      [storyId],
    );

    const counts: Record<string, number> = {};
    for (const row of res.rows) {
      counts[row.reaction] = (counts[row.reaction] || 0) + 1;
    }

    return {
      reactions: res.rows.map((r) => ({
        ...r,
        name_color: r.name_color ?? (r.role === 'owner' || r.username?.toLowerCase() === 'jame.kh' ? '#FF3B30' : null),
      })),
      counts,
      total: res.rows.length,
    };
  }

  async replyToStory(storyId: string, userId: string, text: string) {
    const cleanText = text.trim();
    if (!cleanText) {
      throw new BadRequestException('Reply text cannot be empty');
    }

    const storyOwnerId = await this.visibleStoryOwner(storyId, userId);
    if (storyOwnerId === userId) {
      throw new BadRequestException('Cannot reply to your own story');
    }

    // Find or create direct conversation with the story author
    let convId: string;
    const convRes = await this.db.query(
      `SELECT c.id 
       FROM conversations c
       JOIN conversation_members m1 ON c.id = m1.conversation_id AND m1.user_id = $1
       JOIN conversation_members m2 ON c.id = m2.conversation_id AND m2.user_id = $2
       WHERE c.type = 'direct'
       LIMIT 1`,
      [userId, storyOwnerId],
    );

    if (convRes.rows.length > 0) {
      convId = convRes.rows[0].id;
    } else {
      const ownerRes = await this.db.query('SELECT display_name, username FROM users WHERE id = $1', [storyOwnerId]);
      const newConv = await this.db.query(
        `INSERT INTO conversations (type, title, created_by_user_id)
         VALUES ('direct', $1, $2)
         RETURNING id`,
        [ownerRes.rows[0]?.display_name || ownerRes.rows[0]?.username || 'Direct Chat', userId],
      );
      convId = newConv.rows[0].id;
      await this.db.query(
        `INSERT INTO conversation_members (conversation_id, user_id, role)
         VALUES ($1, $2, 'member'), ($1, $3, 'member')`,
        [convId, userId, storyOwnerId],
      );
    }

    const senderRes = await this.db.query(
      'SELECT username, display_name, avatar_url, role, name_color FROM users WHERE id = $1',
      [userId],
    );
    const sender = senderRes.rows[0] || {};

    // Insert real message into conversation so it appears in chat
    const msgId = crypto.randomUUID();
    const payloadText = JSON.stringify({
      text: cleanText,
      reply_to_story_id: storyId,
    });
    const payloadBase64 = Buffer.from(payloadText, 'utf8').toString('base64');
    const ivBase64 = crypto.randomBytes(12).toString('base64');

    const msgRecord = await this.db.transaction(async (client) => {
      const seqRes = await client.query(
        `UPDATE conversations
         SET last_sequence_id = last_sequence_id + 1,
             last_message_at = NOW(),
             updated_at = NOW()
         WHERE id = $1
         RETURNING last_sequence_id`,
        [convId],
      );
      const sequenceId = seqRes.rows[0].last_sequence_id;

      const ins = await client.query(
        `INSERT INTO messages (
          id, conversation_id, sender_user_id, sender_device_id,
          sequence_id, envelope_type, encrypted_payload, iv
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        RETURNING id, sequence_id, created_at`,
        [msgId, convId, userId, 'story_reply', sequenceId, 'e2ee_text', payloadBase64, ivBase64],
      );

      // Sender read own message
      await client.query(
        `UPDATE conversation_members
         SET last_read_sequence_id = GREATEST(last_read_sequence_id, $1)
         WHERE conversation_id = $2 AND user_id = $3`,
        [sequenceId, convId, userId],
      );

      return ins.rows[0];
    });

    const msgEvent = {
      id: msgRecord.id,
      conversation_id: convId,
      sender_user_id: userId,
      sender_username: sender.username,
      sender_display_name: sender.display_name,
      sender_role: sender.role,
      sender_name_color: sender.name_color ?? (sender.role === 'owner' || sender.username?.toLowerCase() === 'jame.kh' ? '#FF3B30' : null),
      sender_device_id: 'story_reply',
      sequence_id: msgRecord.sequence_id,
      envelope_type: 'e2ee_text',
      encrypted_payload: payloadBase64,
      iv: ivBase64,
      created_at: msgRecord.created_at,
    };

    // Emit live message to conversation room and recipient
    this.realtime.server.to(`conversation:${convId}`).emit('message:new', msgEvent);
    this.realtime.emitToUser(storyOwnerId, 'message.new', msgEvent);

    // Notify author of story reply banner
    this.realtime.emitToUser(storyOwnerId, 'story:reply', {
      story_id: storyId,
      sender_id: userId,
      sender_username: sender.username,
      sender_display_name: sender.display_name,
      sender_avatar_url: sender.avatar_url,
      conversation_id: convId,
      text: cleanText,
    });

    return {
      success: true,
      story_id: storyId,
      conversation_id: convId,
      message_id: msgRecord.id,
      message: 'Reply sent to chat',
    };
  }

  /** Lights up the story ring on friends' phones right away. Never fails the post. */
  private async notifyFriends(userId: string, storyId: string) {
    try {
      const friends = await this.db.query(
        `SELECT friend_id FROM friendships WHERE user_id = $1 AND status = 'accepted'`,
        [userId],
      );
      const rooms = friends.rows.map((row) => `user:${row.friend_id}`);
      if (rooms.length === 0) return;
      this.realtime.server.to(rooms).emit('story.new', { user_id: userId, story_id: storyId });
    } catch (err) {
      this.logger.error(`story.new delivery failed for ${userId}: ${err.message}`);
    }
  }
}


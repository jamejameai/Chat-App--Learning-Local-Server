import {
  Injectable,
  BadRequestException,
  NotFoundException,
  ConflictException,
  Logger,
} from '@nestjs/common';
import { DatabaseService } from '../database/database.service';
import { RealtimeGateway } from '../realtime/realtime.gateway';

@Injectable()
export class FriendsService {
  private readonly logger = new Logger(FriendsService.name);

  constructor(
    private readonly db: DatabaseService,
    private readonly realtime: RealtimeGateway,
  ) {}

  async addFriend(userId: string, identifier: string) {
    const cleanId = identifier.trim();

    // Find target user by username, phone_number, or UUID
    const targetRes = await this.db.query(
      `SELECT id, username, display_name, phone_number, avatar_url, bio, status 
       FROM users 
       WHERE (LOWER(username) = LOWER($1) OR phone_number = $1 OR id::text = $1)
       AND status = 'active'`,
      [cleanId],
    );

    if (targetRes.rows.length === 0) {
      throw new NotFoundException('User not found with that username or phone number');
    }

    const targetUser = targetRes.rows[0];
    if (targetUser.id === userId) {
      throw new BadRequestException('You cannot add yourself as a friend');
    }

    // Check if friendship already exists
    const existing = await this.db.query(
      `SELECT id, status FROM friendships WHERE user_id = $1 AND friend_id = $2`,
      [userId, targetUser.id],
    );

    if (existing.rows.length > 0 && existing.rows[0].status === 'accepted') {
      return {
        message: 'Already friends',
        friend: targetUser,
      };
    }

    // Create mutual friendship records (Instagram/Facebook mutual connection)
    await this.db.transaction(async (client) => {
      await client.query(
        `INSERT INTO friendships (user_id, friend_id, status)
         VALUES ($1, $2, 'accepted')
         ON CONFLICT (user_id, friend_id) DO UPDATE SET status = 'accepted', updated_at = NOW()`,
        [userId, targetUser.id],
      );

      await client.query(
        `INSERT INTO friendships (user_id, friend_id, status)
         VALUES ($1, $2, 'accepted')
         ON CONFLICT (user_id, friend_id) DO UPDATE SET status = 'accepted', updated_at = NOW()`,
        [targetUser.id, userId],
      );

      // Check if 1:1 conversation already exists between the two users
      const convRes = await client.query(
        `SELECT c.id 
         FROM conversations c
         JOIN conversation_members m1 ON c.id = m1.conversation_id AND m1.user_id = $1
         JOIN conversation_members m2 ON c.id = m2.conversation_id AND m2.user_id = $2
         WHERE c.type = 'direct'
         LIMIT 1`,
        [userId, targetUser.id],
      );

      // If no direct conversation exists, automatically create one so they can chat & call immediately
      if (convRes.rows.length === 0) {
        const newConv = await client.query(
          `INSERT INTO conversations (type, title, created_by_user_id)
           VALUES ('direct', $1, $2)
           RETURNING id`,
          [`${targetUser.display_name}`, userId],
        );
        const convId = newConv.rows[0].id;

        await client.query(
          `INSERT INTO conversation_members (conversation_id, user_id, role)
           VALUES ($1, $2, 'member'), ($1, $3, 'member')`,
          [convId, userId, targetUser.id],
        );
      }
    });

    const senderRes = await this.db.query(
      'SELECT id, username, display_name, avatar_url, border_template FROM users WHERE id = $1',
      [userId],
    );
    const sender = senderRes.rows[0];
    if (sender) {
      this.realtime.emitToUser(targetUser.id, 'friend:alert', {
        user_id: sender.id,
        username: sender.username,
        display_name: sender.display_name,
        avatar_url: sender.avatar_url,
        border_template: sender.border_template,
        type: 'received',
        message: `${sender.display_name} added you as a friend`,
      });
    }

    return {
      message: 'Friend added successfully',
      friend: targetUser,
    };
  }

  async getFriends(userId: string) {
    const res = await this.db.query(
      `SELECT u.id, u.username, u.display_name, u.phone_number, u.avatar_url, u.bio, u.status, u.role,
              u.cover_url, u.border_template, u.name_color, u.last_seen_at, f.created_at as friends_since,
              (
                SELECT c.id FROM conversations c
                JOIN conversation_members m1 ON c.id = m1.conversation_id AND m1.user_id = $1
                JOIN conversation_members m2 ON c.id = m2.conversation_id AND m2.user_id = u.id
                WHERE c.type = 'direct'
                LIMIT 1
              ) as conversation_id
       FROM friendships f
       JOIN users u ON f.friend_id = u.id
       WHERE f.user_id = $1 AND f.status = 'accepted' AND u.status = 'active'
       ORDER BY u.display_name ASC`,
      [userId],
    );
    return res.rows.map((row) => ({
      ...row,
      name_color: row.name_color ?? (row.role === 'owner' || row.username?.toLowerCase() === 'jame.kh' ? '#FF3B30' : null),
      is_online: Boolean(this.realtime?.isUserOnline?.(row.id)),
      last_seen: row.last_seen_at ? new Date(row.last_seen_at).toISOString() : null,
    }));
  }

  async searchFriends(userId: string, query: string) {
    const cleanQ = query.trim().toLowerCase();
    if (!cleanQ) {
      return [];
    }

    const res = await this.db.query(
      `SELECT u.id, u.username, u.display_name, u.phone_number, u.avatar_url, u.bio, u.status, u.role,
              u.cover_url, u.border_template, u.name_color, u.last_seen_at,
              CASE WHEN f.id IS NOT NULL AND f.status = 'accepted' THEN true ELSE false END as is_friend,
              (
                SELECT c.id FROM conversations c
                JOIN conversation_members m1 ON c.id = m1.conversation_id AND m1.user_id = $1
                JOIN conversation_members m2 ON c.id = m2.conversation_id AND m2.user_id = u.id
                WHERE c.type = 'direct'
                LIMIT 1
              ) as conversation_id
       FROM users u
       LEFT JOIN friendships f ON f.user_id = $1 AND f.friend_id = u.id
       WHERE u.id != $1 AND u.status = 'active'
         AND (LOWER(u.username) LIKE $2 OR LOWER(u.display_name) LIKE $2 OR u.phone_number LIKE $2)
       ORDER BY is_friend DESC, u.display_name ASC
       LIMIT 30`,
      [userId, `%${cleanQ}%`],
    );
    return res.rows.map((row) => ({
      ...row,
      name_color: row.name_color ?? (row.role === 'owner' || row.username?.toLowerCase() === 'jame.kh' ? '#FF3B30' : null),
      is_online: Boolean(this.realtime?.isUserOnline?.(row.id)),
      last_seen: row.last_seen_at ? new Date(row.last_seen_at).toISOString() : null,
    }));
  }

  /** Public profile of another user; phone number only for friends. */
  async getProfile(viewerId: string, userId: string) {
    const userRes = await this.db.query(
      `SELECT id, username, display_name, phone_number, avatar_url, bio, developer_profile, status, role,
              cover_url, border_template, name_color, last_seen_at, created_at
       FROM users WHERE id = $1 AND status = 'active'`,
      [userId],
    );

    if (userRes.rows.length === 0) {
      throw new NotFoundException('User not found');
    }
    const user = userRes.rows[0];

    const friendRes = await this.db.query(
      `SELECT created_at FROM friendships
       WHERE user_id = $1 AND friend_id = $2 AND status = 'accepted'`,
      [viewerId, userId],
    );
    const isFriend = friendRes.rows.length > 0;

    const convRes = await this.db.query(
      `SELECT c.id FROM conversations c
       JOIN conversation_members m1 ON c.id = m1.conversation_id AND m1.user_id = $1
       JOIN conversation_members m2 ON c.id = m2.conversation_id AND m2.user_id = $2
       WHERE c.type = 'direct'
       LIMIT 1`,
      [viewerId, userId],
    );

    return {
      id: user.id,
      username: user.username,
      display_name: user.display_name,
      avatar_url: user.avatar_url,
      bio: user.bio,
      developer_profile: user.developer_profile ?? {},
      status: user.status,
      role: user.role,
      cover_url: user.cover_url ?? null,
      border_template: user.border_template ?? 'platinumExecutive',
      name_color: user.name_color ?? (user.role === 'owner' || user.username?.toLowerCase() === 'jame.kh' ? '#FF3B30' : null),
      created_at: user.created_at,
      phone_number: isFriend ? user.phone_number : null,
      is_friend: isFriend,
      friends_since: isFriend ? friendRes.rows[0].created_at : null,
      conversation_id: convRes.rows[0]?.id ?? null,
      is_online: Boolean(this.realtime?.isUserOnline?.(userId)),
      last_seen: user.last_seen_at ? new Date(user.last_seen_at).toISOString() : null,
    };

  }

  async removeFriend(userId: string, friendId: string) {
    const result = await this.db.transaction(async (client) => {
      const removed = await client.query(
        `DELETE FROM friendships
         WHERE (user_id = $1 AND friend_id = $2) OR (user_id = $2 AND friend_id = $1)
         RETURNING user_id`,
        [userId, friendId],
      );
      if (removed.rows.length > 0) {
        const shares = await client.query(
          `SELECT user_id, share_id
           FROM live_locations
           WHERE user_id = ANY($1::uuid[])`,
          [[userId, friendId]],
        );
        await client.query(
          `DELETE FROM live_location_viewers
           WHERE (owner_user_id = $1 AND viewer_user_id = $2)
              OR (owner_user_id = $2 AND viewer_user_id = $1)`,
          [userId, friendId],
        );
        return {
          removed,
          shareIds: new Map<string, string>(
            shares.rows.map((share) => [share.user_id, share.share_id] as const),
          ),
        };
      }
      return { removed, shareIds: new Map<string, string>() };
    });
    if (result.removed.rows.length > 0) {
      this.realtime.notifyLocationAccessRevoked(
        userId,
        friendId,
        result.shareIds.get(userId) ?? null,
        result.shareIds.get(friendId) ?? null,
      );
    }
    return { success: true, message: 'Friend removed' };
  }
}

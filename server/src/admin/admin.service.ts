import {
  Injectable,
  ForbiddenException,
  NotFoundException,
  Logger,
} from '@nestjs/common';
import { DatabaseService } from '../database/database.service';
import { RealtimeGateway } from '../realtime/realtime.gateway';

@Injectable()
export class AdminService {
  private readonly logger = new Logger(AdminService.name);

  constructor(
    private readonly db: DatabaseService,
    private readonly realtime: RealtimeGateway,
  ) {}

  async listAllUsers(search?: string) {
    let query = `
      SELECT u.id, u.username, u.display_name, u.phone_number, u.role, u.status,
             u.border_template, u.cover_url, u.avatar_url, u.bio, u.name_color, u.created_at, u.last_seen_at,
             (SELECT COUNT(*) FROM devices d WHERE d.user_id = u.id AND d.is_revoked = FALSE) AS active_devices,
             (SELECT COUNT(*) FROM friendships f WHERE f.user_id = u.id AND f.status = 'accepted') AS friends_count
      FROM users u
    `;
    const params: any[] = [];

    if (search && search.trim().length > 0) {
      query += ` WHERE (LOWER(u.username) LIKE $1 OR LOWER(u.display_name) LIKE $1 OR u.phone_number LIKE $1)`;
      params.push(`%${search.trim().toLowerCase()}%`);
    }

    query += ` ORDER BY CASE WHEN u.role = 'owner' THEN 0 WHEN u.role = 'superadmin' THEN 1 ELSE 2 END, u.created_at DESC`;

    const res = await this.db.query(query, params);
    return res.rows;
  }

  async updateUserStatus(targetUserId: string, status: string, actorUserId: string) {
    const userRes = await this.db.query('SELECT id, role, username FROM users WHERE id = $1', [targetUserId]);
    if (userRes.rows.length === 0) {
      throw new NotFoundException('User not found');
    }

    const targetUser = userRes.rows[0];
    if (targetUser.role === 'owner' && targetUser.id !== actorUserId) {
      throw new ForbiddenException('Cannot modify the status of the app owner');
    }

    await this.db.query(
      'UPDATE users SET status = $1, updated_at = NOW() WHERE id = $2',
      [status, targetUserId],
    );

    if (status === 'suspended' || status === 'deactivated') {
      await this.revokeUserSessions(targetUserId);
    }

    this.logger.log(`Admin ${actorUserId} changed status of user ${targetUserId} to ${status}`);
    return { success: true, user_id: targetUserId, status };
  }

  async updateUserRole(targetUserId: string, role: string, actorRole: string) {
    if (role === 'owner' && actorRole !== 'owner') {
      throw new ForbiddenException('Only the app owner can transfer or assign the owner role');
    }

    const userRes = await this.db.query('SELECT id, role FROM users WHERE id = $1', [targetUserId]);
    if (userRes.rows.length === 0) {
      throw new NotFoundException('User not found');
    }

    const targetUser = userRes.rows[0];
    if (targetUser.role === 'owner' && actorRole !== 'owner') {
      throw new ForbiddenException('Cannot change the role of the app owner');
    }

    await this.db.query(
      'UPDATE users SET role = $1, updated_at = NOW() WHERE id = $2',
      [role, targetUserId],
    );

    return { success: true, user_id: targetUserId, role };
  }

  async revokeUserSessions(targetUserId: string) {
    await this.db.transaction(async (client) => {
      await client.query(
        'UPDATE devices SET is_revoked = TRUE, revoked_at = NOW() WHERE user_id = $1',
        [targetUserId],
      );
      await client.query(
        'UPDATE user_sessions SET is_revoked = TRUE, updated_at = NOW() WHERE user_id = $1',
        [targetUserId],
      );
    });

    // Notify user to immediately drop session
    this.realtime.emitToUser(targetUserId, 'session:revoked', {
      reason: 'Your active sessions have been revoked by the system administrator.',
    });

    return { success: true, user_id: targetUserId, revoked: true };
  }

  async deleteUser(targetUserId: string, actorRole: string) {
    const userRes = await this.db.query('SELECT id, role FROM users WHERE id = $1', [targetUserId]);
    if (userRes.rows.length === 0) {
      throw new NotFoundException('User not found');
    }

    if (userRes.rows[0].role === 'owner') {
      throw new ForbiddenException('The app owner account cannot be deleted');
    }

    await this.revokeUserSessions(targetUserId);
    await this.db.query('UPDATE users SET status = \'deactivated\', updated_at = NOW() WHERE id = $1', [targetUserId]);

    return { success: true, deleted: true };
  }

  async getSystemStats() {
    const [usersRes, activeUsersRes, convsRes, msgsRes, callsRes] = await Promise.all([
      this.db.query('SELECT COUNT(*) FROM users'),
      this.db.query('SELECT COUNT(*) FROM users WHERE status = \'active\''),
      this.db.query('SELECT COUNT(*) FROM conversations'),
      this.db.query('SELECT COUNT(*) FROM messages'),
      this.db.query('SELECT COUNT(*) FROM calls'),
    ]);

    return {
      total_users: parseInt(usersRes.rows[0]?.count || '0', 10),
      active_users: parseInt(activeUsersRes.rows[0]?.count || '0', 10),
      total_conversations: parseInt(convsRes.rows[0]?.count || '0', 10),
      total_messages: parseInt(msgsRes.rows[0]?.count || '0', 10),
      total_calls: parseInt(callsRes.rows[0]?.count || '0', 10),
      server_time: new Date().toISOString(),
    };
  }

  async broadcastAnnouncement(title: string, message: string, actorUsername: string) {
    this.realtime.broadcastAll('admin:announcement', {
      title,
      message,
      from: actorUsername,
      timestamp: new Date().toISOString(),
    });

    return { success: true, broadcasted: true };
  }
}

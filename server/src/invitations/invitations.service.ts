import {
  Injectable,
  NotFoundException,
  BadRequestException,
  Logger,
} from '@nestjs/common';
import { DatabaseService } from '../database/database.service';
import { CreateInvitationDto } from './dto/create-invitation.dto';
import * as crypto from 'crypto';

@Injectable()
export class InvitationsService {
  private readonly logger = new Logger(InvitationsService.name);

  constructor(private readonly db: DatabaseService) {}

  async createInvitation(creatorUserId: string, dto: CreateInvitationDto) {
    const code = `invite_${crypto.randomBytes(24).toString('base64url')}`;
    const days = dto.expires_in_days || 14;
    const role = dto.role || 'member';

    const res = await this.db.query(
      `INSERT INTO invitations (code, created_by_user_id, role, expires_at)
       VALUES ($1, $2, $3, NOW() + ($4 || ' days')::INTERVAL)
       RETURNING id, code, role, expires_at, created_at`,
      [code, creatorUserId, role, days.toString()],
    );

    // Audit Event
    await this.db.query(
      `INSERT INTO audit_events (actor_user_id, action, target_type, target_id, metadata)
       VALUES ($1, 'invitation.create', 'invitation', $2, $3)`,
      [creatorUserId, res.rows[0].id, JSON.stringify({ role, expires_in_days: days })],
    );

    return res.rows[0];
  }

  async listInvitations(limit = 50, offset = 0) {
    const res = await this.db.query(
      `SELECT i.id, i.code, i.role, i.expires_at, i.revoked, i.used_at, i.created_at,
              u1.username as created_by_username,
              u2.username as used_by_username
       FROM invitations i
       LEFT JOIN users u1 ON u1.id = i.created_by_user_id
       LEFT JOIN users u2 ON u2.id = i.used_by_user_id
       ORDER BY i.created_at DESC
       LIMIT $1 OFFSET $2`,
      [limit, offset],
    );
    return res.rows;
  }

  async revokeInvitation(actorUserId: string, id: string) {
    const res = await this.db.query(
      `UPDATE invitations 
       SET revoked = TRUE 
       WHERE id = $1 AND revoked = FALSE AND used_at IS NULL
       RETURNING id, code`,
      [id],
    );

    if (res.rows.length === 0) {
      throw new NotFoundException('Invitation not found or already redeemed/revoked');
    }

    await this.db.query(
      `INSERT INTO audit_events (actor_user_id, action, target_type, target_id)
       VALUES ($1, 'invitation.revoke', 'invitation', $2)`,
      [actorUserId, id],
    );

    return { success: true, id };
  }
}

import {
  Injectable,
  BadRequestException,
  UnauthorizedException,
  ConflictException,
  Logger,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { DatabaseService } from '../database/database.service';
import { RegisterInviteDto } from './dto/register-invite.dto';
import { LoginDto } from './dto/login.dto';
import * as bcrypt from 'bcrypt';
import * as crypto from 'crypto';

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  constructor(
    private readonly db: DatabaseService,
    private readonly jwtService: JwtService,
  ) {}

  async validateInvitation(code: string) {
    const res = await this.db.query(
      `SELECT id, role, expires_at, revoked, used_at 
       FROM invitations 
       WHERE code = $1`,
      [code],
    );

    if (res.rows.length === 0) {
      throw new BadRequestException('Invalid invitation code');
    }

    const invite = res.rows[0];
    if (invite.revoked) {
      throw new BadRequestException('Invitation has been revoked by an administrator');
    }
    if (invite.used_at) {
      throw new BadRequestException('Invitation has already been redeemed');
    }
    if (new Date(invite.expires_at) < new Date()) {
      throw new BadRequestException('Invitation has expired');
    }

    return {
      valid: true,
      role: invite.role,
      expires_at: invite.expires_at,
    };
  }

  async registerWithInvite(dto: RegisterInviteDto) {
    return await this.db.transaction(async (client) => {
      // 1. Atomically claim invitation
      const inviteRes = await client.query(
        `UPDATE invitations 
         SET used_at = NOW() 
         WHERE code = $1 AND revoked = FALSE AND used_at IS NULL AND expires_at > NOW() 
         RETURNING id, role`,
        [dto.invitation_code],
      );

      if (inviteRes.rows.length === 0) {
        throw new BadRequestException(
          'Invitation code is invalid, expired, or has already been redeemed',
        );
      }
      const invite = inviteRes.rows[0];

      // 2. Check username availability
      const existingUser = await client.query(
        'SELECT id FROM users WHERE LOWER(username) = LOWER($1)',
        [dto.username],
      );
      if (existingUser.rows.length > 0) {
        throw new ConflictException('Username is already taken');
      }

      // 3. Hash password
      const passwordHash = await bcrypt.hash(dto.password, 12);

      // 4. Create user
      const userRes = await client.query(
        `INSERT INTO users (username, display_name, password_hash, role, status)
         VALUES ($1, $2, $3, $4, 'active')
         RETURNING id, username, display_name, role`,
        [dto.username.toLowerCase(), dto.display_name, passwordHash, invite.role],
      );
      const user = userRes.rows[0];

      // 5. Update invitation with used_by_user_id
      await client.query(
        'UPDATE invitations SET used_by_user_id = $1 WHERE id = $2',
        [user.id, invite.id],
      );

      // 6. Register device
      const deviceRes = await client.query(
        `INSERT INTO devices (
          user_id, device_name, platform,
          identity_key_pub, signed_prekey_pub, signed_prekey_sig, signed_prekey_id
        ) VALUES ($1, $2, 'ios', $3, $4, $5, $6)
        RETURNING id, device_name`,
        [
          user.id,
          dto.device_name,
          dto.identity_key_pub,
          dto.signed_prekey_pub,
          dto.signed_prekey_sig,
          dto.signed_prekey_id,
        ],
      );
      const device = deviceRes.rows[0];

      // 7. Store one-time prekeys if provided
      if (dto.one_time_prekeys && dto.one_time_prekeys.length > 0) {
        for (const prekey of dto.one_time_prekeys) {
          await client.query(
            `INSERT INTO device_prekeys (device_id, key_id, public_key)
             VALUES ($1, $2, $3)
             ON CONFLICT (device_id, key_id) DO NOTHING`,
            [device.id, prekey.key_id, prekey.public_key],
          );
        }
      }

      // 8. Generate tokens
      const tokens = await this.generateTokens(user.id, device.id, user.role, user.username);

      // 9. Store refresh token hash
      const refreshTokenHash = crypto
        .createHash('sha256')
        .update(tokens.refresh_token)
        .digest('hex');

      await client.query(
        `INSERT INTO user_sessions (user_id, device_id, refresh_token_hash, expires_at)
         VALUES ($1, $2, $3, NOW() + INTERVAL '30 days')`,
        [user.id, device.id, refreshTokenHash],
      );

      // 10. Audit Event
      await client.query(
        `INSERT INTO audit_events (actor_user_id, action, target_type, target_id)
         VALUES ($1, 'user.register_with_invite', 'user', $2)`,
        [user.id, user.id],
      );

      return {
        user,
        device,
        tokens,
      };
    });
  }

  async login(dto: LoginDto) {
    const userRes = await this.db.query(
      'SELECT id, username, display_name, password_hash, role, status FROM users WHERE LOWER(username) = LOWER($1)',
      [dto.username],
    );

    if (userRes.rows.length === 0) {
      throw new UnauthorizedException('Invalid username or password');
    }

    const user = userRes.rows[0];
    if (user.status !== 'active') {
      throw new UnauthorizedException('Account has been suspended or deactivated');
    }

    const isMatch = await bcrypt.compare(dto.password, user.password_hash);
    if (!isMatch) {
      throw new UnauthorizedException('Invalid username or password');
    }

    // Resolve device
    let deviceId = dto.device_id;
    if (!deviceId) {
      // Find latest active device or create session
      const devRes = await this.db.query(
        'SELECT id, device_name FROM devices WHERE user_id = $1 AND is_revoked = FALSE ORDER BY last_active_at DESC LIMIT 1',
        [user.id],
      );
      if (devRes.rows.length > 0) {
        deviceId = devRes.rows[0].id;
      } else {
        throw new BadRequestException('No registered device found for this account. Please register with invitation.');
      }
    }

    // Update last_active_at
    await this.db.query(
      'UPDATE devices SET last_active_at = NOW() WHERE id = $1',
      [deviceId],
    );

    const tokens = await this.generateTokens(user.id, deviceId, user.role, user.username);
    const refreshTokenHash = crypto
      .createHash('sha256')
      .update(tokens.refresh_token)
      .digest('hex');

    await this.db.query(
      `INSERT INTO user_sessions (user_id, device_id, refresh_token_hash, expires_at)
       VALUES ($1, $2, $3, NOW() + INTERVAL '30 days')`,
      [user.id, deviceId, refreshTokenHash],
    );

    return {
      user: {
        id: user.id,
        username: user.username,
        display_name: user.display_name,
        role: user.role,
      },
      device: { id: deviceId },
      tokens,
    };
  }

  async refresh(refreshToken: string) {
    const tokenHash = crypto.createHash('sha256').update(refreshToken).digest('hex');

    const sessionRes = await this.db.query(
      `SELECT s.id, s.user_id, s.device_id, s.is_revoked, s.expires_at,
              u.role, u.username, u.status, d.is_revoked as device_revoked
       FROM user_sessions s
       JOIN users u ON u.id = s.user_id
       JOIN devices d ON d.id = s.device_id
       WHERE s.refresh_token_hash = $1`,
      [tokenHash],
    );

    if (sessionRes.rows.length === 0) {
      throw new UnauthorizedException('Invalid refresh token');
    }

    const session = sessionRes.rows[0];
    if (session.is_revoked || session.device_revoked) {
      throw new UnauthorizedException('Session or device has been revoked');
    }
    if (session.status !== 'active') {
      throw new UnauthorizedException('Account suspended');
    }
    if (new Date(session.expires_at) < new Date()) {
      throw new UnauthorizedException('Refresh token has expired');
    }

    // Invalidate current refresh token (single-use rotation)
    await this.db.query('UPDATE user_sessions SET is_revoked = TRUE WHERE id = $1', [
      session.id,
    ]);

    // Issue new pair
    const tokens = await this.generateTokens(
      session.user_id,
      session.device_id,
      session.role,
      session.username,
    );

    const newHash = crypto.createHash('sha256').update(tokens.refresh_token).digest('hex');
    await this.db.query(
      `INSERT INTO user_sessions (user_id, device_id, refresh_token_hash, expires_at)
       VALUES ($1, $2, $3, NOW() + INTERVAL '30 days')`,
      [session.user_id, session.device_id, newHash],
    );

    return tokens;
  }

  private async generateTokens(
    userId: string,
    deviceId: string,
    role: string,
    username: string,
  ) {
    const payload = {
      sub: userId,
      device_id: deviceId,
      role,
      username,
    };

    const accessToken = this.jwtService.sign(payload, {
      expiresIn: process.env.JWT_ACCESS_EXPIRES_IN || '15m',
    });

    const refreshToken = `rt_${crypto.randomBytes(48).toString('base64url')}`;

    return {
      access_token: accessToken,
      refresh_token: refreshToken,
    };
  }
}

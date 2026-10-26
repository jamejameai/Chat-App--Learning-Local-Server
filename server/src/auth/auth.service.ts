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
import { RegisterDto, UpdateProfileDto } from './dto/register.dto';
import { LoginDto } from './dto/login.dto';
import * as bcrypt from 'bcrypt';
import * as crypto from 'crypto';

/**
 * A login lasts this many days after the app last refreshed its token (every refresh slides it
 * forward), so a user who opens the app at least once a year never has to log in again.
 */
const SESSION_DAYS = 365;

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
         VALUES ($1, $2, $3, NOW() + INTERVAL '${SESSION_DAYS} days')`,
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

  // Normal registration without mandatory invitation code
  async register(dto: RegisterDto) {
    const cleanUsername = dto.username.toLowerCase().trim();

    // Check username availability
    const existingUser = await this.db.query(
      'SELECT id FROM users WHERE LOWER(username) = $1',
      [cleanUsername],
    );
    if (existingUser.rows.length > 0) {
      throw new ConflictException('Username is already taken');
    }

    // Check phone number availability if provided
    if (dto.phone_number) {
      const cleanPhone = dto.phone_number.trim();
      const existingPhone = await this.db.query(
        'SELECT id FROM users WHERE phone_number = $1',
        [cleanPhone],
      );
      if (existingPhone.rows.length > 0) {
        throw new ConflictException('Phone number is already registered');
      }
    }

    // Hash password
    const passwordHash = await bcrypt.hash(dto.password, 12);

    return await this.db.transaction(async (client) => {
      // Create user
      const userRes = await client.query(
        `INSERT INTO users (username, display_name, phone_number, avatar_url, password_hash, role, status)
         VALUES ($1, $2, $3, $4, $5, 'member', 'active')
         RETURNING id, username, display_name, phone_number, avatar_url, bio, developer_profile, role, status, created_at`,
        [
          cleanUsername,
          dto.display_name.trim(),
          dto.phone_number ? dto.phone_number.trim() : null,
          dto.avatar_url || null,
          passwordHash,
        ],
      );
      const user = userRes.rows[0];

      // Register device
      const deviceRes = await client.query(
        `INSERT INTO devices (
          user_id, device_name, platform,
          identity_key_pub, signed_prekey_pub, signed_prekey_sig, signed_prekey_id
        ) VALUES ($1, $2, 'ios', $3, $4, $5, $6)
        RETURNING id, device_name`,
        [
          user.id,
          dto.device_name || 'iPhone',
          dto.identity_key_pub || 'placeholder-identity-key',
          dto.signed_prekey_pub || 'placeholder-signed-prekey',
          dto.signed_prekey_sig || 'placeholder-signature',
          dto.signed_prekey_id || 1,
        ],
      );
      const device = deviceRes.rows[0];

      // Store one-time prekeys if provided
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

      // Generate tokens
      const tokens = await this.generateTokens(user.id, device.id, user.role, user.username);

      const refreshTokenHash = crypto
        .createHash('sha256')
        .update(tokens.refresh_token)
        .digest('hex');

      await client.query(
        `INSERT INTO user_sessions (user_id, device_id, refresh_token_hash, expires_at)
         VALUES ($1, $2, $3, NOW() + INTERVAL '${SESSION_DAYS} days')`,
        [user.id, device.id, refreshTokenHash],
      );

      await client.query(
        `INSERT INTO audit_events (actor_user_id, action, target_type, target_id)
         VALUES ($1, 'user.register', 'user', $2)`,
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
    const identifier = dto.username.trim();
    // Query by username OR phone number
    const userRes = await this.db.query(
      `SELECT id, username, display_name, phone_number, avatar_url, bio, developer_profile, password_hash, role, status, cover_url, border_template, name_color
       FROM users 
       WHERE LOWER(username) = LOWER($1) OR phone_number = $1`,
      [identifier],
    );

    if (userRes.rows.length === 0) {
      throw new UnauthorizedException('Invalid username/phone or password');
    }

    const user = userRes.rows[0];
    if (user.status !== 'active') {
      throw new UnauthorizedException('Account has been suspended or deactivated');
    }

    const isMatch = await bcrypt.compare(dto.password, user.password_hash);
    if (!isMatch) {
      throw new UnauthorizedException('Invalid username/phone or password');
    }

    // Resolve or auto-register device
    let deviceId = dto.device_id;
    if (!deviceId) {
      const devRes = await this.db.query(
        'SELECT id, device_name FROM devices WHERE user_id = $1 AND is_revoked = FALSE ORDER BY last_active_at DESC LIMIT 1',
        [user.id],
      );
      if (devRes.rows.length > 0) {
        deviceId = devRes.rows[0].id;
      } else {
        const newDev = await this.db.query(
          `INSERT INTO devices (
            user_id, device_name, platform,
            identity_key_pub, signed_prekey_pub, signed_prekey_sig, signed_prekey_id
          ) VALUES ($1, $2, 'ios', $3, $4, $5, 1) RETURNING id`,
          [
            user.id,
            dto.device_name || 'iPhone',
            dto.identity_key_pub || 'placeholder-id-key',
            dto.signed_prekey_pub || 'placeholder-spk',
            dto.signed_prekey_sig || 'placeholder-sig',
          ],
        );
        deviceId = newDev.rows[0].id;
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
       VALUES ($1, $2, $3, NOW() + INTERVAL '${SESSION_DAYS} days')`,
      [user.id, deviceId, refreshTokenHash],
    );

    return {
      user: {
        id: user.id,
        username: user.username,
        display_name: user.display_name,
        phone_number: user.phone_number,
        avatar_url: user.avatar_url,
        bio: user.bio,
        developer_profile: user.developer_profile ?? {},
        role: user.role,
        cover_url: user.cover_url ?? null,
        border_template: user.border_template ?? 'platinumExecutive',
        name_color: user.name_color ?? (user.role === 'owner' || user.username?.toLowerCase() === 'jame.kh' ? '#FF3B30' : null),
      },
      device: { id: deviceId },
      tokens,
    };
  }

  async getUserProfile(userId: string) {
    const res = await this.db.query(
      `SELECT id, username, display_name, phone_number, avatar_url, bio, developer_profile, role, status, created_at, cover_url, border_template, name_color
       FROM users WHERE id = $1`,
      [userId],
    );
    if (res.rows.length === 0) {
      throw new BadRequestException('User not found');
    }
    return res.rows[0];
  }

  async updateProfile(userId: string, dto: UpdateProfileDto) {
    const fields: string[] = [];
    const values: any[] = [];
    let idx = 1;

    if (dto.display_name !== undefined) {
      fields.push(`display_name = $${idx++}`);
      values.push(dto.display_name.trim());
    }
    if (dto.username !== undefined) {
      const cleanUsername = dto.username.toLowerCase().trim();
      const existing = await this.db.query(
        'SELECT id FROM users WHERE LOWER(username) = $1 AND id != $2',
        [cleanUsername, userId],
      );
      if (existing.rows.length > 0) {
        throw new ConflictException('Username is already taken');
      }
      fields.push(`username = $${idx++}`);
      values.push(cleanUsername);
    }
    if (dto.phone_number !== undefined) {
      const cleanPhone = dto.phone_number.trim();
      if (cleanPhone.length > 0) {
        const existing = await this.db.query(
          'SELECT id FROM users WHERE phone_number = $1 AND id != $2',
          [cleanPhone, userId],
        );
        if (existing.rows.length > 0) {
          throw new ConflictException('Phone number is already registered');
        }
        fields.push(`phone_number = $${idx++}`);
        values.push(cleanPhone);
      } else {
        fields.push(`phone_number = NULL`);
      }
    }
    if (dto.avatar_url !== undefined) {
      fields.push(`avatar_url = $${idx++}`);
      values.push(dto.avatar_url);
    }
    if (dto.bio !== undefined) {
      fields.push(`bio = $${idx++}`);
      values.push(dto.bio);
    }
    if (dto.cover_url !== undefined) {
      fields.push(`cover_url = $${idx++}`);
      values.push(dto.cover_url);
    }
    if (dto.border_template !== undefined) {
      fields.push(`border_template = $${idx++}`);
      values.push(dto.border_template);
    }
    if (dto.name_color !== undefined) {
      fields.push(`name_color = $${idx++}`);
      values.push(dto.name_color);
    }
    if (dto.developer_profile !== undefined) {
      fields.push(`developer_profile = $${idx++}::jsonb`);
      values.push(JSON.stringify(dto.developer_profile));
    }

    if (fields.length === 0) {
      return await this.getUserProfile(userId);
    }

    fields.push(`updated_at = NOW()`);
    values.push(userId);

    const res = await this.db.query(
      `UPDATE users SET ${fields.join(', ')} WHERE id = $${idx}
       RETURNING id, username, display_name, phone_number, avatar_url, bio, developer_profile, role, status, cover_url, border_template, name_color`,
      values,
    );
    return res.rows[0];
  }


  async refresh(refreshToken: string) {
    let payload: any;
    try {
      payload = this.jwtService.verify(refreshToken, {
        secret: process.env.JWT_REFRESH_SECRET || 'jwt_refresh_secret',
      });
    } catch {
      throw new UnauthorizedException('Invalid or expired refresh token');
    }

    const refreshTokenHash = crypto
      .createHash('sha256')
      .update(refreshToken)
      .digest('hex');

    const sessionRes = await this.db.query(
      `SELECT id, user_id, device_id 
       FROM user_sessions 
       WHERE refresh_token_hash = $1 AND expires_at > NOW()`,
      [refreshTokenHash],
    );

    if (sessionRes.rows.length === 0) {
      throw new UnauthorizedException('Session expired or revoked');
    }

    const session = sessionRes.rows[0];
    const userRes = await this.db.query(
      'SELECT id, username, role, status FROM users WHERE id = $1',
      [session.user_id],
    );

    if (userRes.rows.length === 0 || userRes.rows[0].status !== 'active') {
      throw new UnauthorizedException('User account inactive');
    }

    const user = userRes.rows[0];
    const tokens = await this.generateTokens(
      user.id,
      session.device_id,
      user.role,
      user.username,
    );

    // Rotate refresh token
    const newHash = crypto
      .createHash('sha256')
      .update(tokens.refresh_token)
      .digest('hex');

    await this.db.query(
      `UPDATE user_sessions 
       SET refresh_token_hash = $1, expires_at = NOW() + INTERVAL '${SESSION_DAYS} days' 
       WHERE id = $2`,
      [newHash, session.id],
    );

    return tokens;
  }

  async listUsers(currentUserId: string, search?: string) {
    let query = `
      SELECT id, username, display_name, phone_number, avatar_url, bio, role, status 
      FROM users 
      WHERE id != $1 AND status = 'active'
    `;
    const params: any[] = [currentUserId];

    if (search && search.trim().length > 0) {
      query += ` AND (LOWER(username) LIKE $2 OR LOWER(display_name) LIKE $2 OR phone_number LIKE $2)`;
      params.push(`%${search.trim().toLowerCase()}%`);
    }

    query += ` ORDER BY display_name ASC LIMIT 50`;

    const res = await this.db.query(query, params);
    return res.rows;
  }

  private async generateTokens(
    userId: string,
    deviceId: string,
    role: string,
    username: string,
  ) {
    const payload = {
      sub: userId,
      deviceId,
      role,
      username,
    };

    const [accessToken, refreshToken] = await Promise.all([
      this.jwtService.signAsync(payload, {
        secret: process.env.JWT_ACCESS_SECRET || 'jwt_access_secret',
        expiresIn: '15m',
      }),
      this.jwtService.signAsync(payload, {
        secret: process.env.JWT_REFRESH_SECRET || 'jwt_refresh_secret',
        expiresIn: `${SESSION_DAYS}d`,
      }),
    ]);

    return {
      access_token: accessToken,
      refresh_token: refreshToken,
      expires_in: 900, // 15 minutes
    };
  }
}

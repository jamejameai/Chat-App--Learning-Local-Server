import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { DatabaseService } from '../database/database.service';

export interface JwtPayload {
  sub: string;       // User ID
  device_id: string; // Device ID
  role: string;      // 'superadmin' | 'member'
  username: string;
}

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(private readonly db: DatabaseService) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey:
        process.env.JWT_ACCESS_SECRET ||
        'replace_with_a_64_char_cryptographically_secure_random_string_access',
    });
  }

  async validate(payload: any) {
    const deviceId = payload.deviceId || payload.device_id;
    // 1. Validate that device is not revoked
    const deviceRes = await this.db.query(
      'SELECT is_revoked FROM devices WHERE id = $1 AND user_id = $2',
      [deviceId, payload.sub],
    );

    if (deviceRes.rows.length === 0 || deviceRes.rows[0].is_revoked) {
      throw new UnauthorizedException('Device has been revoked or does not exist');
    }

    // 2. Validate that user is active
    const userRes = await this.db.query(
      'SELECT status, role FROM users WHERE id = $1',
      [payload.sub],
    );

    if (userRes.rows.length === 0 || userRes.rows[0].status !== 'active') {
      throw new UnauthorizedException('User account is suspended or inactive');
    }

    return {
      userId: payload.sub,
      deviceId,
      role: userRes.rows[0].role,
      username: payload.username,
    };
  }
}

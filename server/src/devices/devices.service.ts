import {
  Injectable,
  NotFoundException,
  ForbiddenException,
  Logger,
} from '@nestjs/common';
import { DatabaseService } from '../database/database.service';
import { OneTimePrekeyDto } from '../auth/dto/register-invite.dto';

@Injectable()
export class DevicesService {
  private readonly logger = new Logger(DevicesService.name);

  constructor(private readonly db: DatabaseService) {}

  async getPrekeyBundle(targetUserId: string) {
    // 1. Find active non-revoked device
    const deviceRes = await this.db.query(
      `SELECT id, identity_key_pub, signed_prekey_pub, signed_prekey_sig, signed_prekey_id
       FROM devices
       WHERE user_id = $1 AND is_revoked = FALSE
       ORDER BY last_active_at DESC
       LIMIT 1`,
      [targetUserId],
    );

    if (deviceRes.rows.length === 0) {
      throw new NotFoundException('No active device found for this recipient');
    }

    const device = deviceRes.rows[0];

    // 2. Atomically consume a one-time prekey using SKIP LOCKED
    const prekeyRes = await this.db.query(
      `UPDATE device_prekeys
       SET is_consumed = TRUE, consumed_at = NOW()
       WHERE id = (
         SELECT id FROM device_prekeys
         WHERE device_id = $1 AND is_consumed = FALSE
         LIMIT 1
         FOR UPDATE SKIP LOCKED
       )
       RETURNING key_id, public_key`,
      [device.id],
    );

    const oneTimePrekey =
      prekeyRes.rows.length > 0
        ? {
            key_id: prekeyRes.rows[0].key_id,
            public_key: prekeyRes.rows[0].public_key,
          }
        : null;

    return {
      user_id: targetUserId,
      device_id: device.id,
      identity_key_pub: device.identity_key_pub,
      signed_prekey_pub: device.signed_prekey_pub,
      signed_prekey_sig: device.signed_prekey_sig,
      signed_prekey_id: device.signed_prekey_id,
      one_time_prekey: oneTimePrekey,
    };
  }

  async refillPrekeys(deviceId: string, prekeys: OneTimePrekeyDto[]) {
    if (!prekeys || prekeys.length === 0) {
      return { added: 0 };
    }

    let added = 0;
    for (const k of prekeys) {
      const res = await this.db.query(
        `INSERT INTO device_prekeys (device_id, key_id, public_key)
         VALUES ($1, $2, $3)
         ON CONFLICT (device_id, key_id) DO NOTHING`,
        [deviceId, k.key_id, k.public_key],
      );
      if (res.rowCount && res.rowCount > 0) {
        added++;
      }
    }
    return { added };
  }

  async listUserDevices(userId: string) {
    const res = await this.db.query(
      `SELECT id, device_name, platform, identity_key_pub, is_revoked, last_active_at, created_at
       FROM devices
       WHERE user_id = $1
       ORDER BY last_active_at DESC`,
      [userId],
    );
    return res.rows;
  }

  async revokeDevice(actorUserId: string, deviceId: string, isSuperAdmin: boolean) {
    const devRes = await this.db.query('SELECT user_id, is_revoked FROM devices WHERE id = $1', [
      deviceId,
    ]);
    if (devRes.rows.length === 0) {
      throw new NotFoundException('Device not found');
    }

    const device = devRes.rows[0];
    if (device.user_id !== actorUserId && !isSuperAdmin) {
      throw new ForbiddenException('Cannot revoke another user\'s device without super-admin role');
    }

    await this.db.transaction(async (client) => {
      await client.query(
        'UPDATE devices SET is_revoked = TRUE, revoked_at = NOW() WHERE id = $1',
        [deviceId],
      );
      await client.query(
        'UPDATE user_sessions SET is_revoked = TRUE WHERE device_id = $1',
        [deviceId],
      );
      await client.query(
        `INSERT INTO audit_events (actor_user_id, action, target_type, target_id)
         VALUES ($1, 'device.revoke', 'device', $2)`,
        [actorUserId, deviceId],
      );
    });

    return { success: true, device_id: deviceId };
  }
}

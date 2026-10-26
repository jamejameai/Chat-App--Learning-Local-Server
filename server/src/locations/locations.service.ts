import { createHash } from 'crypto';
import {
  BadRequestException,
  ConflictException,
  Injectable,
} from '@nestjs/common';
import { DatabaseService } from '../database/database.service';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { StartLocationShareDto } from './dto/start-location-share.dto';
import { UpdateLocationDto } from './dto/update-location.dto';

@Injectable()
export class LocationsService {
  constructor(
    private readonly db: DatabaseService,
    private readonly realtime: RealtimeGateway,
  ) {}

  async beginSharing(userId: string, location: StartLocationShareDto) {
    this.validateLocation(location);
    if (!/^[a-f0-9]{64}$/i.test(location.stop_token ?? '')) {
      throw new BadRequestException('Invalid location stop token');
    }
    const stopTokenHash = createHash('sha256')
      .update(location.stop_token)
      .digest('hex');
    const viewerIds = location.viewer_ids;
    if (
      !Array.isArray(viewerIds) ||
      viewerIds.length === 0 ||
      new Set(viewerIds).size !== viewerIds.length ||
      viewerIds.includes(userId)
    ) {
      throw new BadRequestException('Choose at least one unique friend to share with');
    }
    const shareResult = await this.db.transaction(async (client) => {
      const friends = await client.query(
        `SELECT f.friend_id
         FROM friendships f
         JOIN friendships reciprocal
           ON reciprocal.user_id = f.friend_id
          AND reciprocal.friend_id = f.user_id
          AND reciprocal.status = 'accepted'
         WHERE f.user_id = $1
           AND f.friend_id = ANY($2::uuid[])
           AND f.status = 'accepted'
         FOR SHARE OF f, reciprocal`,
        [userId, viewerIds],
      );
      if (friends.rows.length !== viewerIds.length) {
        throw new BadRequestException('Every selected viewer must be an accepted friend');
      }

      const previous = await client.query(
        `SELECT l.share_id, viewer.viewer_user_id
         FROM live_locations l
         LEFT JOIN live_location_viewers viewer ON viewer.owner_user_id = l.user_id
         WHERE l.user_id = $1
         FOR UPDATE OF l`,
        [userId],
      );
      const result = await client.query(
        `INSERT INTO live_locations (user_id, latitude, longitude, heading, accuracy, stop_token_hash, share_id)
         VALUES ($1, $2, $3, $4, $5, $6, gen_random_uuid())
         ON CONFLICT (user_id) DO UPDATE SET
           latitude = EXCLUDED.latitude,
           longitude = EXCLUDED.longitude,
           heading = EXCLUDED.heading,
           accuracy = EXCLUDED.accuracy,
           stop_token_hash = EXCLUDED.stop_token_hash,
           share_id = EXCLUDED.share_id,
           updated_at = NOW()
         RETURNING user_id, latitude, longitude, heading, accuracy, updated_at, share_id`,
        [
          userId,
          location.latitude,
          location.longitude,
          location.heading ?? null,
          location.accuracy ?? null,
          stopTokenHash,
        ],
      );

      await client.query(
        'DELETE FROM live_location_viewers WHERE owner_user_id = $1',
        [userId],
      );
      await client.query(
        `INSERT INTO live_location_viewers (owner_user_id, viewer_user_id)
         SELECT $1, selected.viewer_user_id
         FROM UNNEST($2::uuid[]) AS selected(viewer_user_id)`,
        [userId, viewerIds],
      );
      return {
        location: result.rows[0],
        previousShare: previous.rows.length > 0
          ? {
              shareId: previous.rows[0].share_id,
              viewerIds: previous.rows
                .map((row) => row.viewer_user_id)
                .filter((viewerId): viewerId is string => viewerId !== null),
            }
          : null,
      };
    });
    if (shareResult.previousShare) {
      await this.realtime.notifyLocationStopped(
        userId,
        shareResult.previousShare.viewerIds,
        shareResult.previousShare.shareId,
      );
    }
    await this.realtime.notifyLocationUpdated(shareResult.location);
    return shareResult.location;
  }

  async updateSharing(userId: string, location: UpdateLocationDto) {
    this.validateLocation(location);
    const result = await this.db.query(
      `UPDATE live_locations
       SET latitude = $2, longitude = $3, heading = $4, accuracy = $5, updated_at = NOW()
       WHERE user_id = $1
       RETURNING user_id, latitude, longitude, heading, accuracy, updated_at, share_id`,
      [userId, location.latitude, location.longitude, location.heading ?? null, location.accuracy ?? null],
    );
    const current = result.rows[0];
    if (!current) {
      throw new ConflictException('Start sharing before sending a location update');
    }
    await this.realtime.notifyLocationUpdated(current);
    return current;
  }

  async getFriendLocations(userId: string) {
    const result = await this.db.query(
      `SELECT l.user_id, l.share_id, u.username, u.display_name, u.avatar_url,
              l.latitude, l.longitude, l.heading, l.accuracy, l.updated_at
       FROM live_locations l
       JOIN users u ON u.id = l.user_id AND u.status = 'active'
       JOIN live_location_viewers viewer
         ON viewer.owner_user_id = l.user_id AND viewer.viewer_user_id = $1
       JOIN friendships f
         ON f.user_id = $1 AND f.friend_id = l.user_id AND f.status = 'accepted'
       JOIN friendships reciprocal
         ON reciprocal.user_id = l.user_id
        AND reciprocal.friend_id = $1
        AND reciprocal.status = 'accepted'
       WHERE l.user_id != $1
       ORDER BY l.updated_at DESC`,
      [userId],
    );
    return result.rows;
  }

  async getShareState(userId: string) {
    const result = await this.db.query(
      `SELECT l.user_id, l.share_id, l.latitude, l.longitude, l.heading, l.accuracy, l.updated_at,
              ARRAY(
                SELECT viewer_user_id
                FROM live_location_viewers
                WHERE owner_user_id = l.user_id
                ORDER BY viewer_user_id
              ) AS viewer_ids
       FROM live_locations l
       WHERE l.user_id = $1`,
      [userId],
    );
    const location = result.rows[0] ?? null;
    return { sharing: location !== null, location };
  }

  async stopSharing(userId: string) {
    const viewerIds = await this.db.transaction(async (client) => {
      const current = await client.query(
        'SELECT user_id, share_id FROM live_locations WHERE user_id = $1 FOR UPDATE',
        [userId],
      );
      if (current.rows.length === 0) return null;

      const viewers = await client.query(
        'SELECT viewer_user_id FROM live_location_viewers WHERE owner_user_id = $1',
        [userId],
      );
      await client.query(
        'DELETE FROM live_locations WHERE user_id = $1',
        [userId],
      );
      return {
        shareId: current.rows[0].share_id,
        viewerIds: viewers.rows.map((row) => row.viewer_user_id),
      };
    });
    if (viewerIds !== null) {
      await this.realtime.notifyLocationStopped(userId, viewerIds.viewerIds, viewerIds.shareId);
    }
    return { sharing: false };
  }

  async stopSharingWithToken(stopToken: string) {
    if (!/^[a-f0-9]{64}$/i.test(stopToken)) {
      throw new BadRequestException('Invalid location stop token');
    }
    const stopTokenHash = createHash('sha256').update(stopToken).digest('hex');
    const stoppedShare = await this.db.transaction(async (client) => {
      const current = await client.query(
        'SELECT user_id, share_id FROM live_locations WHERE stop_token_hash = $1 FOR UPDATE',
        [stopTokenHash],
      );
      if (current.rows.length === 0) return null;

      const userId = current.rows[0].user_id;
      const viewers = await client.query(
        'SELECT viewer_user_id FROM live_location_viewers WHERE owner_user_id = $1',
        [userId],
      );
      await client.query(
        'DELETE FROM live_locations WHERE user_id = $1',
        [userId],
      );
      return {
        userId,
        shareId: current.rows[0].share_id,
        viewerIds: viewers.rows.map((row) => row.viewer_user_id),
      };
    });

    if (stoppedShare) {
      await this.realtime.notifyLocationStopped(
        stoppedShare.userId,
        stoppedShare.viewerIds,
        stoppedShare.shareId,
      );
    }
    return { sharing: false };
  }

  private validateLocation(location: UpdateLocationDto) {
    if (
      !Number.isFinite(location.latitude) ||
      location.latitude < -90 ||
      location.latitude > 90 ||
      !Number.isFinite(location.longitude) ||
      location.longitude < -180 ||
      location.longitude > 180 ||
      (location.heading !== undefined &&
        (!Number.isFinite(location.heading) || location.heading < 0 || location.heading >= 360)) ||
      (location.accuracy !== undefined &&
        (!Number.isFinite(location.accuracy) || location.accuracy < 0 || location.accuracy > 10000))
    ) {
      throw new BadRequestException('Invalid location coordinates or movement metadata');
    }
  }
}

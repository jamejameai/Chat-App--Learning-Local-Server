import {
  WebSocketGateway,
  WebSocketServer,
  SubscribeMessage,
  OnGatewayConnection,
  OnGatewayDisconnect,
  ConnectedSocket,
  MessageBody,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { Logger, UseGuards } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { DatabaseService } from '../database/database.service';

@WebSocketGateway({
  cors: {
    origin: '*',
  },
})
export class RealtimeGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server: Server;

  private readonly logger = new Logger(RealtimeGateway.name);
  // Map of userId -> Set of Socket IDs
  private userSockets = new Map<string, Set<string>>();
  // Socket IDs whose app is on screen (sent by the app as `app_state`); the rest are in the background
  private foregroundSockets = new Set<string>();

  constructor(
    private readonly jwtService: JwtService,
    private readonly db: DatabaseService,
  ) {}

  async handleConnection(socket: Socket) {
    try {
      const token =
        socket.handshake.auth?.token ||
        socket.handshake.headers?.authorization?.replace('Bearer ', '') ||
        (socket.handshake.query?.token as string);

      if (!token) {
        this.logger.warn(`Unauthorized WebSocket connection rejected: ${socket.id}`);
        socket.disconnect();
        return;
      }

      const payload = this.jwtService.verify(token, {
        secret:
          process.env.JWT_ACCESS_SECRET ||
          'replace_with_a_64_char_cryptographically_secure_random_string_access',
      });

      // AuthService signs the claim as "deviceId"; older tokens used "device_id"
      const deviceId = payload.deviceId || payload.device_id;

      socket.data = {
        userId: payload.sub,
        deviceId,
        role: payload.role,
        username: payload.username,
      };

      // Add socket to user map
      if (!this.userSockets.has(payload.sub)) {
        this.userSockets.set(payload.sub, new Set());
      }
      this.userSockets.get(payload.sub).add(socket.id);
      // Apps that don't say count as background, so they never hold back an alert
      this.setAppState(socket.id, socket.handshake.query?.app_state);

      // Join room for this user
      socket.join(`user:${payload.sub}`);
      socket.join(`device:${deviceId}`);

      this.logger.log(
        `Client connected: user=${payload.username} (${payload.sub}), device=${deviceId}, socket=${socket.id}`,
      );

      const now = new Date().toISOString();
      this.updateLastSeen(payload.sub);

      // Broadcast presence online
      this.server.emit('presence.update', {
        user_id: payload.sub,
        is_online: true,
        last_seen: now,
      });

      // Send snapshot of all currently online users to the newly connected client
      const onlineUserIds = Array.from(this.userSockets.keys());
      socket.emit?.('presence.snapshot', {
        online_user_ids: onlineUserIds,
      });
    } catch (err) {
      this.logger.warn(`WebSocket auth error on socket ${socket.id}: ${err.message}`);
      socket.disconnect();
    }
  }

  handleDisconnect(socket: Socket) {
    this.foregroundSockets.delete(socket.id);
    const userId = socket.data?.userId;
    if (userId && this.userSockets.has(userId)) {
      const set = this.userSockets.get(userId);
      set.delete(socket.id);
      if (set.size === 0) {
        this.userSockets.delete(userId);
        const now = new Date().toISOString();
        this.updateLastSeen(userId);
        this.server.emit('presence.update', {
          user_id: userId,
          is_online: false,
          last_seen: now,
        });
      }
    }
    this.logger.log(`Client disconnected: socket=${socket.id}`);
  }

  private updateLastSeen(userId: string) {
    try {
      const res = this.db?.query?.('UPDATE users SET last_seen_at = NOW() WHERE id = $1', [userId]);
      if (res && typeof (res as Promise<any>).catch === 'function') {
        (res as Promise<any>).catch((err: any) =>
          this.logger.warn(`Failed to update last_seen_at for ${userId}: ${err.message}`),
        );
      }
    } catch (_) {}
  }

  /** Client explicitly requests full list of online users */
  @SubscribeMessage('presence.sync')
  handlePresenceSync(@ConnectedSocket() socket: Socket) {
    const onlineUserIds = Array.from(this.userSockets.keys());
    socket.emit('presence.snapshot', {
      online_user_ids: onlineUserIds,
    });
  }

  /** Check if a specific user currently has at least one active websocket connection */
  isUserOnline(userId: string): boolean {
    const sockets = this.userSockets.get(userId);
    return !!(sockets && sockets.size > 0);
  }

  /** The app moved on / off screen: `{ state: 'active' | 'background' }`. */
  @SubscribeMessage('app.state')
  handleAppState(@ConnectedSocket() socket: Socket, @MessageBody() data: { state?: string }) {
    if (!socket.data?.userId) return;
    this.setAppState(socket.id, data?.state);
  }

  /**
   * True while one of the user's apps is on screen. It then shows its own banners, so alerts
   * relayed to closed apps (Bark) are held back to avoid alerting twice.
   */
  isUserInForeground(userId: string): boolean {
    for (const socketId of this.userSockets.get(userId) ?? []) {
      if (this.foregroundSockets.has(socketId)) return true;
    }
    return false;
  }

  private setAppState(socketId: string, state: unknown) {
    if (state === 'active') {
      this.foregroundSockets.add(socketId);
    } else {
      this.foregroundSockets.delete(socketId);
    }
  }

  @SubscribeMessage('typing.update')
  handleTyping(
    @ConnectedSocket() socket: Socket,
    @MessageBody() data: { conversation_id: string; is_typing: boolean },
  ) {
    if (!socket.data?.userId || !data.conversation_id) return;

    socket.to(`conv:${data.conversation_id}`).emit('typing.update', {
      conversation_id: data.conversation_id,
      user_id: socket.data.userId,
      is_typing: data.is_typing,
    });
  }

  @SubscribeMessage('conversation.join')
  async handleJoinConversation(
    @ConnectedSocket() socket: Socket,
    @MessageBody() data: { conversation_id: string },
  ) {
    const userId = socket.data?.userId;
    if (!userId || !data?.conversation_id) return;

    // Only members may listen to a conversation's typing / call events
    const member = await this.db.query(
      'SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2',
      [data.conversation_id, userId],
    );
    if (member.rows.length === 0) {
      this.logger.warn(`Refused conversation.join: user=${userId} is not a member of ${data.conversation_id}`);
      return;
    }
    socket.join(`conv:${data.conversation_id}`);
  }

  /**
   * Delivers a new message to every other member's personal room (`user:<id>`, joined
   * automatically on connect), so delivery never depends on the app having joined the
   * conversation room. Fire-and-forget: failures are logged, never thrown to the sender.
   */
  async notifyNewMessage(conversationId: string, message: any) {
    try {
      const rooms = await this.memberRooms(conversationId, message.sender_user_id);
      if (rooms.length === 0) return;

      const senderRes = await this.db.query(
        'SELECT username, display_name, role, name_color FROM users WHERE id = $1',
        [message.sender_user_id],
      );
      const sender = senderRes.rows[0] || {};

      this.server.to(rooms).emit('message.new', {
        ...message,
        sender_username: sender.username,
        sender_display_name: sender.display_name,
        sender_role: sender.role,
        sender_name_color: sender.name_color ?? (sender.role === 'owner' || sender.username?.toLowerCase() === 'jame.kh' ? '#FF3B30' : null),
      });
    } catch (err) {
      this.logger.error(`message.new delivery failed for ${conversationId}: ${err.message}`);
    }
  }

  /** Receipts go to every member, including the original sender who wants to see "read". */
  async notifyReceipt(conversationId: string, receipt: any) {
    try {
      const rooms = await this.memberRooms(conversationId);
      if (rooms.length === 0) return;
      this.server.to(rooms).emit('message.receipt', receipt);
    } catch (err) {
      this.logger.error(`message.receipt delivery failed for ${conversationId}: ${err.message}`);
    }
  }

  /** Sends an event to every member's personal room (e.g. ring their phones for a call). */
  async emitToMembers(conversationId: string, event: string, payload: any, excludeUserId?: string) {
    try {
      const rooms = await this.memberRooms(conversationId, excludeUserId);
      if (rooms.length === 0) return;
      this.server.to(rooms).emit(event, payload);
    } catch (err) {
      this.logger.error(`${event} delivery failed for ${conversationId}: ${err.message}`);
    }
  }

  /** Sends an event to a specific user's personal room. */
  emitToUser(userId: string, event: string, payload: any) {
    try {
      this.server.to(`user:${userId}`).emit(event, payload);
    } catch (err) {
      this.logger.error(`${event} delivery failed for user ${userId}: ${err.message}`);
    }
  }

  /** Broadcasts an event to all connected sockets. */
  broadcastAll(event: string, payload: any) {
    try {
      this.server.emit(event, payload);
    } catch (err) {
      this.logger.error(`${event} broadcast failed: ${err.message}`);
    }
  }


  async notifyLocationUpdated(location: {
    user_id: string;
    share_id: string;
    latitude: number;
    longitude: number;
    heading: number | null;
    accuracy: number | null;
    updated_at: Date | string;
  }) {
    try {
      await this.db.transaction(async (client) => {
        const authorizedViewers = await client.query(
          `SELECT viewer.viewer_user_id AS friend_id,
                  l.user_id, l.share_id, l.latitude, l.longitude, l.heading, l.accuracy, l.updated_at,
                  u.username, u.display_name, u.avatar_url
           FROM live_location_viewers viewer
           JOIN live_locations l
             ON l.user_id = viewer.owner_user_id
            AND l.share_id = $2
           JOIN friendships f
             ON f.user_id = viewer.viewer_user_id
            AND f.friend_id = viewer.owner_user_id
            AND f.status = 'accepted'
           JOIN friendships reciprocal
             ON reciprocal.user_id = viewer.owner_user_id
            AND reciprocal.friend_id = viewer.viewer_user_id
            AND reciprocal.status = 'accepted'
           JOIN users u ON u.id = l.user_id AND u.status = 'active'
           WHERE viewer.owner_user_id = $1
           FOR SHARE OF l, viewer, f, reciprocal`,
          [location.user_id, location.share_id],
        );
        if (authorizedViewers.rows.length === 0) return;
        const rooms = authorizedViewers.rows.map((row) => `user:${row.friend_id}`);
        const latest = authorizedViewers.rows[0];
        this.server.to(rooms).emit('location.update', {
          user_id: latest.user_id,
          share_id: latest.share_id,
          latitude: latest.latitude,
          longitude: latest.longitude,
          heading: latest.heading,
          accuracy: latest.accuracy,
          updated_at: latest.updated_at,
          username: latest.username,
          display_name: latest.display_name,
          avatar_url: latest.avatar_url,
        });
      });
    } catch (err) {
      this.logger.error(`location.update delivery failed for user ${location.user_id}: ${err.message}`);
    }
  }

  async notifyLocationStopped(userId: string, viewerIds: string[], shareId: string) {
    try {
      const rooms = [...viewerIds.map((viewerId) => `user:${viewerId}`), `user:${userId}`];
      this.server.to(rooms).emit('location.stopped', {
        user_id: userId,
        share_id: shareId,
      });
    } catch (err) {
      this.logger.error(`location.stopped delivery failed for user ${userId}: ${err.message}`);
    }
  }

  notifyLocationAccessRevoked(
    userId: string,
    friendId: string,
    userShareId: string | null,
    friendShareId: string | null,
  ) {
    if (friendShareId) {
      this.server.to(`user:${userId}`).emit('location.stopped', {
        user_id: friendId,
        share_id: friendShareId,
      });
    }
    if (userShareId) {
      this.server.to(`user:${friendId}`).emit('location.stopped', {
        user_id: userId,
        share_id: userShareId,
      });
    }
  }

  private async acceptedFriendRooms(userId: string): Promise<string[]> {
    const result = await this.db.query(
      `SELECT viewer.viewer_user_id AS friend_id
       FROM live_location_viewers viewer
       JOIN friendships f
         ON f.user_id = viewer.owner_user_id
        AND f.friend_id = viewer.viewer_user_id
        AND f.status = 'accepted'
       JOIN friendships reciprocal
         ON reciprocal.user_id = viewer.viewer_user_id
        AND reciprocal.friend_id = viewer.owner_user_id
        AND reciprocal.status = 'accepted'
       JOIN users u ON u.id = viewer.viewer_user_id AND u.status = 'active'
       WHERE viewer.owner_user_id = $1`,
      [userId],
    );
    return result.rows.map((row) => `user:${row.friend_id}`);
  }

  private async memberRooms(conversationId: string, excludeUserId?: string): Promise<string[]> {
    const res = await this.db.query(
      'SELECT user_id FROM conversation_members WHERE conversation_id = $1',
      [conversationId],
    );
    return res.rows
      .map((row) => row.user_id)
      .filter((id) => id !== excludeUserId)
      .map((id) => `user:${id}`);
  }
}

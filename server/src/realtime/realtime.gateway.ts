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

      socket.data = {
        userId: payload.sub,
        deviceId: payload.device_id,
        role: payload.role,
        username: payload.username,
      };

      // Add socket to user map
      if (!this.userSockets.has(payload.sub)) {
        this.userSockets.set(payload.sub, new Set());
      }
      this.userSockets.get(payload.sub).add(socket.id);

      // Join room for this user
      socket.join(`user:${payload.sub}`);
      socket.join(`device:${payload.device_id}`);

      this.logger.log(
        `Client connected: user=${payload.username} (${payload.sub}), device=${payload.device_id}, socket=${socket.id}`,
      );

      // Broadcast presence online
      this.server.emit('presence.update', {
        user_id: payload.sub,
        is_online: true,
        last_seen: new Date().toISOString(),
      });
    } catch (err) {
      this.logger.warn(`WebSocket auth error on socket ${socket.id}: ${err.message}`);
      socket.disconnect();
    }
  }

  handleDisconnect(socket: Socket) {
    const userId = socket.data?.userId;
    if (userId && this.userSockets.has(userId)) {
      const set = this.userSockets.get(userId);
      set.delete(socket.id);
      if (set.size === 0) {
        this.userSockets.delete(userId);
        this.server.emit('presence.update', {
          user_id: userId,
          is_online: false,
          last_seen: new Date().toISOString(),
        });
      }
    }
    this.logger.log(`Client disconnected: socket=${socket.id}`);
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
  handleJoinConversation(
    @ConnectedSocket() socket: Socket,
    @MessageBody() data: { conversation_id: string },
  ) {
    if (!data.conversation_id) return;
    socket.join(`conv:${data.conversation_id}`);
  }

  notifyNewMessage(conversationId: string, message: any) {
    this.server.to(`conv:${conversationId}`).emit('message.new', message);
  }

  notifyReceipt(conversationId: string, receipt: any) {
    this.server.to(`conv:${conversationId}`).emit('message.receipt', receipt);
  }
}

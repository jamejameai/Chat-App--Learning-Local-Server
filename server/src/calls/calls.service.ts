import { Injectable, ForbiddenException, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DatabaseService } from '../database/database.service';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { BarkRelayService } from '../notifications/bark-relay.service';
import { AccessToken } from 'livekit-server-sdk';
import { v4 as uuidv4 } from 'uuid';

@Injectable()
export class CallsService {
  private readonly livekitApiKey: string;
  private readonly livekitApiSecret: string;

  constructor(
    private readonly db: DatabaseService,
    private readonly config: ConfigService,
    private readonly realtimeGateway: RealtimeGateway,
    private readonly barkRelay: BarkRelayService,
  ) {
    this.livekitApiKey = this.config.get<string>('LIVEKIT_API_KEY') || 'devkey';
    this.livekitApiSecret = this.config.get<string>('LIVEKIT_API_SECRET') || 'secret';
  }

  /** LiveKit address the phones connect to (ws://<server-ip>:7880 on the home network). */
  private get livekitUrl(): string {
    return this.config.get<string>('LIVEKIT_PUBLIC_URL') || '';
  }

  async initiateCall(
    conversationId: string,
    callerUserId: string,
    callerDeviceId: string | undefined,
    callType: 'audio' | 'video',
  ) {
    // 1. Verify caller membership in conversation
    const memRes = await this.db.query(
      `SELECT cm.role, u.username, u.display_name, c.title, c.type
       FROM conversation_members cm
       JOIN users u ON u.id = cm.user_id
       JOIN conversations c ON c.id = cm.conversation_id
       WHERE cm.conversation_id = $1 AND cm.user_id = $2`,
      [conversationId, callerUserId],
    );

    if (memRes.rows.length === 0) {
      throw new ForbiddenException('Not a member of this conversation');
    }

    const caller = memRes.rows[0];
    const callerName = caller.display_name || caller.username;
    const roomName = `room_${uuidv4().replace(/-/g, '')}`;

    // 2. Create call record
    const callRes = await this.db.query(
      `INSERT INTO calls (conversation_id, initiated_by_user_id, call_type, status, livekit_room_name, started_at)
       VALUES ($1, $2, $3, 'dialing', $4, NOW())
       RETURNING id, conversation_id, initiated_by_user_id, call_type, status, livekit_room_name, started_at`,
      [conversationId, callerUserId, callType, roomName],
    );
    const call = callRes.rows[0];

    // 3. Record the caller (their device comes from the login token)
    if (callerDeviceId) {
      await this.db.query(
        `INSERT INTO call_participants (call_id, user_id, device_id, status, joined_at)
         VALUES ($1, $2, $3, 'joined', NOW())
         ON CONFLICT (call_id, device_id) DO UPDATE SET status = 'joined', joined_at = NOW()`,
        [call.id, callerUserId, callerDeviceId],
      );
    }

    // 4. LiveKit token for the caller
    const callerToken = await this.generateToken(roomName, callerUserId, callerName);

    // 5. Ring the other members' phones (their personal rooms, so it works on any screen)
    void this.realtimeGateway.emitToMembers(
      conversationId,
      'call.incoming',
      {
        call_id: call.id,
        conversation_id: conversationId,
        caller_user_id: callerUserId,
        caller_name: callerName,
        conversation_title: caller.type === 'direct' ? callerName : caller.title,
        call_type: callType,
        livekit_room_name: roomName,
      },
      callerUserId,
    );
    // ...including phones where the app is closed or in the background
    void this.barkRelay.onIncomingCall({
      callId: call.id,
      conversationId,
      callerUserId,
      callerName,
      conversationTitle: caller.type === 'direct' ? callerName : caller.title,
      callType,
    });

    return {
      call_id: call.id,
      conversation_id: conversationId,
      room_name: roomName,
      call_type: callType,
      status: call.status,
      token: callerToken,
      livekit_url: this.livekitUrl,
    };
  }

  async joinCall(callId: string, userId: string, deviceId: string | undefined) {
    // 1. Fetch active call
    const callRes = await this.db.query(
      `SELECT c.id, c.conversation_id, c.call_type, c.status, c.livekit_room_name
       FROM calls c
       WHERE c.id = $1 AND c.status IN ('dialing', 'active')`,
      [callId],
    );

    if (callRes.rows.length === 0) {
      throw new NotFoundException('Active call not found');
    }

    const call = callRes.rows[0];

    // 2. Verify user membership in conversation
    const memRes = await this.db.query(
      `SELECT u.username, u.display_name
       FROM conversation_members cm
       JOIN users u ON u.id = cm.user_id
       WHERE cm.conversation_id = $1 AND cm.user_id = $2`,
      [call.conversation_id, userId],
    );

    if (memRes.rows.length === 0) {
      throw new ForbiddenException('Not a member of this conversation');
    }

    const user = memRes.rows[0];
    const userName = user.display_name || user.username;

    // 3. Update call status to active
    await this.db.query(
      `UPDATE calls SET status = 'active' WHERE id = $1 AND status = 'dialing'`,
      [callId],
    );

    // 4. Record this device as joined
    if (deviceId) {
      await this.db.query(
        `INSERT INTO call_participants (call_id, user_id, device_id, status, joined_at)
         VALUES ($1, $2, $3, 'joined', NOW())
         ON CONFLICT (call_id, device_id) DO UPDATE SET status = 'joined', joined_at = NOW()`,
        [callId, userId, deviceId],
      );
    }

    // 5. LiveKit token
    const token = await this.generateToken(call.livekit_room_name, userId, userName);

    // 6. Tell the chat members someone joined
    void this.realtimeGateway.emitToMembers(call.conversation_id, 'call.participant_joined', {
      call_id: callId,
      user_id: userId,
      user_name: userName,
    });

    return {
      call_id: callId,
      conversation_id: call.conversation_id,
      room_name: call.livekit_room_name,
      call_type: call.call_type,
      token,
      livekit_url: this.livekitUrl,
    };
  }

  async endCall(callId: string, userId: string) {
    const callRes = await this.db.query(
      `SELECT c.id, c.conversation_id, c.status, c.started_at, c.call_type,
              u.username AS caller_username, u.display_name AS caller_display_name,
              conv.title AS conversation_title, conv.type AS conversation_type
       FROM calls c
       LEFT JOIN users u ON u.id = c.initiated_by_user_id
       LEFT JOIN conversations conv ON conv.id = c.conversation_id
       WHERE c.id = $1`,
      [callId],
    );

    if (callRes.rows.length === 0) {
      throw new NotFoundException('Call not found');
    }

    const call = callRes.rows[0];

    // Compute duration
    const updateRes = await this.db.query(
      `UPDATE calls
       SET status = 'ended',
           ended_at = NOW(),
           duration_seconds = GREATEST(0, EXTRACT(EPOCH FROM (NOW() - started_at))::INT)
       WHERE id = $1
       RETURNING duration_seconds`,
      [callId],
    );
    const duration = updateRes.rows[0]?.duration_seconds || 0;

    // Mark participant left
    await this.db.query(
      `UPDATE call_participants SET status = 'left', left_at = NOW() WHERE call_id = $1 AND user_id = $2`,
      [callId, userId],
    );

    // Everyone's phone stops ringing / hangs up (hang-up and decline both end the call)
    void this.realtimeGateway.emitToMembers(call.conversation_id, 'call.ended', {
      call_id: callId,
      conversation_id: call.conversation_id,
      duration_seconds: duration,
      ended_by_user_id: userId,
    });

    const wasAnswered = call.status === 'active';
    const callerName = call.caller_display_name || call.caller_username || '';

    // If call ended without being answered, emit missed call alert
    if (!wasAnswered) {
      void this.realtimeGateway.emitToMembers(call.conversation_id, 'call.missed', {
        call_id: callId,
        conversation_id: call.conversation_id,
        caller_user_id: call.initiated_by_user_id,
        caller_name: callerName,
        call_type: call.call_type,
        started_at: call.started_at,
      });
    }

    // Phones rung through Bark: "Missed call", or the alert removed if someone answered
    void this.barkRelay.onCallEnded({
      callId,
      conversationId: call.conversation_id,
      wasAnswered,
      endedByUserId: userId,
      callerName,
      conversationTitle: call.conversation_type === 'direct' ? callerName : call.conversation_title,
      callType: call.call_type,
    });


    return { success: true, duration_seconds: duration };
  }

  async getCallHistory(userId: string, limit = 50) {
    const res = await this.db.query(
      `SELECT c.id, c.conversation_id, c.call_type, c.status, c.started_at, c.ended_at, c.duration_seconds,
              u.username AS initiated_by_username, u.display_name AS initiated_by_display_name,
              conv.title AS conversation_title, conv.type AS conversation_type,
              (c.initiated_by_user_id = $1) AS is_outgoing
       FROM calls c
       JOIN conversation_members cm ON cm.conversation_id = c.conversation_id
       JOIN users u ON u.id = c.initiated_by_user_id
       JOIN conversations conv ON conv.id = c.conversation_id
       WHERE cm.user_id = $1
       ORDER BY c.started_at DESC
       LIMIT $2`,
      [userId, limit],
    );

    return res.rows;
  }

  private async generateToken(roomName: string, userId: string, userName: string): Promise<string> {
    const at = new AccessToken(this.livekitApiKey, this.livekitApiSecret, {
      identity: userId,
      name: userName,
      ttl: '1h',
    });

    at.addGrant({
      roomJoin: true,
      room: roomName,
      canPublish: true,
      canSubscribe: true,
      canPublishData: true,
    });

    return await at.toJwt();
  }
}

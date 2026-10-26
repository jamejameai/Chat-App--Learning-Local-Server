import { ForbiddenException } from '@nestjs/common';
import { CallsService } from './calls.service';

describe('CallsService', () => {
  const query = jest.fn();
  const emitToMembers = jest.fn();
  const bark = { onIncomingCall: jest.fn(), onCallEnded: jest.fn() };
  const config = { get: (key: string) => ({ LIVEKIT_API_KEY: 'k', LIVEKIT_API_SECRET: 'a-long-test-secret-value-1234567890', LIVEKIT_PUBLIC_URL: 'ws://172.16.41.93:7880' } as any)[key] };
  let service: CallsService;

  beforeEach(() => {
    query.mockReset();
    emitToMembers.mockReset();
    bark.onIncomingCall.mockReset();
    bark.onCallEnded.mockReset();
    service = new CallsService({ query } as any, config as any, { emitToMembers } as any, bark as any);
  });

  describe('initiateCall', () => {
    it("rings the other members' phones (not just whoever has the chat open) and returns where to connect", async () => {
      query
        .mockResolvedValueOnce({ rows: [{ username: 'alice', display_name: 'Alice', title: 'Bob', type: 'direct' }] }) // membership
        .mockResolvedValueOnce({ rows: [{ id: 'call-1', status: 'dialing' }] }) // insert call
        .mockResolvedValueOnce({ rows: [] }); // participant

      const res = await service.initiateCall('conv-1', 'alice', 'dev-a', 'video');

      expect(query.mock.calls[0][1]).toEqual(['conv-1', 'alice']);
      expect(query.mock.calls[2][1]).toEqual(['call-1', 'alice', 'dev-a']); // caller's own device from the login token
      expect(emitToMembers).toHaveBeenCalledWith(
        'conv-1',
        'call.incoming',
        expect.objectContaining({ call_id: 'call-1', caller_user_id: 'alice', caller_name: 'Alice', call_type: 'video' }),
        'alice',
      );
      expect(res).toEqual(expect.objectContaining({
        call_id: 'call-1',
        call_type: 'video',
        livekit_url: 'ws://172.16.41.93:7880',
      }));
      expect(typeof res.token).toBe('string');
      // Phones with the app closed are rung through Bark
      expect(bark.onIncomingCall).toHaveBeenCalledWith(expect.objectContaining({ callId: 'call-1', callerName: 'Alice', callType: 'video' }));
    });

    it('refuses people outside the chat', async () => {
      query.mockResolvedValueOnce({ rows: [] });
      await expect(service.initiateCall('conv-1', 'mallory', 'dev-m', 'audio')).rejects.toBeInstanceOf(ForbiddenException);
      expect(emitToMembers).not.toHaveBeenCalled();
    });
  });

  describe('joinCall', () => {
    it('lets a member join with their device and returns where to connect', async () => {
      query
        .mockResolvedValueOnce({ rows: [{ id: 'call-1', conversation_id: 'conv-1', call_type: 'audio', status: 'dialing', livekit_room_name: 'room_x' }] })
        .mockResolvedValueOnce({ rows: [{ username: 'bob', display_name: 'Bob' }] })
        .mockResolvedValueOnce({ rows: [] }) // status -> active
        .mockResolvedValueOnce({ rows: [] }); // participant

      const res = await service.joinCall('call-1', 'bob', 'dev-b');

      expect(query.mock.calls[3][1]).toEqual(['call-1', 'bob', 'dev-b']);
      expect(emitToMembers).toHaveBeenCalledWith('conv-1', 'call.participant_joined', expect.objectContaining({ call_id: 'call-1', user_id: 'bob' }));
      expect(res).toEqual(expect.objectContaining({ room_name: 'room_x', livekit_url: 'ws://172.16.41.93:7880' }));
    });
  });

  describe('endCall', () => {
    it('tells everyone in the chat, so the other phone stops ringing / hangs up', async () => {
      query
        .mockResolvedValueOnce({ rows: [{ id: 'call-1', conversation_id: 'conv-1', status: 'dialing' }] })
        .mockResolvedValueOnce({ rows: [{ duration_seconds: 0 }] })
        .mockResolvedValueOnce({ rows: [] });

      await service.endCall('call-1', 'bob');

      expect(emitToMembers).toHaveBeenCalledWith('conv-1', 'call.ended', expect.objectContaining({ call_id: 'call-1', ended_by_user_id: 'bob' }));
      // Never answered: Bark turns the ringing alert into "Missed call"
      expect(bark.onCallEnded).toHaveBeenCalledWith(expect.objectContaining({ callId: 'call-1', wasAnswered: false, endedByUserId: 'bob' }));
    });
  });
});

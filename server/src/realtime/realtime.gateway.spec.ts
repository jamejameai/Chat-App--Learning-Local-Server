import { RealtimeGateway } from './realtime.gateway';

describe('RealtimeGateway', () => {
  const query = jest.fn();
  const transactionQuery = jest.fn();
  const transaction = jest.fn((callback: (client: any) => any) => callback({ query: transactionQuery }));
  const emit = jest.fn();
  const to = jest.fn(() => ({ emit }));
  let gateway: RealtimeGateway;

  beforeEach(() => {
    query.mockReset();
    transactionQuery.mockReset();
    transaction.mockClear();
    emit.mockReset();
    to.mockClear();
    gateway = new RealtimeGateway({} as any, { query, transaction } as any);
    gateway.server = { to } as any;
  });

  describe('notifyNewMessage', () => {
    it("delivers to every other member's personal room, with the sender's name", async () => {
      query
        .mockResolvedValueOnce({ rows: [{ user_id: 'alice' }, { user_id: 'bob' }, { user_id: 'carol' }] })
        .mockResolvedValueOnce({ rows: [{ username: 'alice', display_name: 'Alice A', role: 'member', name_color: '#FF3B30' }] });

      await gateway.notifyNewMessage('conv-1', { id: 'm1', sender_user_id: 'alice' });

      expect(to).toHaveBeenCalledWith(['user:bob', 'user:carol']);
      expect(emit).toHaveBeenCalledWith('message.new', {
        id: 'm1',
        sender_user_id: 'alice',
        sender_username: 'alice',
        sender_display_name: 'Alice A',
        sender_role: 'member',
        sender_name_color: '#FF3B30',
      });
    });

    it('does not depend on anyone having joined the conversation room', async () => {
      query
        .mockResolvedValueOnce({ rows: [{ user_id: 'alice' }, { user_id: 'bob' }] })
        .mockResolvedValueOnce({ rows: [{ username: 'alice', display_name: 'Alice' }] });

      await gateway.notifyNewMessage('conv-1', { id: 'm1', sender_user_id: 'alice' });

      expect(to).not.toHaveBeenCalledWith('conv:conv-1');
    });

    it('never throws into the caller if the lookup fails', async () => {
      query.mockRejectedValueOnce(new Error('db down'));
      await expect(gateway.notifyNewMessage('conv-1', { id: 'm1', sender_user_id: 'a' })).resolves.toBeUndefined();
      expect(emit).not.toHaveBeenCalled();
    });
  });

  describe('notifyReceipt', () => {
    it("tells every member (including the message's sender)", async () => {
      query.mockResolvedValueOnce({ rows: [{ user_id: 'alice' }, { user_id: 'bob' }] });
      await gateway.notifyReceipt('conv-1', { message_id: 'm1', user_id: 'bob', status: 'read' });
      expect(to).toHaveBeenCalledWith(['user:alice', 'user:bob']);
      expect(emit).toHaveBeenCalledWith('message.receipt', { message_id: 'm1', user_id: 'bob', status: 'read' });
    });
  });

  describe('emitToMembers', () => {
    it("sends an event to every member's personal room, optionally skipping one person", async () => {
      query.mockResolvedValueOnce({ rows: [{ user_id: 'alice' }, { user_id: 'bob' }] });
      await gateway.emitToMembers('conv-1', 'call.incoming', { call_id: 'c1' }, 'alice');
      expect(to).toHaveBeenCalledWith(['user:bob']);
      expect(emit).toHaveBeenCalledWith('call.incoming', { call_id: 'c1' });
    });
  });

  describe('conversation.join', () => {
    const socket = (userId?: string) => ({ data: { userId }, join: jest.fn() });

    it('lets a member join the conversation room', async () => {
      query.mockResolvedValueOnce({ rows: [{ '?column?': 1 }] });
      const s = socket('bob');
      await gateway.handleJoinConversation(s as any, { conversation_id: 'conv-1' });
      expect(s.join).toHaveBeenCalledWith('conv:conv-1');
    });

    it('refuses a non-member (no eavesdropping on typing or calls)', async () => {
      query.mockResolvedValueOnce({ rows: [] });
      const s = socket('mallory');
      await gateway.handleJoinConversation(s as any, { conversation_id: 'conv-1' });
      expect(s.join).not.toHaveBeenCalled();
    });

    it('ignores unauthenticated sockets', async () => {
      const s = socket(undefined);
      await gateway.handleJoinConversation(s as any, { conversation_id: 'conv-1' });
      expect(query).not.toHaveBeenCalled();
      expect(s.join).not.toHaveBeenCalled();
    });
  });

  describe('location notifications', () => {
    it('sends a location only to selected friends with an active mutual friendship', async () => {
      transactionQuery.mockResolvedValueOnce({
        rows: [
          {
            friend_id: 'bob',
            user_id: 'alice',
            share_id: 'share-1',
            latitude: 37.79,
            longitude: -122.42,
            heading: 180,
            accuracy: 5,
            updated_at: '2026-10-22T00:01:00.000Z',
            username: 'alice',
            display_name: 'Alice',
            avatar_url: 'avatar.png',
          },
          {
            friend_id: 'carol',
            user_id: 'alice',
            share_id: 'share-1',
            latitude: 37.79,
            longitude: -122.42,
            heading: 180,
            accuracy: 5,
            updated_at: '2026-10-22T00:01:00.000Z',
            username: 'alice',
            display_name: 'Alice',
            avatar_url: 'avatar.png',
          },
        ],
      });
      const location = {
        user_id: 'alice',
        share_id: 'share-1',
        latitude: 37.78,
        longitude: -122.41,
        heading: null,
        accuracy: null,
        updated_at: '2026-10-22T00:00:00.000Z',
      };

      await gateway.notifyLocationUpdated(location);

      expect(transactionQuery).toHaveBeenCalledWith(
        expect.stringContaining('live_location_viewers'),
        ['alice', 'share-1'],
      );
      expect(transactionQuery.mock.calls[0][0]).toContain('FOR SHARE OF l, viewer, f, reciprocal');
      expect(to).toHaveBeenCalledWith(['user:bob', 'user:carol']);
      expect(emit).toHaveBeenCalledWith('location.update', {
        ...location,
        latitude: 37.79,
        longitude: -122.42,
        heading: 180,
        accuracy: 5,
        updated_at: '2026-10-22T00:01:00.000Z',
        username: 'alice',
        display_name: 'Alice',
        avatar_url: 'avatar.png',
      });
    });

    it('does not broadcast location updates when no authorized friends are found', async () => {
      transactionQuery.mockResolvedValueOnce({ rows: [] });

      await gateway.notifyLocationUpdated({
        user_id: 'alice',
        share_id: 'share-1',
        latitude: 37.78,
        longitude: -122.41,
        heading: null,
        accuracy: null,
        updated_at: '2026-10-22T00:00:00.000Z',
      });

      expect(to).not.toHaveBeenCalled();
      expect(emit).not.toHaveBeenCalled();
    });

    it('notifies only the selected audience when sharing stops', async () => {
      await gateway.notifyLocationStopped('alice', ['bob'], 'share-1');

      expect(to).toHaveBeenCalledWith(['user:bob', 'user:alice']);
      expect(emit).toHaveBeenCalledWith('location.stopped', {
        user_id: 'alice',
        share_id: 'share-1',
      });
    });

    it('removes each former friend’s marker from only the affected users', () => {
      gateway.notifyLocationAccessRevoked('alice', 'bob', 'alice-share', 'bob-share');

      expect(to).toHaveBeenNthCalledWith(1, 'user:alice');
      expect(emit).toHaveBeenNthCalledWith(1, 'location.stopped', {
        user_id: 'bob',
        share_id: 'bob-share',
      });
      expect(to).toHaveBeenNthCalledWith(2, 'user:bob');
      expect(emit).toHaveBeenNthCalledWith(2, 'location.stopped', {
        user_id: 'alice',
        share_id: 'alice-share',
      });
    });
  });

  describe('isUserInForeground', () => {
    const connect = async (id: string, appState?: string) => {
      const socket: any = {
        id,
        handshake: { auth: { token: 't' }, query: appState ? { app_state: appState } : {} },
        join: jest.fn(),
        disconnect: jest.fn(),
      };
      await gateway.handleConnection(socket);
      return socket;
    };

    beforeEach(() => {
      gateway = new RealtimeGateway({ verify: () => ({ sub: 'bob', deviceId: 'd-1', username: 'bob' }) } as any, { query } as any);
      gateway.server = { to, emit } as any;
    });

    it('follows the app moving on and off screen', async () => {
      const socket = await connect('s-1', 'active');
      expect(gateway.isUserInForeground('bob')).toBe(true);

      gateway.handleAppState(socket, { state: 'background' });
      expect(gateway.isUserInForeground('bob')).toBe(false);

      gateway.handleAppState(socket, { state: 'active' });
      gateway.handleDisconnect(socket);
      expect(gateway.isUserInForeground('bob')).toBe(false);
    });

    it('treats an app that does not say as background, so alerts are never held back by mistake', async () => {
      await connect('s-2');
      expect(gateway.isUserInForeground('bob')).toBe(false);
    });
  });
});

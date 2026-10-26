import { NotFoundException } from '@nestjs/common';
import { FriendsService } from './friends.service';

describe('FriendsService', () => {
  const query = jest.fn();
  const transaction = jest.fn();
  const clientQuery = jest.fn();
  const notifyLocationAccessRevoked = jest.fn();
  let service: FriendsService;

  const user = {
    id: 'bob',
    username: 'bob',
    display_name: 'Bob',
    phone_number: '+855 12 345 678',
    avatar_url: null,
    bio: 'hi',
    developer_profile: {
      headline: 'iOS Developer',
      skills: ['Swift', 'SwiftUI'],
      projects: [],
      website_url: 'https://example.com',
    },
    status: 'active',
    created_at: '2026-10-01T00:00:00.000Z',
  };

  beforeEach(() => {
    query.mockReset();
    clientQuery.mockReset();
    transaction.mockReset().mockImplementation((callback) => callback({ query: clientQuery }));
    notifyLocationAccessRevoked.mockReset();
    service = new FriendsService(
      { query, transaction } as any,
      { notifyLocationAccessRevoked } as any,
    );
  });

  it('returns a friend profile with phone number, friendship date and chat id', async () => {
    query
      .mockResolvedValueOnce({ rows: [user] })
      .mockResolvedValueOnce({ rows: [{ created_at: '2026-10-10T00:00:00.000Z' }] })
      .mockResolvedValueOnce({ rows: [{ id: 'conv-1' }] });

    const profile = await service.getProfile('alice', 'bob');

    expect(profile).toMatchObject({
      id: 'bob',
      display_name: 'Bob',
      phone_number: '+855 12 345 678',
      is_friend: true,
      friends_since: '2026-10-10T00:00:00.000Z',
      conversation_id: 'conv-1',
      developer_profile: user.developer_profile,
    });
    expect(query.mock.calls[0][0]).toContain('developer_profile');
  });

  it('hides the phone number from people who are not friends', async () => {
    query
      .mockResolvedValueOnce({ rows: [user] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [] });

    const profile = await service.getProfile('stranger', 'bob');

    expect(profile.is_friend).toBe(false);
    expect(profile.phone_number).toBeNull();
    expect(profile.conversation_id).toBeNull();
    expect(profile.developer_profile).toEqual(user.developer_profile);
  });

  it('404s for unknown or inactive users', async () => {
    query.mockResolvedValueOnce({ rows: [] });
    await expect(service.getProfile('alice', 'ghost')).rejects.toBeInstanceOf(NotFoundException);
  });

  describe('removeFriend', () => {
    it('revokes live-location access for both users after removing the friendship', async () => {
      clientQuery
        .mockResolvedValueOnce({ rows: [{ user_id: 'alice' }, { user_id: 'bob' }] })
        .mockResolvedValueOnce({
          rows: [
            { user_id: 'alice', share_id: 'alice-share' },
            { user_id: 'bob', share_id: 'bob-share' },
          ],
        })
        .mockResolvedValueOnce({ rows: [] });

      await service.removeFriend('alice', 'bob');

      expect(clientQuery).toHaveBeenNthCalledWith(
        3,
        expect.stringContaining('DELETE FROM live_location_viewers'),
        ['alice', 'bob'],
      );
      expect(notifyLocationAccessRevoked).toHaveBeenCalledWith(
        'alice',
        'bob',
        'alice-share',
        'bob-share',
      );
    });

    it('does not send a revocation event when no friendship was removed', async () => {
      clientQuery.mockResolvedValueOnce({ rows: [] });

      await service.removeFriend('alice', 'unknown');

      expect(notifyLocationAccessRevoked).not.toHaveBeenCalled();
    });
  });
});

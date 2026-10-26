import { createHash } from 'crypto';
import { LocationsService } from './locations.service';

describe('LocationsService', () => {
  const query = jest.fn();
  const transaction = jest.fn();
  const clientQuery = jest.fn();
  const notifyLocationUpdated = jest.fn();
  const notifyLocationStopped = jest.fn();
  let service: LocationsService;

  beforeEach(() => {
    query.mockReset();
    clientQuery.mockReset();
    transaction.mockReset().mockImplementation((callback) => callback({ query: clientQuery }));
    notifyLocationUpdated.mockReset();
    notifyLocationStopped.mockReset();
    service = new LocationsService(
      { query, transaction } as any,
      { notifyLocationUpdated, notifyLocationStopped } as any,
    );
  });

  it('starts sharing with an explicit accepted-friend audience snapshot', async () => {
    const location = {
      user_id: 'alice',
      share_id: 'alice-share',
      latitude: 37.78,
      longitude: -122.41,
      heading: 90,
      accuracy: 8,
      updated_at: '2026-10-22T00:00:00.000Z',
    };
    clientQuery
      .mockResolvedValueOnce({ rows: [{ friend_id: 'bob' }] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [location] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [] });

    await expect(
      service.beginSharing('alice', {
        latitude: 37.78,
        longitude: -122.41,
        heading: 90,
        accuracy: 8,
        viewer_ids: ['bob'],
        stop_token: 'a'.repeat(64),
      }),
    ).resolves.toEqual(location);

    expect(clientQuery).toHaveBeenNthCalledWith(
      1,
      expect.stringContaining("reciprocal.status = 'accepted'"),
      ['alice', ['bob']],
    );
    expect(clientQuery).toHaveBeenNthCalledWith(
      3,
      expect.stringContaining('stop_token_hash'),
      [
        'alice',
        37.78,
        -122.41,
        90,
        8,
        createHash('sha256').update('a'.repeat(64)).digest('hex'),
      ],
    );
    expect(clientQuery).toHaveBeenNthCalledWith(
      5,
      expect.stringContaining('INSERT INTO live_location_viewers'),
      ['alice', ['bob']],
    );
    expect(notifyLocationUpdated).toHaveBeenCalledWith(location);
  });

  it('rejects a selected viewer who is not an accepted mutual friend', async () => {
    clientQuery.mockResolvedValueOnce({ rows: [] });

    await expect(
      service.beginSharing('alice', {
        latitude: 37.78,
        longitude: -122.41,
        viewer_ids: ['mallory'],
        stop_token: 'a'.repeat(64),
      }),
    ).rejects.toThrow('Every selected viewer must be an accepted friend');

    expect(clientQuery).toHaveBeenCalledTimes(1);
    expect(notifyLocationUpdated).not.toHaveBeenCalled();
  });

  it('rejects an empty audience before opening a transaction', async () => {
    await expect(
      service.beginSharing('alice', {
        latitude: 37.78,
        longitude: -122.41,
        viewer_ids: [],
        stop_token: 'a'.repeat(64),
      }),
    ).rejects.toThrow('Choose at least one unique friend to share with');

    expect(transaction).not.toHaveBeenCalled();
  });

  it('revokes sharing with the stop-only token and notifies its audience', async () => {
    clientQuery
      .mockResolvedValueOnce({ rows: [{ user_id: 'alice', share_id: 'alice-share' }] })
      .mockResolvedValueOnce({ rows: [{ viewer_user_id: 'bob' }] })
      .mockResolvedValueOnce({ rows: [] });

    await expect(service.stopSharingWithToken('a'.repeat(64))).resolves.toEqual({
      sharing: false,
    });
    expect(clientQuery).toHaveBeenNthCalledWith(
      1,
      expect.stringContaining('stop_token_hash'),
      [createHash('sha256').update('a'.repeat(64)).digest('hex')],
    );
    expect(notifyLocationStopped).toHaveBeenCalledWith('alice', ['bob'], 'alice-share');
  });

  it('rejects malformed stop-only tokens before database access', async () => {
    await expect(service.stopSharingWithToken('invalid')).rejects.toThrow();
    expect(transaction).not.toHaveBeenCalled();
  });

  it('lists only current locations belonging to accepted friends', async () => {
    const locations = [{ user_id: 'bob', latitude: 1, longitude: 2 }];
    query.mockResolvedValueOnce({ rows: locations });

    await expect(service.getFriendLocations('alice')).resolves.toEqual(locations);
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining('live_location_viewers'),
      ['alice'],
    );
  });

  it('restores the current user’s active share after reconnecting', async () => {
    const location = {
      user_id: 'alice',
      latitude: 37.78,
      longitude: -122.41,
      heading: null,
      accuracy: null,
      updated_at: '2026-10-22T00:00:00.000Z',
      viewer_ids: ['bob'],
    };
    query.mockResolvedValueOnce({ rows: [location] });

    await expect(service.getShareState('alice')).resolves.toEqual({
      sharing: true,
      location,
    });
  });

  it('reports sharing as off when no current location exists', async () => {
    query.mockResolvedValueOnce({ rows: [] });

    await expect(service.getShareState('alice')).resolves.toEqual({
      sharing: false,
      location: null,
    });
  });

  it('stops sharing by deleting the active location and notifying friends', async () => {
    clientQuery
      .mockResolvedValueOnce({ rows: [{ user_id: 'alice', share_id: 'alice-share' }] })
      .mockResolvedValueOnce({ rows: [{ viewer_user_id: 'bob' }] })
      .mockResolvedValueOnce({ rows: [] });

    await expect(service.stopSharing('alice')).resolves.toEqual({ sharing: false });
    expect(clientQuery).toHaveBeenNthCalledWith(
      3,
      'DELETE FROM live_locations WHERE user_id = $1',
      ['alice'],
    );
    expect(notifyLocationStopped).toHaveBeenCalledWith('alice', ['bob'], 'alice-share');
  });

  it('does not allow coordinate updates to create a new share', async () => {
    query.mockResolvedValueOnce({ rows: [] });

    await expect(service.updateSharing('alice', {
      latitude: 37.78,
      longitude: -122.41,
    })).rejects.toThrow('Start sharing before sending a location update');
    expect(notifyLocationUpdated).not.toHaveBeenCalled();
  });

  it.each([
    { latitude: 91, longitude: 0 },
    { latitude: 0, longitude: -181 },
    { latitude: Number.NaN, longitude: 0 },
  ])('rejects invalid coordinates before writing: %o', async (coordinates) => {
    await expect(
      service.updateSharing('alice', coordinates),
    ).rejects.toThrow();
    expect(query).not.toHaveBeenCalled();
  });
});

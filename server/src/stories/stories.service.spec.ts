import { BadRequestException, NotFoundException } from '@nestjs/common';
import { StoriesService } from './stories.service';

describe('StoriesService', () => {
  const query = jest.fn();
  const emit = jest.fn();
  const to = jest.fn(() => ({ emit }));
  let service: StoriesService;

  const dto = {
    attachment_id: 'att-1',
    media_key: 'key',
    media_iv: 'iv',
    media_sha256: 'sha',
    mime_type: 'image/jpeg',
    caption: 'hello',
  };

  beforeEach(() => {
    query.mockReset();
    emit.mockReset();
    to.mockClear();
    service = new StoriesService({ query } as any, { server: { to } } as any);
  });

  describe('createStory', () => {
    it('refuses a photo that this user did not upload', async () => {
      query.mockResolvedValueOnce({ rows: [] });
      await expect(service.createStory('alice', dto)).rejects.toBeInstanceOf(BadRequestException);
    });

    it("posts the story and lights up the ring on friends' phones", async () => {
      query
        .mockResolvedValueOnce({ rows: [{ id: 'att-1' }] }) // attachment is mine
        .mockResolvedValueOnce({ rows: [{ id: 'st-1', created_at: 'now', expires_at: 'later' }] }) // insert
        .mockResolvedValueOnce({ rows: [{ friend_id: 'bob' }, { friend_id: 'carol' }] }); // friends

      const res = await service.createStory('alice', dto);

      expect(res.id).toBe('st-1');
      expect(to).toHaveBeenCalledWith(['user:bob', 'user:carol']);
      expect(emit).toHaveBeenCalledWith('story.new', { user_id: 'alice', story_id: 'st-1' });
    });
  });

  describe('getFeed', () => {
    const row = (id: string, user: string, viewed: boolean, created: string) => ({
      id, user_id: user, username: user, display_name: user.toUpperCase(), avatar_url: null,
      attachment_id: `a-${id}`, media_key: 'k', media_iv: 'i', media_sha256: 's', mime_type: 'image/jpeg',
      caption: null, created_at: created, expires_at: 'x', viewed, view_count: '2',
    });

    it('groups stories by person: mine first, then people with unseen stories, newest first', async () => {
      query.mockResolvedValueOnce({
        rows: [
          row('1', 'bob', true, '2026-10-20T01:00:00Z'),
          row('2', 'carol', false, '2026-10-20T02:00:00Z'),
          row('3', 'alice', false, '2026-10-20T03:00:00Z'),
          row('4', 'bob', true, '2026-10-20T04:00:00Z'),
        ],
      });

      const feed = await service.getFeed('alice');

      expect(feed.map((e) => e.user_id)).toEqual(['alice', 'carol', 'bob']);
      expect(feed[0]).toEqual(expect.objectContaining({ is_me: true }));
      expect(feed[1]).toEqual(expect.objectContaining({ has_unseen: true }));
      expect(feed[2]).toEqual(expect.objectContaining({ has_unseen: false }));
      expect(feed[2].stories.map((s) => s.id)).toEqual(['1', '4']); // oldest → newest, like Telegram
      expect(feed[0].stories[0].view_count).toBe(2); // only for my own stories
      expect(feed[1].stories[0].view_count).toBeNull();
    });
  });

  describe('markViewed', () => {
    it("records a friend's view", async () => {
      query
        .mockResolvedValueOnce({ rows: [{ user_id: 'bob' }] })
        .mockResolvedValueOnce({ rows: [] });
      await service.markViewed('st-1', 'alice');
      expect(query.mock.calls[1][0]).toContain('INSERT INTO story_views');
    });

    it("hides other people's stories from non-friends", async () => {
      query.mockResolvedValueOnce({ rows: [] });
      await expect(service.markViewed('st-1', 'mallory')).rejects.toBeInstanceOf(NotFoundException);
    });

    it('does not count the owner looking at their own story', async () => {
      query.mockResolvedValueOnce({ rows: [{ user_id: 'alice' }] });
      await service.markViewed('st-1', 'alice');
      expect(query).toHaveBeenCalledTimes(1);
    });
  });

  describe('deleteStory', () => {
    it('only the owner can delete', async () => {
      query.mockResolvedValueOnce({ rows: [] });
      await expect(service.deleteStory('st-1', 'mallory')).rejects.toBeInstanceOf(NotFoundException);
    });
  });
});

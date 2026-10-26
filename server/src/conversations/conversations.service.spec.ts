import { ForbiddenException } from '@nestjs/common';
import { ConversationsService } from './conversations.service';

describe('ConversationsService.listConversations', () => {
  it('includes each chat\'s latest (still encrypted) message so the app can show a preview', async () => {
    const query = jest.fn().mockResolvedValueOnce({
      rows: [{
        id: 'c-1', type: 'group', title: 'Team',
        last_message_sender_id: 'bob', last_message_envelope_type: 'e2ee_text',
        last_message_payload: 'cipher', last_message_iv: 'iv',
      }],
    });
    const service = new ConversationsService({ query } as any, {} as any);

    const list = await service.listConversations('alice');

    expect(query.mock.calls[0][0]).toContain('ORDER BY m.sequence_id DESC');
    // Unread = messages from OTHER people after my read position (my own never count)
    expect(query.mock.calls[0][0]).toMatch(/sender_user_id != \$1[\s\S]*AS unread_count|unread_count[\s\S]*sender_user_id != \$1/);
    expect(list[0]).toEqual(expect.objectContaining({
      last_message_sender_id: 'bob',
      last_message_payload: 'cipher',
      last_message_iv: 'iv',
      last_message_envelope_type: 'e2ee_text',
    }));
  });
});

describe('ConversationsService.syncConversation', () => {
  const query = jest.fn();
  let service: ConversationsService;

  beforeEach(() => {
    query.mockReset();
    service = new ConversationsService({ query } as any, {} as any);
  });

  it("returns how far the OTHER members have read, so the app can show 'Seen'", async () => {
    query
      .mockResolvedValueOnce({ rows: [{ id: 'mem-a', last_read_sequence_id: '9' }] }) // membership (me)
      .mockResolvedValueOnce({ rows: [{ id: 'm-5', sequence_id: '5' }] }) // messages
      .mockResolvedValueOnce({ rows: [{ last_sequence_id: '5' }] }) // conversation
      .mockResolvedValueOnce({ rows: [{ read_up_to: '4' }] }); // others' read position

    const res = await service.syncConversation('c-1', 'alice', 0, 50);

    expect(res.read_up_to_sequence_id).toBe('4');
    const othersQuery = query.mock.calls[3];
    expect(othersQuery[0]).toContain('user_id != $2');
    expect(othersQuery[1]).toEqual(['c-1', 'alice']);
  });

  it('reports 0 when nobody else has read anything yet', async () => {
    query
      .mockResolvedValueOnce({ rows: [{ id: 'mem-a', last_read_sequence_id: '0' }] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [{ last_sequence_id: '0' }] })
      .mockResolvedValueOnce({ rows: [{ read_up_to: null }] });

    const res = await service.syncConversation('c-1', 'alice', 0, 50);

    expect(res.read_up_to_sequence_id).toBe(0);
  });

  it('still refuses non-members', async () => {
    query.mockResolvedValueOnce({ rows: [] });
    await expect(service.syncConversation('c-1', 'mallory', 0, 50)).rejects.toBeInstanceOf(ForbiddenException);
  });
});

describe('ConversationsService.createConversation (groups)', () => {
  it('adds every chosen member and pops the new group up on their phones right away', async () => {
    const clientQuery = jest.fn().mockResolvedValueOnce({ rows: [{ id: 'g-1', type: 'group', title: 'Trip' }] })
      .mockResolvedValue({ rows: [] });
    const db = { query: jest.fn(), transaction: (cb: any) => cb({ query: clientQuery }) };
    const emitToMembers = jest.fn().mockResolvedValue(undefined);
    const service = new ConversationsService(db as any, { emitToMembers } as any);

    const conv = await service.createConversation('alice', {
      type: 'group', title: 'Trip', participant_user_ids: ['bob', 'carol', 'alice'],
    });

    expect(conv.id).toBe('g-1');
    const memberInserts = clientQuery.mock.calls.filter(([sql]) => sql.includes("'member'"));
    expect(memberInserts.map(([, params]) => params[1])).toEqual(['bob', 'carol']);
    expect(emitToMembers).toHaveBeenCalledWith('g-1', 'conversation.created', { conversation_id: 'g-1', type: 'group' }, 'alice');
  });

  it('needs a name for a group', async () => {
    const service = new ConversationsService({ query: jest.fn() } as any, {} as any);
    await expect(service.createConversation('alice', { type: 'group', title: '  ', participant_user_ids: ['bob'] }))
      .rejects.toThrow('Group name is required');
  });
});

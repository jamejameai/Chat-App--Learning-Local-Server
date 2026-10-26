import { Test, TestingModule } from '@nestjs/testing';
import { MessagesService } from './messages.service';
import { DatabaseService } from '../database/database.service';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { BarkRelayService } from '../notifications/bark-relay.service';
import { ForbiddenException } from '@nestjs/common';

describe('MessagesService', () => {
  let messagesService: MessagesService;
  let dbMock: any;
  let realtimeMock: any;
  let barkMock: any;

  beforeEach(async () => {
    dbMock = {
      query: jest.fn(),
      transaction: jest.fn(),
    };

    realtimeMock = {
      notifyNewMessage: jest.fn(),
      notifyReceipt: jest.fn(),
    };

    barkMock = {
      onNewMessage: jest.fn(),
      onConversationRead: jest.fn(),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        MessagesService,
        { provide: DatabaseService, useValue: dbMock },
        { provide: RealtimeGateway, useValue: realtimeMock },
        { provide: BarkRelayService, useValue: barkMock },
      ],
    }).compile();

    messagesService = module.get<MessagesService>(MessagesService);
  });

  it('read receipt carries the message sequence so the sender can mark everything up to it as seen', async () => {
    dbMock.query
      .mockResolvedValueOnce({ rows: [{ id: 'm-7', sequence_id: '7' }] }) // message lookup
      .mockResolvedValueOnce({ rows: [] }) // receipt insert
      .mockResolvedValueOnce({ rows: [] }); // last_read update

    const res = await messagesService.recordReceipt('u-2', 'd-2', 'c-1', 'm-7', 'read');

    expect(realtimeMock.notifyReceipt).toHaveBeenCalledWith(
      'c-1',
      expect.objectContaining({ message_id: 'm-7', user_id: 'u-2', status: 'read', sequence_id: '7' }),
    );
    expect(res).toEqual(expect.objectContaining({ success: true, sequence_id: '7' }));
    // Reading the chat takes its Bark alert off the phone
    expect(barkMock.onConversationRead).toHaveBeenCalledWith('u-2', 'c-1');
  });

  it('should reject message submission if user is not a conversation member', async () => {
    dbMock.query.mockResolvedValueOnce({ rows: [] }); // Not a member

    await expect(
      messagesService.submitMessage('u-1', 'd-1', 'c-1', {
        id: '550e8400-e29b-41d4-a716-446655440000',
        envelope_type: 'e2ee_text',
        encrypted_payload: 'ciphertext_base64',
        iv: 'iv_base64',
      }),
    ).rejects.toThrow(ForbiddenException);
  });

  it('should reject message submission if user is read_only', async () => {
    dbMock.query.mockResolvedValueOnce({ rows: [{ id: 'mem-1', role: 'read_only' }] });

    await expect(
      messagesService.submitMessage('u-1', 'd-1', 'c-1', {
        id: '550e8400-e29b-41d4-a716-446655440000',
        envelope_type: 'e2ee_text',
        encrypted_payload: 'ciphertext_base64',
        iv: 'iv_base64',
      }),
    ).rejects.toThrow('Read-only members cannot publish messages to this channel');
  });

  it("sending a message marks the sender's own read position, so it never counts as unread for them", async () => {
    dbMock.query
      .mockResolvedValueOnce({ rows: [{ id: 'mem-1', role: 'member' }] }) // member check
      .mockResolvedValueOnce({ rows: [] }); // not a duplicate
    const client = { query: jest.fn() };
    client.query
      .mockResolvedValueOnce({ rows: [{ last_sequence_id: '8' }] }) // sequence allocation
      .mockResolvedValueOnce({ rows: [{ id: 'm-8', sequence_id: '8', created_at: new Date() }] }) // insert
      .mockResolvedValueOnce({ rows: [] }); // sender read position
    dbMock.transaction.mockImplementation(async (fn: any) => fn(client));

    await messagesService.submitMessage('u-1', 'd-1', 'c-1', {
      id: '550e8400-e29b-41d4-a716-446655440000',
      envelope_type: 'e2ee_text',
      encrypted_payload: 'ciphertext_base64',
      iv: 'iv_base64',
    });

    const readUpdate = client.query.mock.calls.find(([sql]) => /last_read_sequence_id/.test(sql));
    expect(readUpdate).toBeDefined();
    expect(readUpdate[1]).toEqual(['8', 'c-1', 'u-1']);
  });

  it('should return existing message if UUID is deduplicated (idempotent)', async () => {
    dbMock.query
      .mockResolvedValueOnce({ rows: [{ id: 'mem-1', role: 'member' }] }) // Member check
      .mockResolvedValueOnce({
        rows: [
          {
            id: '550e8400-e29b-41d4-a716-446655440000',
            sequence_id: 42,
            created_at: new Date('2026-10-17T20:00:00Z'),
          },
        ],
      }); // Existing message check

    const res = await messagesService.submitMessage('u-1', 'd-1', 'c-1', {
      id: '550e8400-e29b-41d4-a716-446655440000',
      envelope_type: 'e2ee_text',
      encrypted_payload: 'ciphertext_base64',
      iv: 'iv_base64',
    });

    expect(res.deduplicated).toBe(true);
    expect(res.sequence_id).toBe(42);
    expect(dbMock.transaction).not.toHaveBeenCalled();
  });
});

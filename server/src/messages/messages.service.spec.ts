import { Test, TestingModule } from '@nestjs/testing';
import { MessagesService } from './messages.service';
import { DatabaseService } from '../database/database.service';
import { ForbiddenException } from '@nestjs/common';

describe('MessagesService', () => {
  let messagesService: MessagesService;
  let dbMock: any;

  beforeEach(async () => {
    dbMock = {
      query: jest.fn(),
      transaction: jest.fn(),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        MessagesService,
        { provide: DatabaseService, useValue: dbMock },
      ],
    }).compile();

    messagesService = module.get<MessagesService>(MessagesService);
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

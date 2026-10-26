import { Test, TestingModule } from '@nestjs/testing';
import { AuthService } from './auth.service';
import { DatabaseService } from '../database/database.service';
import { JwtService } from '@nestjs/jwt';
import { BadRequestException, UnauthorizedException, ConflictException } from '@nestjs/common';
import * as bcrypt from 'bcrypt';

describe('AuthService', () => {
  let authService: AuthService;
  let dbMock: any;
  let jwtMock: any;

  beforeEach(async () => {
    dbMock = {
      query: jest.fn(),
      transaction: jest.fn(),
    };

    jwtMock = {
      sign: jest.fn().mockReturnValue('mock_jwt_access_token'),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        AuthService,
        { provide: DatabaseService, useValue: dbMock },
        { provide: JwtService, useValue: jwtMock },
      ],
    }).compile();

    authService = module.get<AuthService>(AuthService);
  });

  describe('validateInvitation', () => {
    it('should throw BadRequestException if invitation code does not exist', async () => {
      dbMock.query.mockResolvedValueOnce({ rows: [] });

      await expect(authService.validateInvitation('invalid_code')).rejects.toThrow(
        BadRequestException,
      );
    });

    it('should throw BadRequestException if invitation is revoked', async () => {
      dbMock.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'inv-1',
            role: 'member',
            expires_at: new Date(Date.now() + 86400000),
            revoked: true,
            used_at: null,
          },
        ],
      });

      await expect(authService.validateInvitation('revoked_code')).rejects.toThrow(
        'Invitation has been revoked by an administrator',
      );
    });

    it('should throw BadRequestException if invitation has already been redeemed', async () => {
      dbMock.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'inv-1',
            role: 'member',
            expires_at: new Date(Date.now() + 86400000),
            revoked: false,
            used_at: new Date(),
          },
        ],
      });

      await expect(authService.validateInvitation('used_code')).rejects.toThrow(
        'Invitation has already been redeemed',
      );
    });

    it('should throw BadRequestException if invitation has expired', async () => {
      dbMock.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'inv-1',
            role: 'member',
            expires_at: new Date(Date.now() - 86400000), // Expired yesterday
            revoked: false,
            used_at: null,
          },
        ],
      });

      await expect(authService.validateInvitation('expired_code')).rejects.toThrow(
        'Invitation has expired',
      );
    });

    it('should return valid details for an unredeemed, active invitation', async () => {
      const expires = new Date(Date.now() + 86400000);
      dbMock.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'inv-1',
            role: 'member',
            expires_at: expires,
            revoked: false,
            used_at: null,
          },
        ],
      });

      const res = await authService.validateInvitation('valid_code');
      expect(res.valid).toBe(true);
      expect(res.role).toBe('member');
      expect(res.expires_at).toBe(expires);
    });
  });

  describe('login', () => {
    it('should reject invalid password', async () => {
      const hash = await bcrypt.hash('CorrectPassword123!', 10);
      dbMock.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'u-1',
            username: 'alice',
            display_name: 'Alice',
            password_hash: hash,
            role: 'member',
            status: 'active',
          },
        ],
      });

      await expect(
        authService.login({ username: 'alice', password: 'WrongPassword' }),
      ).rejects.toThrow(UnauthorizedException);
    });

    it('should reject suspended user even with correct password', async () => {
      const hash = await bcrypt.hash('CorrectPassword123!', 10);
      dbMock.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'u-1',
            username: 'bad_actor',
            display_name: 'Bad Actor',
            password_hash: hash,
            role: 'member',
            status: 'suspended',
          },
        ],
      });

      await expect(
        authService.login({ username: 'bad_actor', password: 'CorrectPassword123!' }),
      ).rejects.toThrow('Account has been suspended or deactivated');
    });

    describe('updateProfile', () => {
      it('stores developer profile JSON and returns it with the updated user', async () => {
        const developerProfile = {
          headline: 'iOS Developer',
          skills: ['Swift', 'SwiftUI'],
          projects: [
            {
              id: 'project-1',
              title: 'Our Chat',
              summary: 'A private messaging app',
              technologies: ['SwiftUI'],
              repository_url: 'https://github.com/example/our-chat',
              live_url: 'https://example.com',
            },
          ],
          website_url: 'https://example.com',
          github_url: 'https://github.com/example',
          social_links: {
            linkedin_url: 'https://linkedin.com/in/example',
            instagram_url: null,
            x_url: null,
          },
          currently_building: 'A new app',
          work_availability: 'open_to_opportunities',
          location: 'Phnom Penh',
        };
        dbMock.query.mockResolvedValueOnce({
          rows: [{ id: 'u-1', developer_profile: developerProfile }],
        });

        const result = await authService.updateProfile('u-1', {
          developer_profile: developerProfile,
        } as any);

        expect(dbMock.query).toHaveBeenCalledWith(
          expect.stringContaining('developer_profile = $1::jsonb'),
          [JSON.stringify(developerProfile), 'u-1'],
        );
        expect(result.developer_profile).toEqual(developerProfile);
      });
    });
  });
});

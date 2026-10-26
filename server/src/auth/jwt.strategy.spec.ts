import { UnauthorizedException } from '@nestjs/common';
import { JwtStrategy } from './jwt.strategy';

describe('JwtStrategy.validate', () => {
  const query = jest.fn();
  let strategy: JwtStrategy;

  const activeDevice = () =>
    query
      .mockResolvedValueOnce({ rows: [{ is_revoked: false }] }) // device lookup
      .mockResolvedValueOnce({ rows: [{ status: 'active', role: 'member' }] }); // user lookup

  beforeEach(() => {
    query.mockReset();
    strategy = new JwtStrategy({ query } as any);
  });

  it('exposes the device id carried in the token (AuthService signs it as "deviceId")', async () => {
    activeDevice();
    const user = await strategy.validate({ sub: 'u1', deviceId: 'dev-1', username: 'alex' });
    expect(user.deviceId).toBe('dev-1');
    expect(user.userId).toBe('u1');
    expect(query.mock.calls[0][1]).toEqual(['dev-1', 'u1']);
  });

  it('still accepts the legacy "device_id" claim', async () => {
    activeDevice();
    const user = await strategy.validate({ sub: 'u1', device_id: 'dev-legacy', username: 'alex' });
    expect(user.deviceId).toBe('dev-legacy');
  });

  it('rejects a revoked device', async () => {
    query.mockResolvedValueOnce({ rows: [{ is_revoked: true }] });
    await expect(
      strategy.validate({ sub: 'u1', deviceId: 'dev-1', username: 'alex' }),
    ).rejects.toBeInstanceOf(UnauthorizedException);
  });
});

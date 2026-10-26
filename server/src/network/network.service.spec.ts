import { NetworkService } from './network.service';

describe('NetworkService', () => {
  const realFetch = global.fetch;
  const realEnv = process.env.TUNNEL_METRICS_URL;
  let service: NetworkService;

  const mockTunnel = (body: unknown, ok = true) => {
    global.fetch = jest.fn().mockResolvedValue({ ok, json: async () => body }) as any;
  };

  beforeEach(() => {
    process.env.TUNNEL_METRICS_URL = 'http://tunnel:2000';
    service = new NetworkService();
  });

  afterEach(() => {
    global.fetch = realFetch;
    if (realEnv === undefined) delete process.env.TUNNEL_METRICS_URL;
    else process.env.TUNNEL_METRICS_URL = realEnv;
  });

  it('returns the https API url for a quick-tunnel hostname', async () => {
    mockTunnel({ hostname: 'quiet-river-1234.trycloudflare.com' });
    await expect(service.getPublicApiUrl()).resolves.toBe(
      'https://quiet-river-1234.trycloudflare.com/api/v1',
    );
    expect(global.fetch).toHaveBeenCalledWith(
      'http://tunnel:2000/quicktunnel',
      expect.anything(),
    );
  });

  it('prefers a fixed https PUBLIC_API_URL over the tunnel', async () => {
    process.env.PUBLIC_API_URL = 'https://jjserver.tail87c566.ts.net/api/v1/';
    global.fetch = jest.fn() as any;
    try {
      await expect(service.getPublicApiUrl()).resolves.toBe(
        'https://jjserver.tail87c566.ts.net/api/v1',
      );
      expect(global.fetch).not.toHaveBeenCalled();
    } finally {
      delete process.env.PUBLIC_API_URL;
    }
  });

  it('returns null when no tunnel is configured', async () => {
    delete process.env.TUNNEL_METRICS_URL;
    global.fetch = jest.fn() as any;
    await expect(service.getPublicApiUrl()).resolves.toBeNull();
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('refuses hostnames that are not quick-tunnel domains', async () => {
    mockTunnel({ hostname: 'evil.example.com' });
    await expect(service.getPublicApiUrl()).resolves.toBeNull();
  });

  it('returns null when the tunnel is unreachable or errors', async () => {
    global.fetch = jest.fn().mockRejectedValue(new Error('connect refused')) as any;
    await expect(service.getPublicApiUrl()).resolves.toBeNull();
    service = new NetworkService();
    mockTunnel({}, false);
    await expect(service.getPublicApiUrl()).resolves.toBeNull();
  });

  it('caches the lookup briefly', async () => {
    mockTunnel({ hostname: 'cached-name.trycloudflare.com' });
    await service.getPublicApiUrl();
    await service.getPublicApiUrl();
    expect(global.fetch).toHaveBeenCalledTimes(1);
  });
});

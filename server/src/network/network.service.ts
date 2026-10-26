import { Injectable, Logger } from '@nestjs/common';

const QUICK_TUNNEL_HOST = /^[a-z0-9-]+\.trycloudflare\.com$/;
const CACHE_MS = 10_000;

/**
 * Tells clients where this server can be reached from the internet.
 * A fixed https address (PUBLIC_API_URL, e.g. the Tailscale Funnel name) wins.
 * Otherwise: a Cloudflare quick tunnel gets a new random hostname on every restart,
 * so the current one is read live from the cloudflared sidecar's metrics endpoint.
 */
@Injectable()
export class NetworkService {
  private readonly logger = new Logger(NetworkService.name);
  private cached: { url: string | null; at: number } | null = null;

  async getPublicApiUrl(): Promise<string | null> {
    const fixed = (process.env.PUBLIC_API_URL || '').trim().replace(/\/+$/, '');
    if (fixed.startsWith('https://')) {
      return fixed;
    }
    if (this.cached && Date.now() - this.cached.at < CACHE_MS) {
      return this.cached.url;
    }
    const url = await this.fetchTunnelUrl();
    this.cached = { url, at: Date.now() };
    return url;
  }

  private async fetchTunnelUrl(): Promise<string | null> {
    const metricsUrl = process.env.TUNNEL_METRICS_URL;
    if (!metricsUrl) {
      return null;
    }
    try {
      const res = await fetch(`${metricsUrl}/quicktunnel`, {
        signal: AbortSignal.timeout(1500),
      });
      if (!res.ok) {
        return null;
      }
      const body = (await res.json()) as { hostname?: string };
      const hostname = (body.hostname || '').trim().toLowerCase();
      // Only ever hand out a genuine quick-tunnel hostname
      if (!QUICK_TUNNEL_HOST.test(hostname)) {
        return null;
      }
      return `https://${hostname}/api/v1`;
    } catch (err) {
      this.logger.debug(`Tunnel metrics unavailable: ${(err as Error).message}`);
      return null;
    }
  }
}

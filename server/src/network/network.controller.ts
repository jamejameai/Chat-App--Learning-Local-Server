import { Controller, Get } from '@nestjs/common';
import { NetworkService } from './network.service';

@Controller('network')
export class NetworkController {
  constructor(private readonly network: NetworkService) {}

  /** Public (no auth): lets the app learn the internet-reachable address while on the home LAN. */
  @Get('config')
  async getConfig() {
    return { public_url: await this.network.getPublicApiUrl() };
  }
}

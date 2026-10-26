import { Body, Controller, Post, UseGuards } from "@nestjs/common";
import { Throttle, ThrottlerGuard } from "@nestjs/throttler";
import { LocationsService } from "./locations.service";
import { RevokeLocationShareDto } from "./dto/revoke-location-share.dto";

@Controller("locations")
export class LocationRevocationController {
  constructor(private readonly locationsService: LocationsService) {}

  @Post("revoke")
  @UseGuards(ThrottlerGuard)
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  async revokeSharing(@Body() dto: RevokeLocationShareDto) {
    return this.locationsService.stopSharingWithToken(dto.stop_token);
  }
}

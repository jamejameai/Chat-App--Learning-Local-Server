import {
  Body,
  Controller,
  Delete,
  Get,
  Post,
  Put,
  UseGuards,
} from '@nestjs/common';
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { LocationsService } from './locations.service';
import { StartLocationShareDto } from './dto/start-location-share.dto';
import { UpdateLocationDto } from './dto/update-location.dto';

@Controller('locations')
@UseGuards(JwtAuthGuard)
export class LocationsController {
  constructor(private readonly locationsService: LocationsService) {}

  @Get('friends')
  async getFriendLocations(@CurrentUser('userId') userId: string) {
    return this.locationsService.getFriendLocations(userId);
  }

  @Get('me')
  async getShareState(@CurrentUser('userId') userId: string) {
    return this.locationsService.getShareState(userId);
  }

  @Post('me')
  @UseGuards(ThrottlerGuard)
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  async beginSharing(
    @CurrentUser('userId') userId: string,
    @Body() dto: StartLocationShareDto,
  ) {
    return this.locationsService.beginSharing(userId, dto);
  }

  @Put('me')
  @UseGuards(ThrottlerGuard)
  @Throttle({ default: { limit: 60, ttl: 60_000 } })
  async updateSharing(
    @CurrentUser('userId') userId: string,
    @Body() dto: UpdateLocationDto,
  ) {
    return this.locationsService.updateSharing(userId, dto);
  }

  @Delete('me')
  async stopSharing(@CurrentUser('userId') userId: string) {
    return this.locationsService.stopSharing(userId);
  }
}

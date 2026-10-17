import {
  Controller,
  Get,
  Post,
  Param,
  Body,
  UseGuards,
} from '@nestjs/common';
import { DevicesService } from './devices.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { OneTimePrekeyDto } from '../auth/dto/register-invite.dto';

@Controller('devices')
@UseGuards(JwtAuthGuard)
export class DevicesController {
  constructor(private readonly devicesService: DevicesService) {}

  @Get(':userId/prekey-bundle')
  async getPrekeyBundle(@Param('userId') userId: string) {
    return await this.devicesService.getPrekeyBundle(userId);
  }

  @Post('prekeys/refill')
  async refillPrekeys(
    @CurrentUser('deviceId') deviceId: string,
    @Body('prekeys') prekeys: OneTimePrekeyDto[],
  ) {
    return await this.devicesService.refillPrekeys(deviceId, prekeys);
  }

  @Get()
  async listMyDevices(@CurrentUser('userId') userId: string) {
    return await this.devicesService.listUserDevices(userId);
  }

  @Post(':id/revoke')
  async revokeDevice(
    @CurrentUser() user: any,
    @Param('id') deviceId: string,
  ) {
    const isSuperAdmin = user.role === 'superadmin';
    return await this.devicesService.revokeDevice(user.userId, deviceId, isSuperAdmin);
  }
}

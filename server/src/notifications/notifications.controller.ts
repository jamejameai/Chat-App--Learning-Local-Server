import {
  Controller,
  Get,
  Post,
  Put,
  Patch,
  Delete,
  Body,
  Param,
  UseGuards,
} from '@nestjs/common';
import { NotificationsService } from './notifications.service';
import { BarkRelayService } from './bark-relay.service';
import { IsString, IsNotEmpty, IsUUID, IsOptional, IsBoolean, IsIn, MaxLength } from 'class-validator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';

class RegisterTokenDto {
  @IsString()
  @IsNotEmpty()
  apns_token: string;

  @IsUUID()
  @IsNotEmpty()
  device_id: string;
}

class BarkSettingsDto {
  @IsOptional()
  @IsBoolean()
  enabled?: boolean;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  message_sound?: string;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  call_sound?: string;

  @IsOptional()
  @IsIn(['en', 'km'])
  language?: string;
}

class SaveBarkKeyDto extends BarkSettingsDto {
  /** The address shown in the Bark app ("https://api.day.app/<key>/") or just the key */
  @IsString()
  @IsNotEmpty()
  @MaxLength(512)
  key: string;
}

// The login token gives { userId, deviceId } (see JwtStrategy); there is no `user.id`.
@Controller('notifications')
@UseGuards(JwtAuthGuard)
export class NotificationsController {
  constructor(
    private readonly notificationsService: NotificationsService,
    private readonly barkRelay: BarkRelayService,
  ) {}

  @Post('token')
  async registerToken(@CurrentUser('userId') userId: string, @Body() dto: RegisterTokenDto) {
    return await this.notificationsService.registerToken(
      userId,
      dto.device_id,
      dto.apns_token,
    );
  }

  @Delete('token/:device_id')
  async unregisterToken(@Param('device_id') deviceId: string) {
    return await this.notificationsService.unregisterToken(deviceId);
  }

  @Post('test')
  async testPush(@CurrentUser('userId') userId: string) {
    return await this.notificationsService.sendZeroKnowledgePush(userId, {
      conversationId: '00000000-0000-0000-0000-000000000000',
      sequenceId: 1,
      envelopeType: 'double_ratchet',
      encryptedPayload: 'test_encrypted_payload',
      iv: 'test_iv',
    });
  }

  // Alerts while the app is closed, relayed through the Bark app (see BarkRelayService)

  @Get('bark')
  async getBark(@CurrentUser('userId') userId: string) {
    return await this.barkRelay.getSettings(userId);
  }

  /** Saves a Bark key; a test alert is sent first and a key Bark doesn't know is refused. */
  @Put('bark')
  async saveBark(@CurrentUser('userId') userId: string, @Body() dto: SaveBarkKeyDto) {
    const { key, ...settings } = dto;
    return await this.barkRelay.saveKey(userId, key, settings);
  }

  @Patch('bark')
  async updateBark(@CurrentUser('userId') userId: string, @Body() dto: BarkSettingsDto) {
    return await this.barkRelay.updateSettings(userId, dto);
  }

  @Post('bark/test')
  async testBark(@CurrentUser('userId') userId: string) {
    return await this.barkRelay.sendTest(userId);
  }

  @Delete('bark')
  async removeBark(@CurrentUser('userId') userId: string) {
    return await this.barkRelay.removeRelay(userId);
  }
}

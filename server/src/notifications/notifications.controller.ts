import {
  Controller,
  Post,
  Delete,
  Body,
  Param,
  UseGuards,
  Request,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { NotificationsService } from './notifications.service';
import { IsString, IsNotEmpty, IsUUID } from 'class-validator';

class RegisterTokenDto {
  @IsString()
  @IsNotEmpty()
  apns_token: string;

  @IsUUID()
  @IsNotEmpty()
  device_id: string;
}

@Controller('notifications')
@UseGuards(AuthGuard('jwt'))
export class NotificationsController {
  constructor(private readonly notificationsService: NotificationsService) {}

  @Post('token')
  async registerToken(@Request() req: any, @Body() dto: RegisterTokenDto) {
    return await this.notificationsService.registerToken(
      req.user.id,
      dto.device_id,
      dto.apns_token,
    );
  }

  @Delete('token/:device_id')
  async unregisterToken(@Param('device_id') deviceId: string) {
    return await this.notificationsService.unregisterToken(deviceId);
  }

  @Post('test')
  async testPush(@Request() req: any) {
    return await this.notificationsService.sendZeroKnowledgePush(req.user.id, {
      conversationId: '00000000-0000-0000-0000-000000000000',
      sequenceId: 1,
      envelopeType: 'double_ratchet',
      encryptedPayload: 'test_encrypted_payload',
      iv: 'test_iv',
    });
  }
}

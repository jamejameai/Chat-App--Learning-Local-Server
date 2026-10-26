import {
  Controller,
  Post,
  Get,
  Body,
  Param,
  UseGuards,
  ParseUUIDPipe,
} from '@nestjs/common';
import { CallsService } from './calls.service';
import { IsUUID, IsIn, IsNotEmpty } from 'class-validator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';

class InitiateCallDto {
  @IsUUID()
  @IsNotEmpty()
  conversation_id: string;

  @IsIn(['audio', 'video'])
  @IsNotEmpty()
  call_type: 'audio' | 'video';
}

// The login token gives { userId, deviceId } (see JwtStrategy); there is no `user.id`.
@Controller('calls')
@UseGuards(JwtAuthGuard)
export class CallsController {
  constructor(private readonly callsService: CallsService) {}

  @Post('initiate')
  async initiateCall(
    @CurrentUser('userId') userId: string,
    @CurrentUser('deviceId') deviceId: string,
    @Body() dto: InitiateCallDto,
  ) {
    return await this.callsService.initiateCall(dto.conversation_id, userId, deviceId, dto.call_type);
  }

  @Post(':id/join')
  async joinCall(
    @CurrentUser('userId') userId: string,
    @CurrentUser('deviceId') deviceId: string,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return await this.callsService.joinCall(id, userId, deviceId);
  }

  @Post(':id/end')
  async endCall(
    @CurrentUser('userId') userId: string,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return await this.callsService.endCall(id, userId);
  }

  @Get('history')
  async getCallHistory(@CurrentUser('userId') userId: string) {
    return await this.callsService.getCallHistory(userId);
  }
}

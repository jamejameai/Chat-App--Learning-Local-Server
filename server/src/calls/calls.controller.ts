import {
  Controller,
  Post,
  Get,
  Body,
  Param,
  UseGuards,
  Request,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { CallsService } from './calls.service';
import { IsUUID, IsIn, IsNotEmpty } from 'class-validator';

class InitiateCallDto {
  @IsUUID()
  @IsNotEmpty()
  conversation_id: string;

  @IsIn(['audio', 'video'])
  @IsNotEmpty()
  call_type: 'audio' | 'video';
}

@Controller('calls')
@UseGuards(AuthGuard('jwt'))
export class CallsController {
  constructor(private readonly callsService: CallsService) {}

  @Post('initiate')
  async initiateCall(@Request() req: any, @Body() dto: InitiateCallDto) {
    return await this.callsService.initiateCall(
      dto.conversation_id,
      req.user.id,
      dto.call_type,
    );
  }

  @Post(':id/join')
  async joinCall(@Request() req: any, @Param('id') id: string) {
    return await this.callsService.joinCall(id, req.user.id);
  }

  @Post(':id/end')
  async endCall(@Request() req: any, @Param('id') id: string) {
    return await this.callsService.endCall(id, req.user.id);
  }

  @Get('history')
  async getCallHistory(@Request() req: any) {
    return await this.callsService.getCallHistory(req.user.id);
  }
}

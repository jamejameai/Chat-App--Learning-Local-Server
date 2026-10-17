import {
  Controller,
  Post,
  Get,
  Delete,
  Param,
  Body,
  UseGuards,
  Query,
} from '@nestjs/common';
import { InvitationsService } from './invitations.service';
import { CreateInvitationDto } from './dto/create-invitation.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard, Roles } from '../auth/guards/roles.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';

@Controller('invitations')
@UseGuards(JwtAuthGuard, RolesGuard)
export class InvitationsController {
  constructor(private readonly invitationsService: InvitationsService) {}

  @Post()
  @Roles('superadmin')
  async createInvitation(
    @CurrentUser('userId') userId: string,
    @Body() dto: CreateInvitationDto,
  ) {
    return await this.invitationsService.createInvitation(userId, dto);
  }

  @Get()
  @Roles('superadmin')
  async listInvitations(
    @Query('limit') limit?: number,
    @Query('offset') offset?: number,
  ) {
    return await this.invitationsService.listInvitations(
      limit ? parseInt(limit.toString(), 10) : 50,
      offset ? parseInt(offset.toString(), 10) : 0,
    );
  }

  @Delete(':id')
  @Roles('superadmin')
  async revokeInvitation(
    @CurrentUser('userId') userId: string,
    @Param('id') id: string,
  ) {
    return await this.invitationsService.revokeInvitation(userId, id);
  }
}

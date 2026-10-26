import {
  Controller,
  Get,
  Patch,
  Delete,
  Post,
  Body,
  Param,
  Query,
  UseGuards,
  ForbiddenException,
  ParseUUIDPipe,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AdminService } from './admin.service';
import { UpdateUserStatusDto, UpdateUserRoleDto, BroadcastMessageDto } from './dto/admin.dto';

@Controller('admin')
@UseGuards(JwtAuthGuard)
export class AdminController {
  constructor(private readonly adminService: AdminService) {}

  private checkAdminAccess(role: string) {
    if (role !== 'owner' && role !== 'superadmin') {
      throw new ForbiddenException('Admin panel access requires Owner or Super-Admin privileges');
    }
  }

  @Get('users')
  async listUsers(
    @CurrentUser('role') role: string,
    @Query('search') search?: string,
  ) {
    this.checkAdminAccess(role);
    return await this.adminService.listAllUsers(search);
  }

  @Patch('users/:userId/status')
  async updateUserStatus(
    @CurrentUser('userId') actorUserId: string,
    @CurrentUser('role') actorRole: string,
    @Param('userId', ParseUUIDPipe) targetUserId: string,
    @Body() dto: UpdateUserStatusDto,
  ) {
    this.checkAdminAccess(actorRole);
    return await this.adminService.updateUserStatus(targetUserId, dto.status, actorUserId);
  }

  @Patch('users/:userId/role')
  async updateUserRole(
    @CurrentUser('role') actorRole: string,
    @Param('userId', ParseUUIDPipe) targetUserId: string,
    @Body() dto: UpdateUserRoleDto,
  ) {
    this.checkAdminAccess(actorRole);
    return await this.adminService.updateUserRole(targetUserId, dto.role, actorRole);
  }

  @Delete('users/:userId/sessions')
  async revokeUserSessions(
    @CurrentUser('role') actorRole: string,
    @Param('userId', ParseUUIDPipe) targetUserId: string,
  ) {
    this.checkAdminAccess(actorRole);
    return await this.adminService.revokeUserSessions(targetUserId);
  }

  @Delete('users/:userId')
  async deleteUser(
    @CurrentUser('role') actorRole: string,
    @Param('userId', ParseUUIDPipe) targetUserId: string,
  ) {
    this.checkAdminAccess(actorRole);
    return await this.adminService.deleteUser(targetUserId, actorRole);
  }

  @Get('stats')
  async getSystemStats(@CurrentUser('role') role: string) {
    this.checkAdminAccess(role);
    return await this.adminService.getSystemStats();
  }

  @Post('broadcast')
  async broadcastAnnouncement(
    @CurrentUser('role') role: string,
    @CurrentUser('username') username: string,
    @Body() dto: BroadcastMessageDto,
  ) {
    this.checkAdminAccess(role);
    return await this.adminService.broadcastAnnouncement(dto.title, dto.message, username);
  }
}

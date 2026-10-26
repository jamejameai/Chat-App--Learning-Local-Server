import {
  Controller,
  Get,
  Post,
  Delete,
  Body,
  Param,
  Query,
  UseGuards,
  HttpCode,
  HttpStatus,
  ParseUUIDPipe,
} from '@nestjs/common';
import { FriendsService } from './friends.service';
import { AddFriendDto } from './dto/add-friend.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';

@Controller('friends')
@UseGuards(JwtAuthGuard)
export class FriendsController {
  constructor(private readonly friendsService: FriendsService) {}

  @Get()
  async getFriends(@CurrentUser('userId') userId: string) {
    return await this.friendsService.getFriends(userId);
  }

  @Get('search')
  async searchUsers(
    @CurrentUser('userId') userId: string,
    @Query('q') query: string,
  ) {
    return await this.friendsService.searchFriends(userId, query || '');
  }

  @Get('profile/:userId')
  async getProfile(
    @CurrentUser('userId') userId: string,
    @Param('userId', ParseUUIDPipe) profileUserId: string,
  ) {
    return await this.friendsService.getProfile(userId, profileUserId);
  }

  @Post('add')
  @HttpCode(HttpStatus.OK)
  async addFriend(
    @CurrentUser('userId') userId: string,
    @Body() dto: AddFriendDto,
  ) {
    return await this.friendsService.addFriend(userId, dto.identifier);
  }

  @Delete(':friendId')
  async removeFriend(
    @CurrentUser('userId') userId: string,
    @Param('friendId', ParseUUIDPipe) friendId: string,
  ) {
    return await this.friendsService.removeFriend(userId, friendId);
  }
}

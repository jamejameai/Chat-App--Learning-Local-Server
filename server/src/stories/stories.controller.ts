import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Post,
  UseGuards,
} from '@nestjs/common';
import { StoriesService } from './stories.service';
import { CreateStoryDto } from './dto/create-story.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';

@Controller('stories')
@UseGuards(JwtAuthGuard)
export class StoriesController {
  constructor(private readonly storiesService: StoriesService) {}

  @Get()
  async getFeed(@CurrentUser('userId') userId: string) {
    return await this.storiesService.getFeed(userId);
  }

  @Post()
  async createStory(@CurrentUser('userId') userId: string, @Body() dto: CreateStoryDto) {
    return await this.storiesService.createStory(userId, dto);
  }

  @Post(':id/view')
  @HttpCode(HttpStatus.OK)
  async markViewed(
    @CurrentUser('userId') userId: string,
    @Param('id', ParseUUIDPipe) storyId: string,
  ) {
    return await this.storiesService.markViewed(storyId, userId);
  }

  @Get(':id/viewers')
  async getViewers(
    @CurrentUser('userId') userId: string,
    @Param('id', ParseUUIDPipe) storyId: string,
  ) {
    return await this.storiesService.getViewers(storyId, userId);
  }

  @Delete(':id')
  async deleteStory(
    @CurrentUser('userId') userId: string,
    @Param('id', ParseUUIDPipe) storyId: string,
  ) {
    return await this.storiesService.deleteStory(storyId, userId);
  }

  @Post(':id/react')
  @HttpCode(HttpStatus.OK)
  async reactToStory(
    @CurrentUser('userId') userId: string,
    @Param('id', ParseUUIDPipe) storyId: string,
    @Body('reaction') reaction: string,
  ) {
    return await this.storiesService.reactToStory(storyId, userId, reaction || 'heart');
  }

  @Get(':id/reactions')
  async getReactions(
    @CurrentUser('userId') userId: string,
    @Param('id', ParseUUIDPipe) storyId: string,
  ) {
    return await this.storiesService.getStoryReactions(storyId, userId);
  }

  @Post(':id/reply')
  @HttpCode(HttpStatus.OK)
  async replyToStory(
    @CurrentUser('userId') userId: string,
    @Param('id', ParseUUIDPipe) storyId: string,
    @Body('text') text: string,
  ) {
    return await this.storiesService.replyToStory(storyId, userId, text);
  }
}


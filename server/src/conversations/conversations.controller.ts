import {
  Controller,
  Get,
  Post,
  Param,
  Body,
  Query,
  UseGuards,
} from '@nestjs/common';
import { ConversationsService } from './conversations.service';
import { CreateConversationDto } from './dto/create-conversation.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';

@Controller('conversations')
@UseGuards(JwtAuthGuard)
export class ConversationsController {
  constructor(private readonly conversationsService: ConversationsService) {}

  @Get()
  async listConversations(@CurrentUser('userId') userId: string) {
    return await this.conversationsService.listConversations(userId);
  }

  @Post()
  async createConversation(
    @CurrentUser('userId') userId: string,
    @Body() dto: CreateConversationDto,
  ) {
    return await this.conversationsService.createConversation(userId, dto);
  }

  @Get(':id')
  async getConversation(
    @CurrentUser('userId') userId: string,
    @Param('id') conversationId: string,
  ) {
    return await this.conversationsService.getConversation(conversationId, userId);
  }

  @Get(':id/sync')
  async syncConversation(
    @CurrentUser('userId') userId: string,
    @Param('id') conversationId: string,
    @Query('since_sequence') sinceSequence?: number,
    @Query('limit') limit?: number,
  ) {
    return await this.conversationsService.syncConversation(
      conversationId,
      userId,
      sinceSequence ? parseInt(sinceSequence.toString(), 10) : 0,
      limit ? parseInt(limit.toString(), 10) : 50,
    );
  }
}

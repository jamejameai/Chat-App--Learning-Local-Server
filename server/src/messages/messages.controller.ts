import {
  Controller,
  Post,
  Param,
  Body,
  UseGuards,
} from '@nestjs/common';
import { MessagesService } from './messages.service';
import { SubmitMessageDto } from './dto/submit-message.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';

@Controller('conversations/:conversationId/messages')
@UseGuards(JwtAuthGuard)
export class MessagesController {
  constructor(private readonly messagesService: MessagesService) {}

  @Post()
  async submitMessage(
    @CurrentUser('userId') userId: string,
    @CurrentUser('deviceId') deviceId: string,
    @Param('conversationId') conversationId: string,
    @Body() dto: SubmitMessageDto,
  ) {
    return await this.messagesService.submitMessage(
      userId,
      deviceId,
      conversationId,
      dto,
    );
  }
}

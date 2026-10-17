import {
  Controller,
  Post,
  Get,
  Param,
  Body,
  Res,
  UseGuards,
  BadRequestException,
} from '@nestjs/common';
import { Response } from 'express';
import { AttachmentsService } from './attachments.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';

@Controller('attachments')
@UseGuards(JwtAuthGuard)
export class AttachmentsController {
  constructor(private readonly attachmentsService: AttachmentsService) {}

  @Post('upload')
  async upload(
    @CurrentUser('userId') userId: string,
    @Body('data_base64') dataBase64: string,
    @Body('mime_type') mimeType: string,
    @Body('sha256_checksum') checksum?: string,
  ) {
    if (!dataBase64) {
      throw new BadRequestException('Missing data_base64 in request body');
    }

    const buffer = Buffer.from(dataBase64, 'base64');
    return await this.attachmentsService.uploadAttachment(
      userId,
      buffer,
      mimeType || 'application/octet-stream',
      checksum,
    );
  }

  @Get(':id/download')
  async download(
    @Param('id') attachmentId: string,
    @Res() res: Response,
  ) {
    const file = await this.attachmentsService.getAttachment(attachmentId);

    res.setHeader('Content-Type', 'application/octet-stream');
    res.setHeader('Content-Length', file.byte_size.toString());
    res.setHeader('X-Checksum-SHA256', file.sha256_checksum);
    res.setHeader('Content-Disposition', `attachment; filename="${file.id}.enc"`);

    res.send(file.data);
  }
}

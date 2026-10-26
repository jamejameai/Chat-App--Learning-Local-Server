import {
  Injectable,
  NotFoundException,
  BadRequestException,
  Logger,
} from '@nestjs/common';
import { DatabaseService } from '../database/database.service';
import * as fs from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';

@Injectable()
export class AttachmentsService {
  private readonly logger = new Logger(AttachmentsService.name);
  // On the persistent storage volume (STORAGE_LOCAL_PATH=/uploads in Docker), so files survive
  // server updates; the container's own folder is wiped on every rebuild.
  private readonly uploadDirectory = path.resolve(
    process.env.STORAGE_LOCAL_PATH || path.join(process.cwd(), 'uploads'),
    'attachments',
  );

  constructor(private readonly db: DatabaseService) {
    if (!fs.existsSync(this.uploadDirectory)) {
      fs.mkdirSync(this.uploadDirectory, { recursive: true });
    }
  }

  async uploadAttachment(
    userId: string,
    fileData: Buffer,
    mimeType: string,
    declaredChecksum?: string,
  ) {
    if (!fileData || fileData.length === 0) {
      throw new BadRequestException('Empty attachment data received');
    }

    // 1. Verify SHA-256 integrity checksum
    const computedChecksum = crypto.createHash('sha256').update(fileData).digest('hex');
    if (declaredChecksum && declaredChecksum.toLowerCase() !== computedChecksum.toLowerCase()) {
      throw new BadRequestException('Integrity checksum verification failed');
    }

    // 2. Persist encrypted ciphertext blob on disk
    const attachmentId = crypto.randomUUID();
    const fileName = `${attachmentId}.enc`;
    const filePath = path.join(this.uploadDirectory, fileName);

    fs.writeFileSync(filePath, fileData);

    // 3. Insert record into database
    await this.db.query(
      `INSERT INTO attachments (id, uploaded_by_user_id, byte_size, sha256_checksum, storage_path, mime_type)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [attachmentId, userId, fileData.length, computedChecksum, filePath, mimeType],
    );

    this.logger.log(`Attachment stored: ${attachmentId} (${fileData.length} bytes, ${mimeType})`);

    return {
      id: attachmentId,
      byte_size: fileData.length,
      sha256_checksum: computedChecksum,
      mime_type: mimeType,
      download_url: `/api/v1/attachments/${attachmentId}/download`,
    };
  }

  async getAttachment(attachmentId: string) {
    const res = await this.db.query(
      'SELECT id, byte_size, sha256_checksum, storage_path, mime_type FROM attachments WHERE id = $1',
      [attachmentId],
    );

    if (res.rows.length === 0) {
      throw new NotFoundException('Attachment not found');
    }

    const item = res.rows[0];
    if (!fs.existsSync(item.storage_path)) {
      throw new NotFoundException('Attachment binary not found in storage');
    }

    const data = fs.readFileSync(item.storage_path);
    return {
      ...item,
      data,
    };
  }
}

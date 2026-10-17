import { Controller, Get, HttpStatus, Res } from '@nestjs/common';
import { Response } from 'express';
import { DatabaseService } from '../database/database.service';
import * as fs from 'fs';
import * as path from 'path';

@Controller('health')
export class HealthController {
  constructor(private readonly db: DatabaseService) {}

  @Get()
  async checkHealth(@Res() res: Response) {
    let dbStatus = 'disconnected';
    let storageStatus = 'unwritable';

    try {
      const dbRes = await this.db.query('SELECT 1 as alive');
      if (dbRes.rows?.[0]?.alive === 1) {
        dbStatus = 'connected';
      }
    } catch (err) {
      dbStatus = 'error';
    }

    try {
      const storagePath = process.env.STORAGE_LOCAL_PATH || './uploads';
      if (!fs.existsSync(storagePath)) {
        fs.mkdirSync(storagePath, { recursive: true });
      }
      const testFile = path.join(storagePath, '.health_check');
      fs.writeFileSync(testFile, 'ok');
      fs.unlinkSync(testFile);
      storageStatus = 'writable';
    } catch (err) {
      storageStatus = 'error';
    }

    const isHealthy = dbStatus === 'connected' && storageStatus === 'writable';
    return res.status(isHealthy ? HttpStatus.OK : HttpStatus.SERVICE_UNAVAILABLE).json({
      status: isHealthy ? 'ok' : 'degraded',
      timestamp: new Date().toISOString(),
      database: dbStatus,
      storage: storageStatus,
      uptime: process.uptime(),
    });
  }
}

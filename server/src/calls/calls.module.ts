import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { CallsController } from './calls.controller';
import { CallsService } from './calls.service';
import { DatabaseModule } from '../database/database.module';
import { RealtimeModule } from '../realtime/realtime.module';

@Module({
  imports: [DatabaseModule, ConfigModule, RealtimeModule],
  controllers: [CallsController],
  providers: [CallsService],
  exports: [CallsService],
})
export class CallsModule {}

import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { NotificationsController } from './notifications.controller';
import { NotificationsService } from './notifications.service';
import { BarkRelayService } from './bark-relay.service';
import { DatabaseModule } from '../database/database.module';

@Module({
  imports: [DatabaseModule, ConfigModule],
  controllers: [NotificationsController],
  providers: [NotificationsService, BarkRelayService],
  exports: [NotificationsService, BarkRelayService],
})
export class NotificationsModule {}

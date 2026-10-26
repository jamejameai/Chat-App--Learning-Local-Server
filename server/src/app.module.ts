import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ThrottlerModule } from '@nestjs/throttler';
import { DatabaseModule } from './database/database.module';
import { HealthModule } from './health/health.module';
import { AuthModule } from './auth/auth.module';
import { InvitationsModule } from './invitations/invitations.module';
import { DevicesModule } from './devices/devices.module';
import { ConversationsModule } from './conversations/conversations.module';
import { MessagesModule } from './messages/messages.module';
import { RealtimeModule } from './realtime/realtime.module';
import { AttachmentsModule } from './attachments/attachments.module';
import { CallsModule } from './calls/calls.module';
import { NotificationsModule } from './notifications/notifications.module';
import { FriendsModule } from './friends/friends.module';
import { DistributionModule } from './distribution/distribution.module';
import { NetworkModule } from './network/network.module';
import { StoriesModule } from './stories/stories.module';
import { LocationsModule } from './locations/locations.module';
import { AdminModule } from './admin/admin.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: ['../.env', '.env'],
    }),
    // Brute-force protection; applied per-endpoint on auth routes (see AuthController)
    ThrottlerModule.forRoot([{ ttl: 60_000, limit: 60 }]),
    DatabaseModule,
    HealthModule,
    AuthModule,
    InvitationsModule,
    DevicesModule,
    ConversationsModule,
    MessagesModule,
    RealtimeModule,
    AttachmentsModule,
    CallsModule,
    NotificationsModule,
    FriendsModule,
    DistributionModule,
    NetworkModule,
    StoriesModule,
    LocationsModule,
    AdminModule,
  ],
})
export class AppModule {}


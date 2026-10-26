import { Module } from '@nestjs/common';
import { DatabaseModule } from '../database/database.module';
import { RealtimeModule } from '../realtime/realtime.module';
import { LocationsController } from './locations.controller';
import { LocationRevocationController } from './location-revocation.controller';
import { LocationsService } from './locations.service';

@Module({
  imports: [DatabaseModule, RealtimeModule],
  controllers: [LocationsController, LocationRevocationController],
  providers: [LocationsService],
})
export class LocationsModule {}

import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { MeasurementsController } from './measurements.controller';
import { MeasurementsService } from './measurements.service';
import { MeasurementEntity } from './entities/measurement.entity';
import { ProfileEntity } from '../profile/entities/profile.entity';

@Module({
  imports: [TypeOrmModule.forFeature([MeasurementEntity, ProfileEntity])],
  controllers: [MeasurementsController],
  providers: [MeasurementsService],
  exports: [MeasurementsService],
})
export class MeasurementsModule {}

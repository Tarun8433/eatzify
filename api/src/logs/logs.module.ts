import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { LogsController } from './logs.controller';
import { LogsService } from './logs.service';
import { FoodLogEntity } from './entities/food-log.entity';
import { FoodEntity } from '../foods/entities/food.entity';
import { MeasurementEntity } from '../measurements/entities/measurement.entity';
import { PlanEntity } from '../plans/entities/plan.entity';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      FoodLogEntity,
      FoodEntity,
      PlanEntity,
      MeasurementEntity,
    ]),
  ],
  controllers: [LogsController],
  providers: [LogsService],
  exports: [LogsService],
})
export class LogsModule {}

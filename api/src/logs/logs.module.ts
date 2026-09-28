import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { LogsController } from './logs.controller';
import { MealPhotoController } from './meal-photo.controller';
import { LogsService } from './logs.service';
import { FoodLogEntity } from './entities/food-log.entity';
import { FoodEntity } from '../foods/entities/food.entity';
import { MeasurementEntity } from '../measurements/entities/measurement.entity';
import { PlanEntity } from '../plans/entities/plan.entity';
import { GymWorkoutEntity } from '../gym/entities/gym-workout.entity';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      FoodLogEntity,
      FoodEntity,
      PlanEntity,
      MeasurementEntity,
      GymWorkoutEntity,
    ]),
  ],
  controllers: [LogsController, MealPhotoController],
  providers: [LogsService],
  exports: [LogsService],
})
export class LogsModule {}

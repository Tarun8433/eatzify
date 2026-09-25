import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { MeasurementEntity } from '../measurements/entities/measurement.entity';
import { ProfileEntity } from '../profile/entities/profile.entity';
import { EnergyReferenceEntity } from './entities/energy-reference.entity';
import { ExerciseEntity } from './entities/exercise.entity';
import { GymProfileEntity } from './entities/gym-profile.entity';
import { GymRoutineEntity } from './entities/gym-routine.entity';
import { GymWorkoutEntity } from './entities/gym-workout.entity';
import { GymController } from './gym.controller';
import { GymLibraryService } from './gym-library.service';
import { GymPlanService } from './gym-plan.service';
import { GymStatsService } from './gym-stats.service';
import { GymWorkoutsService } from './gym-workouts.service';

/// ADR-013. Reads `measurement` and `profile` directly for the body weight an energy estimate is
/// priced at (D-242), the way LogsModule reads other modules' tables.
@Module({
  imports: [
    TypeOrmModule.forFeature([
      ExerciseEntity,
      EnergyReferenceEntity,
      GymProfileEntity,
      GymRoutineEntity,
      GymWorkoutEntity,
      MeasurementEntity,
      ProfileEntity,
    ]),
  ],
  controllers: [GymController],
  providers: [
    GymLibraryService,
    GymWorkoutsService,
    GymPlanService,
    GymStatsService,
  ],
})
export class GymModule {}

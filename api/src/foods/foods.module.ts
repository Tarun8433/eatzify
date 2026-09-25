import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { FoodsController } from './foods.controller';
import { FoodImagesController } from './food-images.controller';
import { FoodsService } from './foods.service';
import { FoodEntity } from './entities/food.entity';
import { HouseholdMeasureEntity } from './entities/household-measure.entity';
import { BillingModule } from '../billing/billing.module';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';
import { FoodScanController } from './scan/food-scan.controller';
import { FoodScanService } from './scan/food-scan.service';
import { ScanPolicyService } from './scan/scan-policy.service';
import { FoodScanEntity } from './scan/food-scan.entity';
import { ScanPolicyEntity } from './scan/scan-policy.entity';
import { FOOD_VISION_PROVIDER } from './scan/food-vision.provider';
import { MealPhotoSweep } from './scan/meal-photo.sweep';
import { MealPhotoScheduler } from './scan/meal-photo.scheduler';
import { LogsModule } from '../logs/logs.module';
import { FoodLogEntity } from '../logs/entities/food-log.entity';
import { visionProviderFromEnv } from './scan/vision-provider-from-env';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      FoodEntity,
      HouseholdMeasureEntity,
      ScanPolicyEntity,
      FoodScanEntity,
      // The FREE scan window counts from signup (D-238).
      UserEntity,
      // The photo sweep clears entry photos past their retention (D-240).
      FoodLogEntity,
    ]),
    // A scan's allowance is the caller's tier.
    BillingModule,
    // A confirmed scan becomes a diary entry (D-240).
    LogsModule,
  ],
  controllers: [FoodsController, FoodImagesController, FoodScanController],
  providers: [
    FoodsService,
    ScanPolicyService,
    FoodScanService,
    MealPhotoSweep,
    MealPhotoScheduler,
    {
      // docs/04 §11: the vendor is chosen by config. `none`, or no key, turns scanning off with a
      // 503 the app explains — rather than a boot that fails for a feature someone did not set up.
      provide: FOOD_VISION_PROVIDER,
      useFactory: visionProviderFromEnv,
    },
  ],
  exports: [FoodsService, ScanPolicyService],
})
export class FoodsModule {}

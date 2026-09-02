import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { PlansController } from './plans.controller';
import { PlansService } from './plans.service';
import { PlanOptionsService } from './plan-options.service';
import { PlanEntity } from './entities/plan.entity';
import { FoodEntity } from '../foods/entities/food.entity';
import { ProfileEntity } from '../profile/entities/profile.entity';
import { HealthProfileEntity } from '../profile/entities/health-profile.entity';
import { EngineService } from '../modules/engine';
import { BillingModule } from '../billing/billing.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      PlanEntity,
      ProfileEntity,
      HealthProfileEntity,
      FoodEntity,
    ]),
    BillingModule,
  ],
  controllers: [PlansController],
  providers: [
    PlansService,
    PlanOptionsService,
    {
      // The engine is framework-free by design (docs/06 §2), so it is constructed here rather than
      // decorated. It validates every rule pack at boot — a bad pack fails startup, not a request.
      provide: EngineService,
      useFactory: () =>
        new EngineService(
          process.env.RULE_PACK_DIR ?? 'config/rule-packs',
          process.env.RULE_PACK_VERSION ?? '1.0.0',
        ),
    },
  ],
  exports: [PlansService],
})
export class PlansModule {}

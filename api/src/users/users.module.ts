import {
  // common
  Module,
} from '@nestjs/common';

import { UsersController } from './users.controller';

import { UsersService } from './users.service';
import { RelationalUserPersistenceModule } from './infrastructure/persistence/relational/relational-persistence.module';
import { FilesModule } from '../files/files.module';
import { TypeOrmModule } from '@nestjs/typeorm';
import { UserAccessService } from './user-access.service';
import { UserBlockEntity } from './infrastructure/persistence/relational/entities/user-block.entity';
import { UserActivityDayEntity } from './infrastructure/persistence/relational/entities/user-activity-day.entity';
import { UserEntity } from './infrastructure/persistence/relational/entities/user.entity';

// docs/20 §2 + ADR-003: Postgres only. The boilerplate's document/Mongoose branch was removed.
const infrastructurePersistenceModule = RelationalUserPersistenceModule;

@Module({
  imports: [
    // import modules, etc.
    infrastructurePersistenceModule,
    FilesModule,
    TypeOrmModule.forFeature([
      UserBlockEntity,
      UserEntity,
      UserActivityDayEntity,
    ]),
  ],
  controllers: [UsersController],
  providers: [UsersService, UserAccessService],
  exports: [UsersService, UserAccessService, infrastructurePersistenceModule],
})
export class UsersModule {}

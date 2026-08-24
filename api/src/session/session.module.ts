import {
  // common
  Module,
} from '@nestjs/common';

import { RelationalSessionPersistenceModule } from './infrastructure/persistence/relational/relational-persistence.module';
import { SessionService } from './session.service';

// docs/20 §2 + ADR-003: Postgres only. The boilerplate's document/Mongoose branch was removed.
const infrastructurePersistenceModule = RelationalSessionPersistenceModule;

@Module({
  imports: [infrastructurePersistenceModule],
  providers: [SessionService],
  exports: [SessionService, infrastructurePersistenceModule],
})
export class SessionModule {}

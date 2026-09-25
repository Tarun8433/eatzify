import {
  BadRequestException,
  Injectable,
  Logger,
  type OnModuleInit,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { RulePackActivationEntity } from './entities/rule-pack-activation.entity';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';
import { EngineService } from '../modules/engine';
import { RoleEnum } from '../roles/roles.enum';

export type RulePackState = {
  active: string;
  available: readonly string[];
  history: {
    version: string;
    activated_by_user_id: number;
    reviewed_by_user_id: number;
    note: string | null;
    created_at: string;
  }[];
};

export type ActivationRequest = {
  version: string;
  actorUserId: number;
  reviewedByUserId: number;
  note?: string | null;
};

/// The most history a read returns. This table gains a row a few times a year.
const MAX_HISTORY = 50;

/**
 * docs/09 §9: `POST /admin/rule-packs/activate { version }`, super_admin only, requires
 * `reviewed_by`.
 *
 * What activation is NOT: a way to change a number. api rule 1 keeps every constant in a versioned
 * YAML file, and this service only chooses which of the files already on disk is the live one — a
 * pack that is not on disk at boot cannot be activated, because the engine validated the ones it
 * has and cannot vouch for a file it has never read.
 */
@Injectable()
export class RulePacksService implements OnModuleInit {
  private readonly log = new Logger(RulePacksService.name);

  constructor(
    @InjectRepository(RulePackActivationEntity)
    private readonly activations: Repository<RulePackActivationEntity>,
    @InjectRepository(UserEntity)
    private readonly users: Repository<UserEntity>,
    private readonly engine: EngineService,
  ) {}

  /**
   * The database has the last word on start-up, not `RULE_PACK_VERSION`.
   *
   * Without this, a restart would silently roll back to whatever the environment says, and the
   * activation that two people signed off would quietly stop being true.
   */
  async onModuleInit(): Promise<void> {
    const latest = await this.latest();
    if (!latest || latest.version === this.engine.version) return;

    try {
      this.engine.activate(latest.version);
    } catch {
      // The pack is not on this machine. Serving the env's version is the safe answer; failing to
      // start would take the API down over a file that has not been deployed yet.
      this.log.warn(
        `activated rule pack ${latest.version} is not on disk; serving ${this.engine.version}`,
      );
    }
  }

  async state(): Promise<RulePackState> {
    const history = await this.activations.find({
      order: { createdAt: 'DESC' },
      take: MAX_HISTORY,
    });

    return {
      active: this.engine.version,
      available: this.engine.availableVersions,
      history: history.map((row) => ({
        version: row.version,
        activated_by_user_id: row.activatedByUserId,
        reviewed_by_user_id: row.reviewedByUserId,
        note: row.note,
        created_at: row.createdAt.toISOString(),
      })),
    };
  }

  async activate(input: ActivationRequest): Promise<RulePackState> {
    if (!this.engine.availableVersions.includes(input.version)) {
      throw new BadRequestException({
        error: {
          code: 'RULE_PACK_UNKNOWN',
          user_message: `No rule pack ${input.version} on this server. Deploy the file first.`,
        },
      });
    }

    // Two people. The database has the same rule as a CHECK, because "one person cannot do this
    // alone" is not a thing to leave to whichever service happens to write the row.
    if (input.reviewedByUserId === input.actorUserId) {
      throw new BadRequestException({
        error: {
          code: 'REVIEWER_REQUIRED',
          user_message:
            'Somebody other than you has to have reviewed this pack. Name them.',
        },
      });
    }

    const reviewer = await this.users.findOne({
      where: { id: input.reviewedByUserId },
    });
    const reviewerRole = Number(reviewer?.role?.id ?? 0);
    if (
      !reviewer ||
      ![RoleEnum.admin, RoleEnum.super_admin].includes(reviewerRole)
    ) {
      throw new BadRequestException({
        error: {
          code: 'REVIEWER_NOT_ALLOWED',
          user_message: 'The reviewer has to be an admin on this system.',
        },
      });
    }

    await this.activations.save(
      this.activations.create({
        version: input.version,
        activatedByUserId: input.actorUserId,
        reviewedByUserId: input.reviewedByUserId,
        note: input.note ?? null,
      }),
    );

    this.engine.activate(input.version);
    return this.state();
  }

  private async latest(): Promise<RulePackActivationEntity | null> {
    const [row] = await this.activations.find({
      order: { createdAt: 'DESC' },
      take: 1,
    });
    return row ?? null;
  }
}

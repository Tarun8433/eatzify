import {
  generatePlan,
  type EngineFood,
  type EngineInput,
  type EngineOutput,
  type RulePack,
} from '@eatzify/diet-engine';
import { RulePackError, loadAllRulePacks } from './rule-pack.loader';

/**
 * The thin I/O shell around the pure engine. docs/06 §2: the `engine` module owns computation plus
 * the rule-pack loader, and may not touch the DB or HTTP. Persistence belongs to `plans`.
 *
 * Framework-free on purpose — the boilerplate fork (docs/20 §2) supplies the NestJS module and
 * provider wiring, and this class drops into it unchanged.
 */
export class EngineService {
  private readonly packs: ReadonlyMap<string, RulePack>;
  private activeVersion: string;

  public constructor(packDir: string, activeVersion: string) {
    this.packs = loadAllRulePacks(packDir);
    if (!this.packs.has(activeVersion)) {
      throw new RulePackError(
        `RULE_PACK_VERSION="${activeVersion}" not found; available: ${[...this.packs.keys()].join(', ')}`,
      );
    }
    this.activeVersion = activeVersion;
  }

  public get version(): string {
    return this.activeVersion;
  }

  public get availableVersions(): readonly string[] {
    return [...this.packs.keys()];
  }

  /**
   * Switches which loaded pack new plans are generated against (docs/09 §9's rule-pack activation).
   *
   * Only a pack that was on disk at boot: every pack is validated once at start-up, and a version
   * this process has never read is one nothing has checked. Plans already issued keep the version
   * they were generated with — that is why `plan.packVersion` is stored.
   */
  public activate(version: string): void {
    if (!this.packs.has(version)) {
      throw new RulePackError(
        `rule pack "${version}" is not loaded; available: ${[...this.packs.keys()].join(', ')}`,
      );
    }
    this.activeVersion = version;
  }

  /**
   * Generates against the active pack. Callers persist `packVersion` with the plan (docs/04 §1).
   *
   * `foods` is the candidate pool, read from the database by `plans` and passed IN — this module
   * may not touch the DB (docs/06 §2) and the engine may not either (rule 2). Omitted, the plan
   * comes back with targets and no meals, which is what shipped before steps 11 and 13 existed.
   */
  public generate(
    input: EngineInput,
    foods: readonly EngineFood[] = [],
  ): EngineOutput {
    return generatePlan(input, this.pack(this.activeVersion), foods);
  }

  /**
   * Regenerates against a specific pack version, so a plan issued months ago can be reproduced
   * byte-for-byte for a coach or an audit (docs/16 GV-09).
   */
  public generateWithPack(
    input: EngineInput,
    version: string,
    foods: readonly EngineFood[] = [],
  ): EngineOutput {
    return generatePlan(input, this.pack(version), foods);
  }

  private pack(version: string): RulePack {
    const pack = this.packs.get(version);
    if (pack === undefined)
      throw new RulePackError(`unknown rule pack version: ${version}`);
    return pack;
  }
}

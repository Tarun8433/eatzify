import { generatePlan, type EngineInput, type EngineOutput, type RulePack } from '@eatzify/diet-engine';
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
  private readonly activeVersion: string;

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

  /** Generates against the active pack. Callers persist `packVersion` with the plan (docs/04 §1). */
  public generate(input: EngineInput): EngineOutput {
    return generatePlan(input, this.pack(this.activeVersion));
  }

  /**
   * Regenerates against a specific pack version, so a plan issued months ago can be reproduced
   * byte-for-byte for a coach or an audit (docs/16 GV-09).
   */
  public generateWithPack(input: EngineInput, version: string): EngineOutput {
    return generatePlan(input, this.pack(version));
  }

  private pack(version: string): RulePack {
    const pack = this.packs.get(version);
    if (pack === undefined) throw new RulePackError(`unknown rule pack version: ${version}`);
    return pack;
  }
}

import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { load } from 'js-yaml';
import type { RulePack } from '@eatzify/diet-engine';
import { rulePackSchema } from './rule-pack.schema';

/**
 * Reads and validates rule packs from disk. docs/04: constants live in a versioned pack loaded at
 * boot, never in code. A pack that fails validation stops startup — serving a plan from a malformed
 * pack is the failure mode docs/05 §1 is written to prevent.
 */

export class RulePackError extends Error {
  public constructor(message: string) {
    super(message);
    this.name = 'RulePackError';
  }
}

const PACK_FILE = /^v(\d+\.\d+\.\d+)\.yaml$/;

export function listPackVersions(dir: string): readonly string[] {
  return readdirSync(dir)
    .map((f) => PACK_FILE.exec(f)?.[1])
    .filter((v): v is string => v !== undefined)
    .sort();
}

export function loadRulePack(dir: string, version: string): RulePack {
  const file = join(dir, `v${version}.yaml`);

  let parsed: unknown;
  try {
    parsed = load(readFileSync(file, 'utf8'));
  } catch (cause) {
    throw new RulePackError(`cannot read rule pack ${file}: ${(cause as Error).message}`);
  }

  const result = rulePackSchema.safeParse(parsed);
  if (!result.success) {
    const detail = result.error.issues
      .map((i) => `${i.path.join('.') || '(root)'}: ${i.message}`)
      .join('; ');
    throw new RulePackError(`rule pack ${file} is invalid — ${detail}`);
  }

  // The filename is part of the contract: v1.0.0.yaml must not declare version 1.0.1.
  if (result.data.version !== version) {
    throw new RulePackError(
      `rule pack ${file} declares version "${result.data.version}" but is named v${version}`,
    );
  }

  return result.data as unknown as RulePack;
}

/**
 * Loads every pack once, at boot. Packs are immutable (docs/03 §1), so caching them for the process
 * lifetime is correct — and it means a plan re-read months later resolves the same constants.
 */
export function loadAllRulePacks(dir: string): ReadonlyMap<string, RulePack> {
  const versions = listPackVersions(dir);
  if (versions.length === 0) throw new RulePackError(`no rule packs found in ${dir}`);
  return new Map(versions.map((v) => [v, loadRulePack(dir, v)]));
}

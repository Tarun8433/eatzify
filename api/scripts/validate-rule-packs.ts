/**
 * Boot-equivalent check, runnable in CI: every pack in config/rule-packs must parse and satisfy the
 * schema. Wire this into the pipeline so a bad clinical constant fails the build, not a user's plan.
 */
import { join } from 'node:path';
import { listPackVersions, loadRulePack } from '../src/modules/engine';

const dir = join(__dirname, '..', 'config', 'rule-packs');
const versions = listPackVersions(dir);

if (versions.length === 0) {
  process.stderr.write(`no rule packs found in ${dir}\n`);
  process.exit(1);
}

let failed = 0;
for (const version of versions) {
  try {
    const pack = loadRulePack(dir, version);
    process.stdout.write(`ok    v${version} (${Object.keys(pack.meals.patterns).length} meal patterns)\n`);
  } catch (error) {
    failed += 1;
    process.stderr.write(`FAIL  v${version}: ${(error as Error).message}\n`);
  }
}
process.exit(failed === 0 ? 0 : 1);

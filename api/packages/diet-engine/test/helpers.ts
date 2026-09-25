import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { load } from 'js-yaml';
import type { PackWithOverrides } from '../src/overrides';
import type { EngineInput } from '../src/types';
import type { EngineFood } from '../src/foods';

/** Tests may touch the filesystem. The engine may not. */
export function loadPack(version = 'v1.0.0'): PackWithOverrides {
  const path = join(__dirname, '..', '..', '..', 'config', 'rule-packs', `${version}.yaml`);
  return load(readFileSync(path, 'utf8')) as PackWithOverrides;
}

export function input(overrides: Partial<EngineInput>): EngineInput {
  return {
    userId: 'u-test-0001',
    planDate: '2026-08-24',
    ageYears: 30,
    sexAtBirth: 'male',
    heightCm: 175,
    weightKg: 80,
    goal: 'maintenance',
    activityLevel: 'moderate',
    conditions: ['none'],
    foodPreference: 'veg',
    foodAllergies: [],
    budgetTier: 'medium',
    lifestyle: 'flexible',
    mealCount: '4',
    ...overrides,
  };
}

/**
 * The real 281 foods, as the engine sees them (`docs/templates/foods-seed.csv`).
 *
 * D-165 and D-167 were both found by running against this file by hand, and every bug they name
 * was invisible to the hand-built fixtures above: the fill only misbehaves when the pool is big
 * enough to contain a better-scoring wrong answer.
 */
export function seedFoods(): EngineFood[] {
  const path = join(
    __dirname,
    '..',
    '..',
    '..',
    '..',
    'docs',
    'templates',
    'foods-seed.csv',
  );
  const [header, ...lines] = readFileSync(path, 'utf8').trim().split('\n');
  const columns = splitCsv(header ?? '');

  return lines.map((line, index) => {
    const cells = splitCsv(line);
    const at = (name: string): string => cells[columns.indexOf(name)] ?? '';
    const list = (name: string): string[] =>
      at(name)
        .split('|')
        .map((s) => s.trim())
        .filter(Boolean);

    return {
      id: `f${index + 1}`,
      name: at('name'),
      kcal: Number(at('kcal')),
      proteinG: Number(at('proteinG')),
      fatG: Number(at('fatG')),
      carbG: Number(at('carbG')),
      fibreG: Number(at('fibreG')),
      sodiumMg: Number(at('sodiumMg')),
      addedSugarG: Number(at('addedSugarG')),
      saturatedFatG: Number(at('saturatedFatG')),
      tags: list('tags'),
      suitableFor: list('suitableFor'),
      allergens: list('allergens'),
      costTier: at('costTier'),
      // `katori=150*` — the star marks the serving the plan quotes, which is the first one here.
      measures: list('measures')
        .map((m) => {
          const [label, grams] = m.replace('*', '').split('=');
          return { label: label ?? '', grams: Number(grams) };
        })
        .filter((m) => m.label !== '' && Number.isFinite(m.grams)),
    };
  });
}

/// Enough CSV for this one file: quoted cells exist (a name with a comma in it), escapes do not.
function splitCsv(line: string): string[] {
  const cells: string[] = [];
  let cell = '';
  let quoted = false;

  for (const char of line) {
    if (char === '"') quoted = !quoted;
    // The file is CRLF; without this the last column's name is `measures\r` and every food comes
    // back with no serving, which the fill reads as "cannot be eaten".
    else if (char === '\r') continue;
    else if (char === ',' && !quoted) {
      cells.push(cell);
      cell = '';
    } else cell += char;
  }
  cells.push(cell);

  return cells;
}

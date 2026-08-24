import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { load } from 'js-yaml';
import type { PackWithOverrides } from '../src/overrides';
import type { EngineInput } from '../src/types';

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

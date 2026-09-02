import type { EngineInput } from './types';

/** Pipeline step 1. docs/03 §2 ranges. The API DTO validates too — this is the engine's own guard. */

export class EngineInputError extends Error {
  public constructor(message: string) {
    super(message);
    this.name = 'EngineInputError';
  }
}

const RANGES = {
  ageYears: [18, 99],
  heightCm: [120, 220],
  weightKg: [30, 250],
} as const;

export function validateInput(input: EngineInput): void {
  for (const [field, [min, max]] of Object.entries(RANGES)) {
    const value = input[field as keyof typeof RANGES];
    if (!Number.isFinite(value) || value < min || value > max) {
      throw new EngineInputError(
        `${field} out of range: ${value} (expected ${min}..${max})`,
      );
    }
  }
  if (input.conditions.length === 0) {
    throw new EngineInputError('conditions must contain at least "none"');
  }
  // docs/03 §2: `none` is exclusive. Selecting it clears the rest.
  if (input.conditions.includes('none') && input.conditions.length > 1) {
    throw new EngineInputError(
      'condition "none" is exclusive and cannot appear with others',
    );
  }
  if (input.planDate.match(/^\d{4}-\d{2}-\d{2}$/) === null) {
    throw new EngineInputError(
      `planDate must be YYYY-MM-DD, got "${input.planDate}"`,
    );
  }
}

import { join } from 'path';
import { type MeasurementEntity } from '../src/measurements/entities/measurement.entity';
import {
  isWithinBounds,
  MEASUREMENT_KINDS,
  unitFor,
} from '../src/measurements/measurement-rules';
import { LogsService } from '../src/logs/logs.service';
import {
  EngineService,
  loadRulePack,
  rulePackSchema,
} from '../src/modules/engine';

/// What the Home dashboard reads off the day: last night's sleep from the phone, and the day's
/// steps goal from the active rule pack (never a number the app makes up).

type Row = Pick<MeasurementEntity, 'kind' | 'diaryDate' | 'value' | 'source'>;

const row = (kind: string, value: number, source = 'health_connect'): Row => ({
  kind,
  diaryDate: '2026-10-12',
  value: value.toFixed(2),
  source,
});

const PACK_DIR = join(__dirname, '..', 'config', 'rule-packs');

const dayWith = (activity: Row[], engine?: { stepsGoal(): number | null }) =>
  new LogsService(
    { find: () => Promise.resolve([]) } as never,
    {} as never,
    { findOne: () => Promise.resolve(null) } as never,
    { find: () => Promise.resolve(activity) } as never,
    undefined,
    engine as never,
  ).day(1, '2026-10-12');

describe('sleep is a kind', () => {
  it('should be in the closed list, in minutes', () => {
    expect(MEASUREMENT_KINDS).toContain('sleep_min');
    expect(unitFor('sleep_min')).toBe('min');
  });

  it('should accept a real night and refuse more than a day', () => {
    expect(isWithinBounds('sleep_min', 450)).toBe(true);
    expect(isWithinBounds('sleep_min', 0)).toBe(true);
    expect(isWithinBounds('sleep_min', 1441)).toBe(false);
  });
});

describe('the day carries sleep', () => {
  it('should send last night’s minutes and where they came from', async () => {
    const day = await dayWith([row('sleep_min', 450)]);

    expect(day.activity.sleep_min).toBe(450);
    expect(day.activity.sleep_source).toBe('health_connect');
  });

  it('should send null, not zero, when nothing was recorded', async () => {
    const day = await dayWith([]);

    expect(day.activity.sleep_min).toBeNull();
    expect(day.activity.sleep_source).toBeNull();
  });
});

describe('the day carries a steps goal', () => {
  it('should send the active pack’s goal', async () => {
    const day = await dayWith([], { stepsGoal: () => 8000 });

    expect(day.activity.steps_goal).toBe(8000);
  });

  it('should send null when the pack sets none', async () => {
    const day = await dayWith([], { stepsGoal: () => null });

    expect(day.activity.steps_goal).toBeNull();
  });

  it('should send null when no engine is wired', async () => {
    const day = await dayWith([]);

    expect(day.activity.steps_goal).toBeNull();
  });
});

describe('the rule pack’s steps goal', () => {
  const base = JSON.parse(
    JSON.stringify(loadRulePack(PACK_DIR, '1.0.0')),
  ) as Record<string, unknown>;

  it('should be optional, so the shipped pack still loads', () => {
    expect(rulePackSchema.safeParse(base).success).toBe(true);
  });

  it('should accept a whole positive goal and keep it', () => {
    const result = rulePackSchema.safeParse({
      ...base,
      activity: { steps_goal: 8000 },
    });

    expect(result.success).toBe(true);
    expect(result.success && result.data.activity?.steps_goal).toBe(8000);
  });

  it('should refuse a goal of zero or a fraction', () => {
    for (const goal of [0, -1, 7999.5]) {
      expect(
        rulePackSchema.safeParse({ ...base, activity: { steps_goal: goal } })
          .success,
      ).toBe(false);
    }
  });

  it('should be null on the engine while the active pack has none', () => {
    expect(new EngineService(PACK_DIR, '1.0.0').stepsGoal()).toBeNull();
  });
});

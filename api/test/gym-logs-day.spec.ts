import { GUARDS_METADATA } from '@nestjs/common/constants';
import { GymController } from '../src/gym/gym.controller';
import { LogsService } from '../src/logs/logs.service';

/// D-242: a day's workout energy reaches Home as its own figure, and every gym route needs a login.
describe('gym on the diary day', () => {
  const dayWith = (workouts: { energyKcal: number | null }[]) =>
    new LogsService(
      { find: () => Promise.resolve([]) } as never,
      {} as never,
      { findOne: () => Promise.resolve(null) } as never,
      { find: () => Promise.resolve([]) } as never,
      { find: () => Promise.resolve(workouts) } as never,
    ).day(7, '2026-09-19');

  it("should sum the day's workouts when each carries an estimate", async () => {
    const day = await dayWith([{ energyKcal: 240 }, { energyKcal: 95 }]);
    expect(day.activity.workout_kcal).toBe(335);
  });

  it('should say not estimated, not zero, when no workout had a body weight', async () => {
    expect(
      (await dayWith([{ energyKcal: null }])).activity.workout_kcal,
    ).toBeNull();
    expect((await dayWith([])).activity.workout_kcal).toBeNull();
  });

  it('should never fold workout energy into device energy', async () => {
    const day = await dayWith([{ energyKcal: 240 }]);
    expect(day.activity.energy_burned_kcal).toBeNull();
  });

  it('should require a signed-in user on every gym route', () => {
    const guards = Reflect.getMetadata(
      GUARDS_METADATA,
      GymController,
    ) as unknown[];
    expect(guards).toHaveLength(1);
  });
});

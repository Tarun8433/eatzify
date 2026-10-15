import { describe, expect, it } from 'vitest';
import { choiceOf, switchSummary } from '../lib/dashboard-switch';

/// D-269: the person page says what someone gets, and whether it is their own setting.
describe('dashboard switch', () => {
  it('should map an override to the three choices', () => {
    expect(choiceOf(null)).toBe('follow');
    expect(choiceOf(true)).toBe('allow');
    expect(choiceOf(false)).toBe('deny');
  });

  it('should say a person follows the app setting, and which one', () => {
    expect(
      switchSummary({ user_id: 1, override: null, audience: 'verified', allowed: false }),
    ).toBe('Cannot switch dashboards — follows the app setting (verified partners only).');
  });

  it('should say when the setting is the person’s own', () => {
    expect(
      switchSummary({ user_id: 1, override: true, audience: 'verified', allowed: true }),
    ).toBe('Can switch dashboards — set for this person.');
  });
});

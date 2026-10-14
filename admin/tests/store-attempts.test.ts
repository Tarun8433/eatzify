import { describe, expect, it } from 'vitest';
import { attemptDetail, OUTCOME_LABEL } from '../lib/store-attempts';

/// D-266: a failed Play attempt reads as plain words, with Play's own code kept for support.
describe('attemptDetail', () => {
  it('should word the reason and keep the store code when Play failed', () => {
    expect(
      attemptDetail({ provider: 'play', reason: 'storeFailed', store_code: 'BillingResponse.developerError' }),
    ).toBe("Play couldn't complete · BillingResponse.developerError");
  });

  it('should name the App Store when the attempt was on iOS', () => {
    expect(attemptDetail({ provider: 'app_store', reason: 'storeBusy', store_code: null })).toBe(
      'App Store busy or offline',
    );
  });

  it('should be empty when there is no reason and no code', () => {
    expect(attemptDetail({ provider: 'play', reason: null, store_code: null })).toBe('');
  });

  it('should show an unknown reason as it came when the app sends a new one', () => {
    expect(attemptDetail({ provider: 'play', reason: 'somethingNew', store_code: null })).toBe('somethingNew');
  });

  it('should say refused by server when the server would not verify', () => {
    expect(OUTCOME_LABEL.refused).toBe('Refused by server');
  });
});

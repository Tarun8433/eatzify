import {
  gateMessage,
  warningsForUser,
  GATE_COPY,
} from '../src/plans/plan-copy';

/// docs/05 §7 says "use verbatim; do not paraphrase" — the wording IS the safety feature. These
/// tests exist to make an edit to that copy a deliberate, visible act rather than a silent one.
describe('plan copy — docs/05 §7', () => {
  it('routes an eating-disorder gate to its own message, never the generic referral', () => {
    const message = gateMessage('eating_disorder');

    // docs/05 §4: this must never be answered with a coach-unlock or a referral written for a
    // different reason.
    expect(message.toLowerCase()).toContain(
      "we're not going to set calorie or weight targets",
    );
    expect(message).not.toBe(GATE_COPY.ckd);
  });

  it('routes an age gate to the under-18 message, not the condition message', () => {
    expect(gateMessage('age_ineligible')).toContain('built for adults');
    expect(gateMessage('age_ineligible')).not.toBe(GATE_COPY.ckd);
  });

  it('routes a clinician-unlockable gate to the coach-unlock message', () => {
    expect(gateMessage('post_surgery_needs_clinician')).toContain(
      'coach can unlock',
    );
    expect(gateMessage('clinician_review_required')).toContain(
      'coach can unlock',
    );
  });

  it('every blocking condition shares the one approved referral string', () => {
    for (const code of ['ckd', 'pregnancy', 'lactation', 'hyperthyroid']) {
      expect(gateMessage(code)).toBe(GATE_COPY.ckd);
    }
  });

  it('falls back to the referral message for an unknown gate rather than leaking a code', () => {
    const message = gateMessage('some_future_gate');

    expect(message).toBe(GATE_COPY.ckd);
    expect(message).not.toContain('some_future_gate');
  });

  it('collapses several clamp warnings into one message', () => {
    const warnings = warningsForUser([
      'deficit_capped_age',
      'target_raised_to_bmr',
      'deficit_capped_absolute',
    ]);

    // Three internal reasons, one thing the user needs to be told.
    expect(warnings).toHaveLength(1);
    expect(warnings[0].code).toBe('safety_clamp_applied');
  });

  it('drops internal-only warnings instead of showing a raw code', () => {
    expect(warningsForUser(['estimate_precision_reduced'])).toEqual([]);
    expect(warningsForUser(['renal_protein_caution'])).toEqual([]);
  });

  it('returns nothing when no clamp was applied', () => {
    expect(warningsForUser([])).toEqual([]);
  });
});

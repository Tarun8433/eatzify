import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/format/rupees.dart';
import 'package:health_pro/domain/entities/onboarding_enums.dart';

void main() {
  group('the food budget slider (D-78)', () {
    test('covers 2k to 18k in 500-rupee steps, landing exactly on both ends', () {
      expect(BudgetRange.minInr, 2000);
      expect(BudgetRange.maxInr, 18000);
      expect((BudgetRange.maxInr - BudgetRange.minInr) % BudgetRange.stepInr, 0);
    });

    test('the default is inside the range', () {
      expect(BudgetRange.defaultInr, greaterThanOrEqualTo(BudgetRange.minInr));
      expect(BudgetRange.defaultInr, lessThanOrEqualTo(BudgetRange.maxInr));
    });

    test('clamps anything outside, so a bad value cannot reach the wire', () {
      expect(BudgetRange.clamp(0), BudgetRange.minInr);
      expect(BudgetRange.clamp(999999), BudgetRange.maxInr);
      expect(BudgetRange.clamp(8000), 8000);
    });
  });

  group('rupees map onto the engine tiers', () {
    test('every point on the slider resolves to a tier', () {
      for (var r = BudgetRange.minInr; r <= BudgetRange.maxInr; r += BudgetRange.stepInr) {
        expect(BudgetTier.values, contains(BudgetTier.forMonthlyInr(r)), reason: '$r');
      }
    });

    test('the boundaries belong to the tier above, not below', () {
      expect(BudgetTier.forMonthlyInr(BudgetRange.mediumFromInr - 1), BudgetTier.low);
      expect(BudgetTier.forMonthlyInr(BudgetRange.mediumFromInr), BudgetTier.medium);
      expect(BudgetTier.forMonthlyInr(BudgetRange.premiumFromInr - 1), BudgetTier.medium);
      expect(BudgetTier.forMonthlyInr(BudgetRange.premiumFromInr), BudgetTier.premium);
    });

    test('the mapping never goes backwards as the budget rises', () {
      var previous = -1;
      for (var r = BudgetRange.minInr; r <= BudgetRange.maxInr; r += BudgetRange.stepInr) {
        final index = BudgetTier.values.indexOf(BudgetTier.forMonthlyInr(r));
        expect(index, greaterThanOrEqualTo(previous), reason: 'a bigger budget cannot buy less');
        previous = index;
      }
    });

    test('both ends of the slider are reachable tiers', () {
      expect(BudgetTier.forMonthlyInr(BudgetRange.minInr), BudgetTier.low);
      expect(BudgetTier.forMonthlyInr(BudgetRange.maxInr), BudgetTier.premium);
    });
  });

  group('rupees are grouped the Indian way (ui-standards.md)', () {
    test('thousands, then every two digits — not the western every three', () {
      expect(Rupees.format(2000), '₹2,000');
      expect(Rupees.format(18000), '₹18,000');
      // The one that gives the western grouping away: ₹1,24,560, never ₹124,560.
      expect(Rupees.format(124560), '₹1,24,560');
    });

    test('no paise on a budget nobody knows to the rupee', () {
      expect(Rupees.format(8000), isNot(contains('.')));
    });
  });
}

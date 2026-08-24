import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/domain/entities/onboarding_enums.dart';
import 'package:health_pro/presentation/features/onboarding/enum_labels.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// docs/15 first audit finding: the old build showed `lose_weight`, `moderate`, `vegetarian`
/// straight on the profile screen. These tests make that a build failure rather than a bug report.
void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    group('locale ${locale.languageCode}', () {
      late AppLocalizations l;

      setUpAll(() async {
        l = await AppLocalizations.delegate.load(locale);
      });

      test('no enum label is ever its raw wire value', () {
        final labels = <String, String>{
          for (final v in SexAtBirth.values) v.wire: v.label(l),
          for (final v in Goal.values) v.wire: v.label(l),
          for (final v in ActivityLevel.values) v.wire: v.label(l),
          for (final v in Condition.values) v.wire: v.label(l),
          for (final v in FoodPreference.values) v.wire: v.label(l),
          for (final v in FoodAllergy.values) v.wire: v.label(l),
          for (final v in BudgetTier.values) v.wire: v.label(l),
          for (final v in Lifestyle.values) v.wire: v.label(l),
          for (final v in MealCount.values) v.wire: v.label(l),
        };

        for (final entry in labels.entries) {
          final wire = entry.key;
          final label = entry.value;
          expect(label, isNotEmpty, reason: '$wire has no label');
          expect(label, isNot(wire), reason: '$wire leaked its wire value to the UI');
          expect(
            label,
            isNot(matches(RegExp(r'^[a-z0-9]+(_[a-z0-9]+)+$'))),
            reason: '$wire produced a snake_case label: "$label"',
          );
        }
      });

      test('every activity tier carries the docs/04 §3 description', () {
        for (final v in ActivityLevel.values) {
          expect(v.description(l), isNotEmpty, reason: v.wire);
          expect(v.description(l), isNot(v.label(l)), reason: v.wire);
        }
      });
    });
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/domain/entities/onboarding_enums.dart';
import 'package:health_pro/domain/entities/profile_view.dart';
import 'package:health_pro/presentation/features/account/edit_profile_controller.dart';

import 'fakes.dart';

const initial = ProfileView(
  ageYears: 32,
  heightCm: 172,
  weightKg: 74.5,
  sexAtBirth: 'female',
  goal: 'fat_loss',
  activity: 'moderate',
  foodPreference: 'veg',
  conditions: ['prediabetes'],
  allergies: ['peanut'],
  healthProfileVersion: 1,
);

EditProfileController controllerWith(FakeProfileRepository repo) =>
    EditProfileController(profiles: repo, initial: initial);

void main() {
  test('sends nothing when nothing changed', () async {
    final repo = FakeProfileRepository();
    final c = controllerWith(repo);

    expect(c.profileChanges(), isEmpty);
    expect(c.healthChanges(), isEmpty);

    // A no-op save is a success, not an error — the user opened the sheet and changed their mind.
    expect(await c.save(health: false), isTrue);
    expect(repo.lastProfilePatch, isNull);
  });

  test('sends only the changed key, never the untouched ones', () async {
    final repo = FakeProfileRepository();
    final c = controllerWith(repo)..goal.value = Goal.maintenance;

    await c.save(health: false);

    // Sending activity/diet here would overwrite the server's values with ones read at page load.
    expect(repo.lastProfilePatch, {'goal': 'maintenance'});
  });

  test('a changed weight is sent, an unchanged one is not', () async {
    final repo = FakeProfileRepository();
    final c = controllerWith(repo)..weightKg.value = 74.5;

    expect(c.profileChanges(), isEmpty);

    c.weightKg.value = 72;
    await c.save(health: false);
    expect(repo.lastProfilePatch, {'weight_kg': 72.0});
  });

  test('conditions and allergies patch independently', () async {
    final repo = FakeProfileRepository();
    final c = controllerWith(repo)..toggleAllergy(FoodAllergy.milk);

    await c.save(health: true);

    expect(repo.lastHealthPatch!.containsKey('allergies'), isTrue);
    expect(repo.lastHealthPatch!.containsKey('conditions'), isFalse);
  });

  test('reordering the same values is not a change', () {
    final c = controllerWith(FakeProfileRepository())
      ..toggleAllergy(FoodAllergy.milk)
      ..toggleAllergy(FoodAllergy.milk);

    expect(c.healthChanges(), isEmpty);
  });

  test('"none" stays exclusive, same as onboarding (docs/03 §2)', () {
    final c = controllerWith(FakeProfileRepository())..toggleCondition(Condition.none);

    expect(c.conditions, {Condition.none});

    c.toggleCondition(Condition.pcos);
    expect(c.conditions.contains(Condition.none), isFalse);
    expect(c.conditions, {Condition.pcos});
  });

  test('a failed save surfaces the server message and reports failure', () async {
    final repo = FakeProfileRepository(
      patchFailure: const ApiFailure('Could not save that.', code: 'X', status: 500),
    );
    final c = controllerWith(repo)..goal.value = Goal.maintenance;

    expect(await c.save(health: false), isFalse);
    expect(c.error.value, 'Could not save that.');
  });
}

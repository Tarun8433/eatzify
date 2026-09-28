/// `GET /profile` (docs/09 §4).
///
/// Enum values arrive as docs/03 §2 wire strings and are rendered through l10n — CLAUDE.md rule 4:
/// never show a user a raw `fat_loss`.
class ProfileView {
  const ProfileView({
    required this.ageYears,
    required this.heightCm,
    required this.weightKg,
    required this.sexAtBirth,
    required this.goal,
    required this.activity,
    required this.foodPreference,
    required this.conditions,
    required this.allergies,
    required this.healthProfileVersion,
    this.photoUrl,
    this.phone,
    this.name,
    this.goalDeclared,
    this.goalWeightKg,
    this.mealCount = '',
    this.lifestyle = '',
    this.budgetTier = '',
    this.wakeTime,
    this.sleepTime,
    this.sleepHours,
    this.breakfastTime,
    this.lunchTime,
    this.midMorningTime,
    this.bedtimeSnackTime,
    this.eveningSnackTime,
    this.dinnerTime,
    this.foodDislikes,
    this.budgetMonthlyInr,
    this.medications,
    this.digestiveSymptoms = const [],
    this.injuries = const [],
    this.menstrualRegularity,
    this.pregnantOrBreastfeeding,
    this.heavyBleedingOrPain,
    this.hormonalMedication,
  });

  final int ageYears;
  final int heightCm;
  final double weightKg;
  final String sexAtBirth;
  final String goal;
  final String activity;
  final String foodPreference;
  final List<String> conditions;
  final List<String> allergies;
  final int healthProfileVersion;

  /// Absolute URL, or null when the user has not set one.
  final String? photoUrl;

  /// The number this account signs in with, E.164. Null for an email or social signup, where the
  /// column was never filled — shown as absent rather than as an empty row.
  final String? phone;

  // Everything else `GET /profile` returns. These were dropped on the floor by the parser until
  // D-72: the server had them, the account screen could not show them, and the edit sheets could
  // not offer them — which is why "change the number of meals in your profile" was a dead end.
  final String? name;
  final String? goalDeclared;
  final double? goalWeightKg;
  final String mealCount;
  final String lifestyle;
  final String budgetTier;

  /// "HH:MM", 24-hour. Rendered through `TimeOfDayText` — never shown raw.
  final String? wakeTime;
  final String? sleepTime;
  final double? sleepHours;
  final String? breakfastTime;
  final String? lunchTime;

  /// docs/04 §7's five-to-six pattern only (D-171). Null for the three and four-meal patterns,
  /// which have no such occasion.
  final String? midMorningTime;
  final String? bedtimeSnackTime;

  final String? eveningSnackTime;
  final String? dinnerTime;
  final String? foodDislikes;

  /// Rupees a month (D-78). Null for anyone onboarded before the slider existed.
  final int? budgetMonthlyInr;

  final String? medications;
  final List<String> digestiveSymptoms;
  final List<String> injuries;
  final String? menstrualRegularity;
  final bool? pregnantOrBreastfeeding;
  final bool? heavyBleedingOrPain;
  final bool? hormonalMedication;

  static ProfileView? fromJson(Map<String, dynamic> json) {
    final p = json['profile'] as Map<String, dynamic>?;
    final h = json['health_profile'] as Map<String, dynamic>?;
    // No profile row means onboarding never completed — an Empty state, not a broken Ready one.
    if (p == null) return null;

    return ProfileView(
      ageYears: (p['age_years'] as num?)?.toInt() ?? 0,
      heightCm: (p['height_cm'] as num?)?.toInt() ?? 0,
      weightKg: (p['weight_kg'] as num?)?.toDouble() ?? 0,
      sexAtBirth: p['sex_at_birth']?.toString() ?? '',
      goal: p['goal']?.toString() ?? '',
      activity: p['activity']?.toString() ?? '',
      foodPreference: p['food_preference']?.toString() ?? '',
      conditions: (h?['conditions'] as List?)?.map((c) => c.toString()).toList() ?? const [],
      allergies: (h?['allergies'] as List?)?.map((a) => a.toString()).toList() ?? const [],
      healthProfileVersion: (h?['version'] as num?)?.toInt() ?? 0,
      photoUrl: json['photo_url']?.toString(),
      phone: json['phone']?.toString(),
      name: p['name']?.toString(),
      goalDeclared: p['goal_declared']?.toString(),
      goalWeightKg: (p['goal_weight_kg'] as num?)?.toDouble(),
      mealCount: p['meal_count']?.toString() ?? '',
      lifestyle: p['lifestyle']?.toString() ?? '',
      budgetTier: p['budget_tier']?.toString() ?? '',
      wakeTime: p['wake_time']?.toString(),
      sleepTime: p['sleep_time']?.toString(),
      sleepHours: (p['sleep_hours'] as num?)?.toDouble(),
      breakfastTime: p['breakfast_time']?.toString(),
      lunchTime: p['lunch_time']?.toString(),
      midMorningTime: p['mid_morning_time']?.toString(),
      bedtimeSnackTime: p['bedtime_snack_time']?.toString(),
      eveningSnackTime: p['evening_snack_time']?.toString(),
      dinnerTime: p['dinner_time']?.toString(),
      foodDislikes: p['food_dislikes']?.toString(),
      budgetMonthlyInr: (p['budget_monthly_inr'] as num?)?.toInt(),
      medications: h?['medications']?.toString(),
      digestiveSymptoms:
          (h?['digestive_symptoms'] as List?)?.map((d) => d.toString()).toList() ?? const [],
      injuries: (h?['injuries'] as List?)?.map((i) => i.toString()).toList() ?? const [],
      menstrualRegularity: h?['menstrual_regularity']?.toString(),
      pregnantOrBreastfeeding: h?['pregnant_or_breastfeeding'] as bool?,
      heavyBleedingOrPain: h?['heavy_bleeding_or_pain'] as bool?,
      hormonalMedication: h?['hormonal_medication'] as bool?,
    );
  }

  /// docs/13: conditions and allergies are health data and never reach a log line.
  @override
  String toString() => 'ProfileView(v$healthProfileVersion, redacted)';
}

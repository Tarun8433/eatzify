/// What the app reads from the phone's health store (D-214).
///
/// `docs/HEALTH-SYNC-TRACKER.md` lists these three and, more usefully, everything deliberately left
/// out and why. The wire strings live here and nowhere else: one enum drives the permission request,
/// the read, and the measurement the server stores.
enum HealthMetric {
  steps(kind: 'steps', unit: 'steps'),

  /// ACTIVE energy only. Total and basal both include resting metabolism, which the plan's TDEE
  /// already counts — storing either would add a BMR to every day twice.
  activeEnergy(kind: 'energy_burned_kcal', unit: 'kcal'),

  distance(kind: 'distance_m', unit: 'm');

  const HealthMetric({required this.kind, required this.unit});

  /// The server's measurement kind.
  final String kind;

  /// The only unit the server accepts for [kind].
  final String unit;
}

/// Whether the app may read, as far as it can tell.
enum HealthPermission {
  granted,

  /// Never asked, or refused. Manual entry still works, so this is a normal state, not an error.
  denied,

  /// iOS, after the user tapped Connect. HealthKit will not say whether READ access was granted —
  /// the answer would itself reveal whether the user has the data — so the only honest move is to
  /// read and see. Treating this as [denied] would switch sync off on every iPhone.
  unknown;

  bool get mayRead => this != denied;
}

/// One diary day's span, exactly as the SERVER defined it (rule 8).
///
/// The phone never works out where a day begins. It is handed these and asks the health store
/// about each one; [contains] is a test against an interval it was given, not a boundary it drew.
class DiaryWindow {
  const DiaryWindow({required this.diaryDate, required this.start, required this.end});

  factory DiaryWindow.fromJson(Map<String, dynamic> json) => DiaryWindow(
    diaryDate: json['diary_date']?.toString() ?? '',
    start: DateTime.parse(json['start'].toString()),
    end: DateTime.parse(json['end'].toString()),
  );

  final String diaryDate;

  /// Inclusive.
  final DateTime start;

  /// Exclusive — it is the next day's [start].
  final DateTime end;

  bool contains(DateTime instant) => !instant.isBefore(start) && instant.isBefore(end);
}

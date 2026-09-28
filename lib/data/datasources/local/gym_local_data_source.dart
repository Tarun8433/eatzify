import 'package:health_pro/core/storage/hive_boxes.dart';
import 'package:health_pro/core/storage/secure_store.dart';

/// The Gym section's phone-side store: JSON strings by key. An interface so tests run on a map.
abstract class GymLocalDataSource {
  static const overviewKey = 'overview';
  static const exercisesKey = 'exercises';
  static const activeKey = 'active';
  static const pendingKey = 'pending';

  Future<String?> read(String key);

  /// Null deletes.
  Future<void> write(String key, String? value);

  Future<void> clear();
}

/// Backed by the encrypted Hive box in [HiveBoxes.gym].
class HiveGymLocalDataSource implements GymLocalDataSource {
  HiveGymLocalDataSource(this._store);

  final SecureStore _store;

  @override
  Future<String?> read(String key) async {
    try {
      return (await HiveBoxes.openGym(_store)).get(key);
    } on Object {
      // An unreadable box is an empty cache, never a crash: the server still has everything saved.
      return null;
    }
  }

  @override
  Future<void> write(String key, String? value) async {
    final box = await HiveBoxes.openGym(_store);
    if (value == null) {
      await box.delete(key);
    } else {
      await box.put(key, value);
    }
  }

  @override
  Future<void> clear() => HiveBoxes.deleteGym();
}

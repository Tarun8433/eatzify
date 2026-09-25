import 'dart:convert';

import 'package:health_pro/core/storage/secure_store.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:path_provider/path_provider.dart';

/// Every Hive box the app opens (CLAUDE.md rule 11). Boxes hold JSON strings — no adapters, so the
/// on-disk shape is whatever the entity's own `toJson` says and nothing generated can drift.
abstract final class HiveBoxes {
  /// The Gym section's phone-side state (ADR-013): the workout in progress, workouts waiting to be
  /// saved, and the last overview and exercise list so a session can start with no signal.
  /// AES-encrypted with a key held in the secure store.
  static const gym = 'gym';

  static Future<void>? _init;

  static Future<void> _ensureInit() =>
      _init ??= getApplicationSupportDirectory().then((dir) => Hive.init(dir.path));

  static Future<Box<String>> openGym(SecureStore store) async {
    await _ensureInit();
    if (Hive.isBoxOpen(gym)) return Hive.box<String>(gym);
    var key = await store.readGymBoxKey();
    if (key == null) {
      key = base64Encode(Hive.generateSecureKey());
      await store.writeGymBoxKey(key);
    }
    return Hive.openBox<String>(gym, encryptionCipher: HiveAesCipher(base64Decode(key)));
  }

  /// At sign-out: the box goes with the account it belonged to.
  static Future<void> deleteGym() async {
    await _ensureInit();
    if (Hive.isBoxOpen(gym)) await Hive.box<String>(gym).close();
    await Hive.deleteBoxFromDisk(gym);
  }
}

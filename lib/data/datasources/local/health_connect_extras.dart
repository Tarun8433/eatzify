import 'package:flutter/services.dart';

/// One diary window's walking extras, as Health Connect aggregated them. Null is "not recorded".
typedef WalkingExtras = ({double? speedMPerS, double? elevationM, double? floors});

/// What `package:health` 13.3.1 cannot total per day on Android: walking speed, elevation gained
/// and floors climbed (D-268). Read through Health Connect's own aggregate — de-duplicated across a
/// phone and a watch, like the plugin's steps — by `MainActivity.kt`. Read only.
class HealthConnectExtras {
  const HealthConnectExtras({MethodChannel channel = const MethodChannel('eatzify/health_extras')})
    : _channel = channel;

  final MethodChannel _channel;

  /// Whether any of the three may be read. Never prompts.
  Future<bool> hasPermission() async => await _channel.invokeMethod<bool>('hasPermission') ?? false;

  /// Shows Health Connect's sheet for the three. True when any was granted.
  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestPermission') ?? false;

  /// One answer per window, in order. Throws when Health Connect would not answer.
  Future<List<WalkingExtras>> read(List<({DateTime start, DateTime end})> windows) async {
    final answer = await _channel.invokeListMethod<Map<Object?, Object?>>('read', {
      'windows': [
        for (final w in windows) [w.start.millisecondsSinceEpoch, w.end.millisecondsSinceEpoch],
      ],
    });
    return [
      for (final day in answer ?? const <Map<Object?, Object?>>[])
        (
          speedMPerS: (day['speed_m_s'] as num?)?.toDouble(),
          elevationM: (day['elevation_m'] as num?)?.toDouble(),
          floors: (day['floors'] as num?)?.toDouble(),
        ),
    ];
  }
}

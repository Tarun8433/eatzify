import CoreMotion
import Flutter

/// Step counts from CMPedometer, the motion coprocessor's own counter (D-99).
///
/// Chosen over HealthKit deliberately. It answers the one question this app asks — "how many steps
/// between these two instants" — needs only `NSMotionUsageDescription` rather than a HealthKit
/// entitlement, and skips the health-app scrutiny HealthKit draws in App Review. It also counts
/// whether or not the app is running, because the counting happens in hardware; nothing here runs
/// in the background, and the app declares no background mode.
///
/// The window always arrives from Dart, which got it from the server (rule 8). Nothing in this file
/// knows what a diary day is, and it must stay that way — a second implementation of the 04:00 IST
/// boundary is how a 1 a.m. walk lands on two different days on two different phones.
class StepCounter {
  static let channelName = "app.eatzify/step_counter"

  /// CMPedometer keeps about seven days. Older than that is not an error, it is simply gone —
  /// reported as null so the caller stores nothing rather than a zero.
  private let pedometer = CMPedometer()

  func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: StepCounter.channelName,
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      // Hardware, not permission. An iPad has no step counter and never will, and the UI should
      // not offer to connect something that cannot exist.
      result(CMPedometer.isStepCountingAvailable())

    case "hasPermission":
      result(CMPedometer.authorizationStatus() == .authorized)

    case "requestPermission":
      requestPermission(result: result)

    case "stepsBetween":
      guard let args = call.arguments as? [String: Any],
        let startMs = args["startMs"] as? NSNumber,
        let endMs = args["endMs"] as? NSNumber
      else {
        result(FlutterError(code: "BAD_ARGS", message: "startMs and endMs are required", details: nil))
        return
      }
      stepsBetween(startMs: startMs.doubleValue, endMs: endMs.doubleValue, result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// There is no "ask for motion access" call in Core Motion. The prompt appears on the first
  /// query, so asking IS querying — a one-second window is enough to trigger it and cheap enough
  /// to throw away.
  private func requestPermission(result: @escaping FlutterResult) {
    guard CMPedometer.isStepCountingAvailable() else {
      result(false)
      return
    }

    let now = Date()
    pedometer.queryPedometerData(from: now.addingTimeInterval(-1), to: now) { _, _ in
      // The status, not the query's own outcome: a device that simply has no data for the last
      // second still granted access, and reporting that as a refusal would send the user to
      // Settings to fix something that is not broken.
      DispatchQueue.main.async {
        result(CMPedometer.authorizationStatus() == .authorized)
      }
    }
  }

  private func stepsBetween(startMs: Double, endMs: Double, result: @escaping FlutterResult) {
    guard CMPedometer.isStepCountingAvailable() else {
      result(nil)
      return
    }

    let start = Date(timeIntervalSince1970: startMs / 1000)
    let end = Date(timeIntervalSince1970: endMs / 1000)

    pedometer.queryPedometerData(from: start, to: end) { data, error in
      DispatchQueue.main.async {
        if error != nil {
          // Denied, restricted, or outside the seven days CMPedometer retains. All of them mean
          // "no answer", which is NOT zero steps — Dart stores nothing for a null.
          result(nil)
          return
        }
        result(data?.numberOfSteps.intValue)
      }
    }
  }
}

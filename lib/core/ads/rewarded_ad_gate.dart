import 'dart:async';
import 'dart:io';

import 'package:google_mobile_ads/google_mobile_ads.dart';

/// What happened when the user was shown a rewarded ad.
enum AdOutcome {
  /// Watched to the end — the scan may go ahead.
  earned,

  /// Closed early. Nothing is owed.
  skipped,

  /// No ad could be loaded (offline, no fill). Not the user's fault, and said differently.
  unavailable,
}

/// The ad a FREE scan sits behind (D-238): AdMob, non-personalised requests only. This is a health
/// app, and docs/13 promises health data is never used for advertising — so no advertising ID (the
/// manifest removes AD_ID) and no ATT prompt. Tests `implements` it, so the scan flow never needs
/// the SDK.
class RewardedAdGate {
  RewardedAdGate();

  /// Real unit ids arrive by `--dart-define`; without them, Google's public TEST units, so a
  /// development build can never earn — or be banned for — a real impression.
  static const _androidUnit = String.fromEnvironment(
    'ADMOB_REWARDED_ANDROID',
    defaultValue: 'ca-app-pub-3940256099942544/5224354917',
  );
  static const _iosUnit = String.fromEnvironment(
    'ADMOB_REWARDED_IOS',
    defaultValue: 'ca-app-pub-3940256099942544/1712485313',
  );

  bool _initialised = false;

  Future<AdOutcome> show() async {
    // Lazily: the SDK starts only for a FREE user who taps Scan, not on every app launch.
    if (!_initialised) {
      await MobileAds.instance.initialize();
      _initialised = true;
    }

    final loaded = Completer<RewardedAd?>();
    await RewardedAd.load(
      adUnitId: Platform.isIOS ? _iosUnit : _androidUnit,
      request: const AdRequest(nonPersonalizedAds: true),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: loaded.complete,
        onAdFailedToLoad: (_) => loaded.complete(null),
      ),
    );
    final ad = await loaded.future;
    if (ad == null) return AdOutcome.unavailable;

    final done = Completer<AdOutcome>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdDismissedFullScreenContent: (ad) {
        unawaited(ad.dispose());
        if (!done.isCompleted) done.complete(earned ? AdOutcome.earned : AdOutcome.skipped);
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        unawaited(ad.dispose());
        if (!done.isCompleted) done.complete(AdOutcome.unavailable);
      },
    );
    await ad.show(onUserEarnedReward: (_, _) => earned = true);
    return done.future;
  }
}

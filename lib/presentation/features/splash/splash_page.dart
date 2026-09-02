import 'package:flutter/material.dart';
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/core/theme/app_assets.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/frame_sequence.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The first thing the app shows, while secure storage is read on boot (D-92).
///
/// It was a two-line skeleton loader living at the bottom of `login_page.dart`, and it was on
/// screen for about one frame — long enough to flicker, not long enough to read. The walker is
/// already the app's signature everywhere else; opening on him is one asset the bundle
/// already carries rather than a new logo to draw.
///
/// docs/14 §3: `restoring` is a state, not an inferred null. Nothing here decides anything — it is
/// what `RootGate` shows while [SessionController.restore] runs.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  /// He is smaller here than on Home: this screen is one figure on an empty ground, and at hero
  /// size on a short phone his feet ran into the app name.
  static const _walkerHeight = 220.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                height: _walkerHeight,
                width: _walkerHeight * AppSizes.walkerAspect,
                child: FrameSequence(
                  frameCount: AppAssets.walkFrameCount,
                  frame: AppAssets.walkFrame,
                  cycle: AppMotion.walkCycle,
                  // Null, not a count: the splash is dismissed by the restore finishing, so a
                  // sequence that stopped after N cycles would freeze mid-boot on a slow keychain.
                  cycles: null,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                AppLocalizations.of(context).appTitle,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

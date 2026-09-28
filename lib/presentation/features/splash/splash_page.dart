import 'package:flutter/material.dart';
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/core/theme/app_assets.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/frame_sequence.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The first thing the app shows, while secure storage is read on boot (D-92).
///
/// The walker on his botanical stage (D-138) — the same figure, on the same podium, that Home
/// opens on, so the splash is the app's first frame rather than a different app that hands over.
/// Under him: the wordmark with its leaf (the D-102 treatment the welcome headlines use), the
/// tagline, and an indeterminate bar — indeterminate because a keychain read has no known length,
/// and a bar that pretends to measure one is a progress lie.
///
/// docs/14 §3: `restoring` is a state, not an inferred null. Nothing here decides anything — it is
/// what `RootGate` shows while [SessionController.restore] runs.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  /// The bar's share of the page width — long enough to read as progress, short enough to read
  /// as an accent rather than a form control.
  static const _barWidthFraction = 0.55;

  /// The decorative ground swell pinned to the bottom edge.
  static const _waveHeight = 96.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l = AppLocalizations.of(context);

    return Scaffold(
      body: Stack(
        children: [
          // Outside the SafeArea on purpose: the swell belongs to the screen's bottom edge, and
          // stopping it at the gesture inset would draw a hard line where the mock fades out.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _waveHeight,
            child: ExcludeSemantics(
              child: CustomPaint(painter: _WavesPainter(color: scheme.secondaryContainer)),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Column(
                children: [
                  Expanded(child: Center(child: _StagedWalker())),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: l.appTitle),
                        // The same leaf the welcome headlines carry (D-102), sized to the
                        // wordmark so it grows with the OS text setting.
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: const EdgeInsets.only(left: AppSpacing.xs),
                            child: Icon(
                              Icons.spa_outlined,
                              size: (theme.textTheme.displaySmall?.fontSize ?? 30) * 0.6,
                              color: scheme.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l.splashTagline,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  FractionallySizedBox(
                    widthFactor: _barWidthFraction,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      child: LinearProgressIndicator(
                        minHeight: AppSizes.barHeight,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    l.splashPreparing,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The walker on the podium, using the D-138 stage geometry the shell measured off the art —
/// feet on the surface line, stage width tied to his height, so the two screens cannot drift.
class _StagedWalker extends StatelessWidget {
  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1 / AppSizes.stageAspect,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final stageHeight = constraints.maxHeight;
        final walkerHeight = constraints.maxWidth / AppSizes.stageWidthFactor;

        return Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Positioned.fill(
              child: ExcludeSemantics(
                child: Image.asset(
                  AppAssets.themed(AppAssets.dashboardStage, Theme.of(context).brightness),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              bottom: stageHeight * (1 - AppSizes.stagePodiumLine),
              child: SizedBox(
                height: walkerHeight,
                width: walkerHeight * AppSizes.walkerAspect,
                child: const FrameSequence(
                  frameCount: AppAssets.walkFrameCount,
                  frame: AppAssets.walkFrame,
                  cycle: AppMotion.walkCycle,
                  // Null, not a count: the splash is dismissed by the restore finishing, so a
                  // sequence that stopped after N cycles would freeze mid-boot on a slow keychain.
                  cycles: null,
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// Two soft ground swells at the foot of the page, mock-for-mock. Decoration only — excluded
/// from semantics at the call site, and behind everything that means anything.
class _WavesPainter extends CustomPainter {
  const _WavesPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    Path swell(double top, double lift) => Path()
      ..moveTo(0, top + lift)
      ..quadraticBezierTo(size.width * 0.25, top - lift, size.width * 0.55, top)
      ..quadraticBezierTo(size.width * 0.8, top + lift * 0.7, size.width, top - lift * 0.3)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas
      ..drawPath(swell(size.height * 0.35, 16), Paint()..color = color.withValues(alpha: 0.45))
      ..drawPath(swell(size.height * 0.6, 12), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_WavesPainter oldDelegate) => oldDelegate.color != color;
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/core/theme/app_assets.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// One slide's content. A record rather than a class because nothing outside this file constructs
/// one and it never outlives a build.
typedef _Slide = ({
  String title,
  String body,
  IconData icon,
  IconData badge,
  int index,
  List<({IconData icon, String label, String sub})> facts,
});

/// What the app is, before it asks for a phone number (D-92).
///
/// Sits between the splash and sign-in, shown once per install. Someone who lands straight on
/// "Your phone number" has been asked to identify themselves by an app that has not yet said what
/// it does; three cards is the smallest thing that answers that.
///
/// Every claim here is one the app actually keeps — no numbers, no "lose 10 kg", no before-and-
/// after. docs/05 §6 tone rules apply to marketing copy first, not last.
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final _pages = PageController();
  var _index = 0;

  /// Kept only as the fallback an image error falls back to (D-102).
  ///
  /// This used to be the art itself, on the reasoning that three bundled images were not worth it
  /// for a screen seen once per install. The photographs won: a claim about roti and dal needs a
  /// photograph of roti and dal. The icons stay as the error state.
  static const _icons = [Icons.restaurant_menu, Icons.calculate_outlined, Icons.task_alt];

  /// The glyph in the medallion that straddles the curve between the photograph and the sheet.
  static const _badges = [Icons.ramen_dining_outlined, Icons.speed_outlined, Icons.done_all];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  List<_Slide> _slides(AppLocalizations l) => [
    (
      title: l.welcomeSlide1Title,
      body: l.welcomeSlide1Body,
      icon: _icons[0],
      badge: _badges[0],
      index: 0,
      facts: [
        (icon: Icons.home_outlined, label: l.welcomeSlide1Fact1, sub: l.welcomeSlide1Fact1Sub),
        (
          icon: Icons.soup_kitchen_outlined,
          label: l.welcomeSlide1Fact2,
          sub: l.welcomeSlide1Fact2Sub,
        ),
        (icon: Icons.favorite_border, label: l.welcomeSlide1Fact3, sub: l.welcomeSlide1Fact3Sub),
      ],
    ),
    (
      title: l.welcomeSlide2Title,
      body: l.welcomeSlide2Body,
      icon: _icons[1],
      badge: _badges[1],
      index: 1,
      facts: [
        (icon: Icons.person_outline, label: l.welcomeSlide2Fact1, sub: l.welcomeSlide2Fact1Sub),
        (icon: Icons.shield_outlined, label: l.welcomeSlide2Fact2, sub: l.welcomeSlide2Fact2Sub),
        (icon: Icons.calculate_outlined, label: l.welcomeSlide2Fact3, sub: l.welcomeSlide2Fact3Sub),
      ],
    ),
    (
      title: l.welcomeSlide3Title,
      body: l.welcomeSlide3Body,
      icon: _icons[2],
      badge: _badges[2],
      index: 2,
      facts: [
        (
          icon: Icons.check_circle_outline,
          label: l.welcomeSlide3Fact1,
          sub: l.welcomeSlide3Fact1Sub,
        ),
        (
          icon: Icons.water_drop_outlined,
          label: l.welcomeSlide3Fact2,
          sub: l.welcomeSlide3Fact2Sub,
        ),
        (icon: Icons.repeat_rounded, label: l.welcomeSlide3Fact3, sub: l.welcomeSlide3Fact3Sub),
      ],
    ),
  ];

  /// Finishing and skipping do the same thing on purpose. A "Skip" that quietly kept the carousel
  /// queued for the next launch would be a dark pattern for the sake of one more impression.
  Future<void> _finish() => Get.find<SessionController>().markIntroSeen();

  void _next(int last) {
    if (_index >= last) {
      unawaited(_finish());
      return;
    }
    unawaited(_pages.nextPage(duration: AppMotion.normal, curve: AppMotion.enter));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final slides = _slides(l);
    final last = slides.length - 1;
    final isLast = _index == last;

    return Scaffold(
      // The photograph runs under the status bar, so the top row is placed by the slide itself and
      // only the bottom inset is reserved here.
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                PageView.builder(
                  controller: _pages,
                  itemCount: slides.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => _SlideView(slide: slides[i]),
                ),
                // Above the PageView rather than inside it: the progress and the skip affordance
                // belong to the carousel, not to any one card, and a copy per page would slide.
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      0,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _Segments(count: slides.length, index: _index),
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        // Kept in the tree on the last card rather than removed, so the row does
                        // not reflow under the user's thumb on the final swipe.
                        _SkipButton(label: l.welcomeSkip, onPressed: isLast ? null : _finish),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          _Dots(count: slides.length, index: _index),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.sm,
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: _buttonHeight,
                child: FilledButton(
                  onPressed: () => _next(last),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.cardLarge),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // The label is centred and the arrow is pinned right, as in the reference —
                      // so the arrow reads as a direction rather than as part of the word.
                      Expanded(
                        child: Text(
                          isLast ? l.welcomeStart : l.welcomeNext,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Icon(Icons.arrow_forward_rounded, size: AppSpacing.xl),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The reference's call to action is a bar, not a chip — tall enough to be the only thing the
  /// thumb can reach for at the bottom of the screen.
  static const _buttonHeight = 62.0;
}

/// The thin bar across the top: one segment per slide, filled up to the current one.
///
/// It says the same thing as the dots at the bottom, and that is the reference's own arrangement:
/// the bar answers "how long is this" on arrival, the dots answer "where am I" while swiping.
class _Segments extends StatelessWidget {
  const _Segments({required this.count, required this.index});

  final int count;
  final int index;

  static const _height = 4.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      // The bar is decoration over a photograph; the carousel's position is announced once, here.
      label: '${index + 1} / $count',
      child: Row(
        children: [
          for (var i = 0; i < count; i++)
            Expanded(
              child: AnimatedContainer(
                duration: AppMotion.normal,
                curve: AppMotion.enter,
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs / 2),
                height: _height,
                decoration: BoxDecoration(
                  color: i <= index
                      ? theme.colorScheme.primary
                      : theme.colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A white pill over the photograph. A bare text button disappeared against the art; the pill is
/// what makes "Skip" legible on every one of the three images without dimming them.
class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;

    return Material(
      color: theme.colorScheme.surface.withValues(alpha: enabled ? 1 : 0.5),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        // Sized by its content, not aligned inside it: `Container(alignment:)` would expand to the
        // Stack's full loose height and turn the pill into a column down the side of the page.
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary.withValues(alpha: enabled ? 1 : 0.4),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.chevron_right_rounded,
                size: AppSpacing.xl,
                color: theme.colorScheme.primary.withValues(alpha: enabled ? 1 : 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});

  final _Slide slide;

  /// How much of the slide the photograph takes. The teardown's own proportion — enough that the
  /// image is the screen and the words sit under it, rather than a header above a paragraph.
  static const _artFraction = 0.48;

  /// The medallion that straddles the curve. Half of it hangs below the photograph, which is what
  /// stitches the two surfaces together instead of leaving a seam.
  static const _badgeSize = 92.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Centred when it fits and scrollable when it does not: at 200 % font scale the body outgrows
    // a short phone, and a bare Center would clip it rather than let it move (rule 12).
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: constraints.maxHeight * _artFraction,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: ClipPath(
                        clipper: const _SheetCurve(),
                        child: Image.asset(
                          AppAssets.welcomeSlide(slide.index),
                          // Cover, not contain: the supplied art is a mix of landscape and square,
                          // and letterboxing a full-bleed header is the difference between a
                          // designed screen and a placeholder.
                          fit: BoxFit.cover,
                          // A missing or corrupt asset must not take the first screen of the app
                          // down with it — the icon it used to show stands in.
                          errorBuilder: (context, _, _) => ColoredBox(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(
                              slide.icon,
                              size: AppSizes.avatar,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -_badgeSize / 2,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: _Badge(icon: slide.badge, size: _badgeSize),
                      ),
                    ),
                  ],
                ),
              ),
              // Clears the half of the medallion that hangs into the sheet.
              const SizedBox(height: _badgeSize / 2 + AppSpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: slide.title),
                          // A leaf, sized to the headline so it grows with the OS text setting.
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: const EdgeInsets.only(left: AppSpacing.sm),
                              child: Icon(
                                Icons.spa_outlined,
                                size: (theme.textTheme.displaySmall?.fontSize ?? 30) * 0.8,
                                color: theme.colorScheme.secondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w800,
                        height: 1.12,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      slide.body,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _FactStrip(facts: slide.facts),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The photograph's bottom edge: flat at the sides, bowing down through the middle.
///
/// A straight cut made the picture and the page read as two stacked rectangles. The bow is what
/// makes the sheet below look like it is being lifted over the photograph.
class _SheetCurve extends CustomClipper<Path> {
  const _SheetCurve();

  static const _dip = 34.0;

  @override
  Path getClip(Size size) => Path()
    ..lineTo(0, size.height - _dip)
    ..quadraticBezierTo(size.width / 2, size.height + _dip, size.width, size.height - _dip)
    ..lineTo(size.width, 0)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// The medallion over the curve: the slide's glyph, with a small warm heart clipped to its corner.
class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.size});

  final IconData icon;
  final double size;

  static const _heartFraction = 0.32;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heart = size * _heartFraction;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              shape: BoxShape.circle,
              // The ring is the page's own colour, so the medallion reads as a hole punched
              // through the photograph rather than as a sticker on top of it.
              border: Border.all(color: theme.colorScheme.surface, width: AppSpacing.xs),
            ),
            child: Icon(icon, size: size * 0.42, color: theme.colorScheme.primary),
          ),
          Positioned(
            right: -AppSpacing.xs / 2,
            bottom: heart * 0.15,
            child: Container(
              width: heart,
              height: heart,
              decoration: BoxDecoration(
                color: AppColors.warmCoral,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.surface, width: AppSpacing.xs / 2),
              ),
              child: Icon(Icons.favorite_rounded, size: heart * 0.5, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three claims in one tinted panel, divided by hairlines.
///
/// They are the body copy said again in three words each — the reference's own device, and it is
/// what someone skimming reads instead of the sentence.
class _FactStrip extends StatelessWidget {
  const _FactStrip({required this.facts});

  final List<({IconData icon, String label, String sub})> facts;

  static const _iconWell = 44.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg, horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.cardLarge),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, fact) in facts.indexed) ...[
              if (i > 0)
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                ),
              Expanded(
                child: Column(
                  children: [
                    Container(
                      width: _iconWell,
                      height: _iconWell,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(fact.icon, size: AppSpacing.xl, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      fact.label,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      fact.sub,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  static const _size = 8.0;
  static const _activeWidth = 24.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: AppMotion.normal,
            curve: AppMotion.enter,
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            height: _size,
            width: i == index ? _activeWidth : _size,
            decoration: BoxDecoration(
              color: i == index
                  ? theme.colorScheme.primary
                  : theme.colorScheme.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
      ],
    );
  }
}

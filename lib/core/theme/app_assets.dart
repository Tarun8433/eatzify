import 'package:flutter/material.dart';

/// Bundled asset paths. A widget never names a file directly, for the same reason it never names a
/// colour: one place to change, and one list to check the bundle against (NFR-4: nothing bundled
/// that is not used).
abstract final class AppAssets {
  /// The Home walker (D-55): a 38-frame walk cycle, 308×886 palette PNGs, ~13 KB each.
  static const walkFrameCount = 38;

  /// Frame [index], 0-based.
  static String walkFrame(int index) =>
      'assets/walking/frame_${(index + 1).toString().padLeft(2, '0')}.png';

  /// The walker beside the steps tab's headline (D-126). Paired (D-161) — read it through
  /// [themed], never directly, or dark mode gets the pale grade. Trimmed to its content,
  /// re-encoded to 520 px (three times the ~165 pt it is ever drawn at) and palette-quantised.
  static const activityHero = 'assets/activity/walking.png';

  /// The scales beside the weight tab's headline (D-127). Paired; same treatment as
  /// [activityHero]: trimmed of its empty canvas, 520 px, palette-quantised.
  static const weightHero = 'assets/activity/weighing_scale.png';

  /// The trainer beside the "Become a partner" headline (D-185). Carries its own "Make an impact"
  /// lettering in the art, so it is DECORATIVE and excluded from semantics — a screen reader that
  /// announced it would read the slogan twice for anyone who also hears the headline.
  static const partnerHero = 'assets/requirement_screens_img/traner.png';

  /// The bottle beside the water tab's headline (D-129). Paired; same treatment as the others:
  /// trimmed of its empty canvas, 520 px, palette-quantised.
  static const waterHero = 'assets/activity/water_bottle.png';

  /// The bowl beside the Plan tab's target card (D-132). A photograph rather than an illustration,
  /// because the tab is about food a person will actually eat. Trimmed, re-encoded to 520 px and
  /// palette-quantised at 160 colours — food needs more of them than a flat illustration does.
  /// The one hero with NO dark grade — none was supplied — so it is deliberately absent from
  /// [_paired] and renders the same picture in both themes until that art exists.
  static const planHero = 'assets/activity/plan_bowl.png';

  /// The botanical stage the Home walker stands on (D-138): an arch, leaves, and a podium whose
  /// surface is placed under his feet. Paired; trimmed, 640 px, quantised.
  static const dashboardStage = 'assets/activity/dashboard_stage.png';

  /// Played while the first plan is generated, straight after onboarding (D-75). The space in the
  /// filename is the artist's; renaming it would only move the quoting problem into pubspec.yaml.
  static const preparingPlan = 'assets/Preparing Food.json';

  /// The welcome carousel's art, one per slide (D-102). Photographs of real meals and real
  /// kitchens rather than illustration: the promise on slide one is "food you already eat", and an
  /// illustrated plate would undercut the only claim the screen makes.
  static String welcomeSlide(int index) => 'assets/onboarding/o${index + 1}.jpg';

  /// The image behind the sign-in screen.
  static const welcomeHero = 'assets/welcome/hero.jpg';

  /// The illustration beside the sign-in headline (D-109): a phone showing a code, a padlock, and
  /// the brand's leaves. Replaced with the reference's own art (D-131), given the same treatment as
  /// every other hero — trimmed of its empty canvas, re-encoded to 520 px (three times the 165 pt
  /// ceiling it is drawn at) and palette-quantised: 1.0 MB to 32 KB.
  static const loginHero = 'assets/welcome/login_hero.png';

  /// The bowl that bleeds off the top-right corner of the first onboarding step (D-106). A
  /// cut-out, so PNG rather than the JPG D-102 chose for the full-bleed carousel art — the page
  /// has to show through around the leaves. Palette-quantised to 159 KB at 800 px, which is three
  /// times the 250 pt it is ever drawn at.
  static const basicsHero = 'assets/onboarding/basics_hero.png';

  /// The scales-and-plant beside the goal-gap headline (D-110). Supplied at 1519 px and
  /// re-encoded to 520 — three times the ~170 pt it is drawn at, and 164 KB rather than 1.25 MB.
  static const goalHero = 'assets/onboarding/goal_hero.png';

  /// The window, clock and plant on the daily-routine step (D-109). Same treatment as
  /// [basicsHero]: a cut-out PNG, resized to 720 px and palette-quantised. Paired — and the dark
  /// grade arrived flattened against a DRAWN checkerboard rather than a transparent ground, so
  /// that ground was flood-filled back out from the corners before encoding (D-159); 18 % is the
  /// tolerance that clears both checker greys and still leaves the cream curtains standing.
  static const routineHero = 'assets/onboarding/routine_hero.png';

  /// The pointing figure beside the disclaimer's four points. Same treatment as the splash
  /// stage: a cut-out re-encoded to WebP at three times its ~140 pt display width — 1.5 MB of
  /// PNG to 41 KB.
  static const disclaimerHero = 'assets/onboarding/disclaimer_hero.webp';

  /// The folder-and-shield above the consent question (D-115). A cut-out with a fully transparent
  /// ground, which is the requirement rather than a detail: the page is cream, and art carrying its
  /// own white background would put a second, whiter rectangle behind the one thing on the screen
  /// asking for a decision. Paired, and the dark grade arrived with a checkerboard drawn into its
  /// pixels — which is exactly that failure; it is flood-filled back out the way [routineHero] is.
  static const consentHero = 'assets/onboarding/consent_hero.png';

  /// The heroes that exist in both grades. A `dark/` sibling of each, same filename.
  ///
  /// Explicit rather than "try the dark path and fall back", because a missing asset in Flutter is
  /// a broken image at runtime, not a caught error — and [planHero] genuinely has no dark grade.
  /// `app_assets_test.dart` fails if a path here has no file behind it, so the set cannot drift
  /// away from what is on disk.
  static const _paired = {
    activityHero,
    weightHero,
    waterHero,
    dashboardStage,
    routineHero,
    consentHero,
  };

  /// The grade to draw for [brightness] (D-161).
  ///
  /// The art was supplied as two colour grades of the same drawings — the pale one washes out on
  /// a near-black page, the saturated one is heavy on cream — so the hero follows the theme the
  /// way every colour token already does. An asset with only one grade returns it unchanged.
  static String themed(String asset, Brightness brightness) {
    if (brightness != Brightness.dark || !_paired.contains(asset)) return asset;
    final cut = asset.lastIndexOf('/');
    return '${asset.substring(0, cut)}/dark/${asset.substring(cut + 1)}';
  }

  /// Meal-slot headers, keyed by position in `docs/09 §5` slot order.
  static String mealSlot(int index) => 'assets/meal_slots/t${index % 8 + 1}.jpg';
}

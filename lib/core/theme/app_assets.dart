/// Bundled asset paths. A widget never names a file directly, for the same reason it never names a
/// colour: one place to change, and one list to check the bundle against (NFR-4: nothing bundled
/// that is not used).
abstract final class AppAssets {
  /// The Home walker (D-55): a 38-frame walk cycle, 308×886 palette PNGs, ~13 KB each.
  static const walkFrameCount = 38;

  /// Frame [index], 0-based.
  static String walkFrame(int index) =>
      'assets/walking/frame_${(index + 1).toString().padLeft(2, '0')}.png';

  /// The walker beside the steps tab's headline (D-126). Supplied at 1536 px with two thirds of
  /// the canvas empty; trimmed to its content, re-encoded to 520 px — three times the ~165 pt it is
  /// ever drawn at — and palette-quantised, which took it from 871 KB to 33 KB.
  static const activityHero = 'assets/activity/walking.png';

  /// The scales beside the weight tab's headline (D-127). Same treatment as [activityHero]:
  /// trimmed of its empty canvas, re-encoded to 520 px and palette-quantised, 1.5 MB to 29 KB.
  static const weightHero = 'assets/activity/weighing_scale.png';

  /// The bottle beside the water tab's headline (D-129). Same treatment as the others: trimmed of
  /// its empty canvas, re-encoded to 520 px and palette-quantised, 1.3 MB to 47 KB.
  static const waterHero = 'assets/activity/water_bottle.png';

  /// The bowl beside the Plan tab's target card (D-132). A photograph rather than an illustration,
  /// because the tab is about food a person will actually eat. Trimmed, re-encoded to 520 px and
  /// palette-quantised at 160 colours — food needs more of them than a flat illustration does.
  static const planHero = 'assets/activity/plan_bowl.png';

  /// The botanical stage the Home walker stands on (D-138): an arch, leaves, and a podium whose
  /// surface is placed under his feet. Same treatment as every hero: trimmed, 640 px, quantised —
  /// 1.4 MB to 54 KB.
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
  /// [basicsHero]: a cut-out PNG, resized and palette-quantised from 1.6 MB to 53 KB.
  static const routineHero = 'assets/onboarding/routine_hero.png';

  /// The folder-and-shield above the consent question (D-115). A cut-out with a fully transparent
  /// ground, which is the requirement rather than a detail: the page is cream, and art carrying its
  /// own white background would put a second, whiter rectangle behind the one thing on the screen
  /// asking for a decision. 1.3 MB re-encoded to 229 KB at 560 px.
  static const consentHero = 'assets/onboarding/consent_hero.png';

  /// Meal-slot headers, keyed by position in `docs/09 §5` slot order.
  static String mealSlot(int index) => 'assets/meal_slots/t${index % 8 + 1}.jpg';
}

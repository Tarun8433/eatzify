import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 4 pt spacing scale and the three radii. docs/14 §5.
/// A magic number in a widget is a bug — use these.
abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  /// Minimum touch target. docs/14 §5 and CLAUDE.md rule 12.
  static const minTouchTarget = 48.0;

  /// The screen gutter: the inset from the screen edge to content, on every screen. A header and
  /// the body beneath it both use THIS — picking separately off the scale is what put every tab's
  /// title 8 pt left of its own content, because `TabScaffold` had chosen [lg] and all four bodies
  /// had chosen [xl].
  ///
  /// [md], not the [xl] docs/DESIGN-SYSTEM §5 first set (D-177): at 24 the cards had given up a
  /// seventh of a phone's width to margin. Changing it here moves every screen at once, which is
  /// the whole reason the gutter is a name rather than a number repeated down the tree.
  ///
  /// A sheet is already inset from the page and runs on [lg] instead — see the food log's
  /// search row. That is the one deliberate exception; anything full-screen uses this.
  static const screenH = md;
}

/// Corner radii. docs/14 §5: 12 cards, 24 sheets, 999 pills. Pick and stick.
abstract final class AppRadius {
  static const card = 12.0;

  /// The larger radius the card-led layout uses (docs/14 §5 design language).
  static const cardLarge = 20.0;
  static const tile = 16.0;
  static const sheet = 24.0;
  static const pill = 999.0;
}

/// Component sizes. Here rather than inline so a ring is the same size everywhere it appears.
abstract final class AppSizes {
  static const ringSmall = 44.0;

  /// The disc on an onboarding option row. Smaller than [ringSmall] on purpose: that one heads a
  /// card, this one repeats three to eight times down a step, and at 44 pt the rows stood 68 pt
  /// tall and made one-word answers look like the longest question in the funnel. At 32, with the
  /// row's own padding, the tile lands on the 48 dp touch floor exactly.
  static const choiceDisc = 32.0;
  static const ringMacro = 56.0;

  /// The narrowest a Home nutrient tile can be and still read (D-138 revisited).
  ///
  /// Four tiles divided a phone's content column into 79 pt each, and a tile is a stack — disc,
  /// label, "0 / 121 g", ring, percent — so at that width it read as four tall, narrow columns
  /// rather than as a row of tiles. Below this the row scrolls sideways instead of squeezing;
  /// above it the tiles share the width evenly and nothing scrolls.
  static const nutrientTile = 112.0;

  /// A coach's stat tile. Wider than a nutrient tile because it carries a trend line under the
  /// label, and "vs last 30 days" wraps to three lines at 112.
  static const coachTile = 136.0;

  /// A series chart on a coach's client screen. Shorter than the Progress tab's full chart because
  /// several stack on one page, tall enough that a gentle trend is still visible.
  static const coachChart = 120.0;
  static const gauge = 200.0;
  static const chartHeight = 200.0;
  static const avatar = 96.0;
  static const barHeight = 8.0;

  /// The screen's primary call to action (D-107). Half again the 48 dp minimum: the reference
  /// gives the one button a screen is built around real weight, and a 48 pt bar reads as a form
  /// control rather than as the way forward.
  static const primaryButton = 56.0;

  /// Art that sits BESIDE a headline — the sign-in phone, the goal scales (D-111).
  ///
  /// One pair of numbers rather than a fraction invented per screen, which is how the sign-in art
  /// ended up at 0.36 of the width and the goal art at 0.32 with no reason for the difference.
  /// They are a ratio, not a size: the art takes its share of whatever width it is given, up to a
  /// ceiling that stops it ballooning on a tablet.
  ///
  /// Raised from ~0.34 once the type came down to a 1.2 scale (D-111). The art had been sized
  /// against a 32 pt headline that needed most of the row; against 26 pt there is room for the
  /// picture to be a picture.
  static const heroArtFraction = 0.42;
  static const heroArtMax = 165.0;

  /// The headline's share of the same row. It and [heroArtFraction] add up to more than one, and
  /// that is deliberate — the same overlap `_BasicsHero` uses (D-106): the outer eighth of these
  /// PNGs is transparent, so the two BOXES overlap while nothing drawn in them does. Sized so they
  /// could not, "You're aiming to" broke after "aiming" and the headline ran to three lines.
  static const heroTextFraction = 0.70;

  /// The Home hero's percentage (D-119). Deliberately OUTSIDE the 1.2 type scale of D-111: that
  /// scale sizes running text, and this is a figure read across a room — `lib/screen/1.dart` sets
  /// it at 84 against a 20 pt stat, a ratio no text scale would ever produce. One number on one
  /// screen; anything else on the page still comes from `AppTextStyles`.
  static const heroFigure = 72.0;

  /// A number the screen is built around and is typed INTO — the weight on the log form (D-127).
  /// Between the 26 pt display style and Home's 72 pt read-across-a-room figure: it has to look
  /// like the answer the screen wants while still leaving room for "300.0" and a unit beside it.
  static const inputFigure = 48.0;

  /// The week-of-bars under a daily habit on Progress (D-128). Tall enough that a light day and a
  /// heavy one are visibly different, short enough that three of these fit above the fold.
  static const habitBar = 44.0;

  /// A single box in the OTP row (D-109). Six of these plus their gaps have to fit a phone's
  /// content column, so it is a MINIMUM height rather than a size: the box grows with the text
  /// scale and the width comes from the row dividing what is left.
  static const otpCell = 56.0;

  /// The macro rings' stroke and the gap between them — the reference's own 10 and 2.5 (D-67).
  ///
  /// The ratio is what matters, not the stroke alone. At 13 and 7 the radii stepped by 20, so the
  /// innermost ring came in at 0.55 of the outer and the group read as three separate hoops around
  /// a small hole instead of as one band. The reference steps by 12.5, putting the inner ring at
  /// 0.72 of the outer.
  static const ringStroke = 10.0;
  static const ringGap = 2.5;

  /// The Home hero (D-55, enlarged in D-58): the walker's box and the rings under his feet. He is
  /// the screen's subject now that no card frames him, and at 220 he read as an icon beside the
  /// figures rather than as the thing they describe.
  static const heroArt = 320.0;

  /// The rings' diameter, and the width of the column they share with the walker (D-66). They are
  /// circles and they stay inside that column: painted wider, they ran left across the figures and
  /// the caption text beside them.
  static const heroRings = 190.0;

  /// The rings lie on the floor by being TILTED, not by being drawn as ellipses (D-67). Matches the
  /// walking_animation reference's `Matrix4..setEntry(3, 2, ringPerspective)..rotateX(ringTilt)`.
  ///
  /// This is the whole difference between the reference's clean floor and the version that read as
  /// overlapping: a rotation compresses the strokes by exactly as much as it compresses the gaps
  /// between them, so the rings stay as far apart at the back of the ellipse as at the sides.
  /// Squashing the circles instead left the stroke at full width while the gaps shrank, and at the
  /// near and far edges 13 pt strokes met across a 7 pt gap.
  static const ringTilt = -1.05;
  static const ringPerspective = 0.0011;

  /// The You tab's profile frame (D-59): the panel's height, and the hole's radius as a fraction of
  /// its width. The walker shows through the hole and the panel covers the rest of him, which is
  /// what makes the circle read as a frame rather than as a cropped photo.
  /// 240, down from 320 (D-145): the frame's content is the avatar and a greeting now, not an
  /// 84 pt figure, and the old floor held a dead band open between the hole and the glance card.
  /// 150, down from 320 then 240 (D-147): the floor only has to hold the avatar row now, and
  /// anything taller held a dead band open between the hero and the content.
  static const profileFrame = 150.0;

  /// The travelling walker's frames are 308 x 886, so his box is this much wider than it is tall
  /// (D-56). Sizing him by height and deriving the width keeps him upright at every anchor.
  static const walkerAspect = 308 / 886;

  /// The botanical stage under the walker (D-138), shared by the shell and the splash so his
  /// setting is the same everywhere he stands. Width against HIS height, so shrinking him shrinks
  /// the stage with him; the aspect is the file's own; the podium surface is measured off the art.
  static const stageWidthFactor = 1.45;
  static const stageAspect = 763 / 640;
  static const stagePodiumLine = 0.86;

  /// Below this card width, or above this text scale, the hero stacks art over figures instead of
  /// side by side — a four-digit headline at 200 % no longer fits beside the art (rule 12).
  /// 300: a 390 pt phone leaves the card 310 pt inside its paddings, and must stay side by side.
  static const heroBreakpoint = 300.0;

  /// The narrowest a tier card can be and still hold a price and a per-month line beside a radio
  /// (D-160). Two of these plus a gap is what the paywall needs before it puts BASIC and PRO side
  /// by side; under it the cards stack, which is also what happens at 200 % text because the
  /// threshold is measured against the scaled width rather than the raw one (rule 12).
  static const tierCardMin = 150.0;

  /// The narrowest a number field can be and still read (D-90, widened in D-108). Two of these
  /// plus the gap is what `_NumberPair` needs before it will sit side by side — a phone's content
  /// column is about 330, so the threshold has to stay under that or the pair stacks everywhere.
  ///
  /// 160, not 150, because the field grew two affixes: a 48 pt leading disc and a 48 pt picker
  /// button leave a 150 pt column 46 pt of label, which is less than "Weight" needs. At 160 the
  /// narrowest column that still goes side by side has 61 pt, and the paired labels are all under
  /// 44. Below the threshold the pair stacks and has the whole width.
  static const wheelColumnMin = 160.0;

  /// How far the floor rings hang BELOW the box the hero reserves for the walker (D-100).
  ///
  /// They are centred on his feet, at the bottom of that box, and tilted — so half an ellipse of
  /// them falls outside it. `heroRings / 2 * cos(ringTilt)` is that half, and content placed after
  /// the hero has to clear it or it scrolls through the rings. Home never had full-width content
  /// at that height before the stat grid, so nothing had needed the number.
  static final heroRingOverhang = heroRings / 2 * math.cos(ringTilt).abs();
  static const heroStackTextScale = 1.15;
}

/// The elevation scale (D-100). One place, so a card on Home and a card on Progress cast the same
/// shadow — a screen where every surface invents its own is the single clearest tell of an
/// unfinished interface.
///
/// Two layers, not one. A single blurred drop reads as fog; a tight contact shadow plus a wide
/// ambient one is how a real object sits on a surface, and it is what separates a card from a
/// rectangle with a border.
///
/// The shadow is TINTED, not black. `lightBackground` is a warm cream, and neutral black over it
/// greys the page — the shade under a card should be a darker version of the surface it falls on.
abstract final class AppElevation {
  /// Resting surface: a card, a tile, a chip.
  static List<BoxShadow> card(Brightness brightness) => brightness == Brightness.dark
      // A shadow needs light to be cast. On a near-black page it reads as a smudge, so depth in
      // dark mode comes from the surface being lighter than the ground, not from a shadow.
      ? const []
      : const [
          BoxShadow(color: Color(0x0F2A1F14), blurRadius: 2, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x14332617), blurRadius: 16, offset: Offset(0, 6)),
        ];

  /// A surface that has left the page: a sheet, a menu, the card under a finger.
  static List<BoxShadow> raised(Brightness brightness) => brightness == Brightness.dark
      ? const []
      : const [
          BoxShadow(color: Color(0x142A1F14), blurRadius: 3, offset: Offset(0, 2)),
          BoxShadow(color: Color(0x1F332617), blurRadius: 28, offset: Offset(0, 12)),
        ];
}

/// Motion tokens. Durations sit in the 150–300 ms band the platform guidelines ask for; anything
/// longer reads as sluggish rather than smooth.
///
/// Every animated widget must check `AppMotion.enabled(context)` first — the OS "reduce motion"
/// setting is an accessibility request, not a preference to override.
abstract final class AppMotion {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);

  /// Entering: ease-out. Motion decelerates into place rather than stopping dead.
  static const enter = Curves.easeOutCubic;

  /// One tab change: the outgoing page turns away, the incoming one turns in, and the walker walks
  /// between his two anchors (D-56). Longer than [normal] because the walker has to cross the
  /// screen and a 250 ms sprint reads as a teleport; still inside the band for a full-screen change.
  static const tabSwitch = Duration(milliseconds: 420);

  /// Both halves of a tab change use the same curve, so the hand-off at the halfway point has no
  /// kink in it.
  static const tabSwitchCurve = Curves.easeInOut;

  /// One walk cycle of the walker: 38 frames at 30 fps. He walks continuously (D-58) — a walk that
  /// stopped after six cycles read as the animation freezing, which is the opposite of what a
  /// figure mid-stride is for. Reduced motion still holds him on one frame.
  static const walkCycle = Duration(milliseconds: 1267);

  static bool enabled(BuildContext context) => !MediaQuery.of(context).disableAnimations;
}

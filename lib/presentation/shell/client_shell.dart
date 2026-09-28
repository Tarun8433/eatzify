import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_assets.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/cube_transition.dart';
import 'package:health_pro/presentation/features/account/account_page.dart';
import 'package:health_pro/presentation/features/home/home_page.dart';
import 'package:health_pro/presentation/features/plan/plan_page.dart';
import 'package:health_pro/presentation/features/progress/progress_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/log_sheet.dart';
import 'package:health_pro/presentation/shell/nav_controller.dart';
import 'package:health_pro/presentation/shell/walking_man.dart';

/// The ONE client shell. docs/14 §1:
///
///     Home    Plan    [ + ]    Progress    You
///
/// Deleted on purpose and not to be reintroduced: the hamburger menu, the separate Diary and Log
/// tabs, the Reports/Trends split, the Tracker/Diet Plan/Progress shell, and the per-screen
/// back-arrow-plus-Menu-pill pattern. Adding a tab requires an ADR.
///
/// D-56: a tab change is animated rather than cut. The outgoing page turns away like a face of a
/// cube, the incoming one turns in behind it, and the walker walks between the two tabs' anchors.
/// [NavController] stays the source of truth — the shell watches it and animates to whatever it
/// says, so a tab change from anywhere else animates identically.
class ClientShell extends StatefulWidget {
  const ClientShell({super.key});

  /// Identifies the slide that carries the You sheet, so a test can tell it apart from the several
  /// the Scaffold, the nav bar and the FAB contribute.
  static const youSlideKey = ValueKey('you-slide');

  @override
  State<ClientShell> createState() => _ClientShellState();
}

class _ClientShellState extends State<ClientShell> with SingleTickerProviderStateMixin {
  final _nav = Get.find<NavController>();

  /// 0 at the start of a tab change, 1 when it has arrived. Starts arrived: the first frame of the
  /// app is not a transition.
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: AppMotion.tabSwitch,
    value: 1,
  );
  late final Animation<double> _eased = CurvedAnimation(
    parent: _slide,
    curve: AppMotion.tabSwitchCurve,
  );

  late double _from = _nav.indexOf(_nav.current).toDouble();
  late double _to = _from;

  /// The pages either side of the turn. Held separately from the indices because the page showing
  /// during the first half is the one we are leaving, which [NavController] has already forgotten.
  late ClientTab _fromTab = _nav.current;
  late ClientTab _toTab = _nav.current;

  Worker? _watch;

  @override
  void initState() {
    super.initState();
    _watch = ever<ClientTab>(_nav.selected, _animateTo);
  }

  @override
  void dispose() {
    _watch?.dispose();
    _slide.dispose();
    super.dispose();
  }

  /// Fractional tab position. Drives the You sheet's slide; the walker is placed by anchors.
  double get _position => lerpDouble(_from, _to, _eased.value)!;

  /// Where the current leg of his walk starts, and whether it starts on screen.
  ///
  /// Snapshotted on every retarget so a second tap mid-walk carries on from where he is rather
  /// than jumping back to the anchor he had already left (D-74).
  late WalkAnchor _fromAnchor = WalkingMan.anchorFor(_fromTab);
  late bool _fromVisible = WalkingMan.showsWalker(_fromTab);

  /// The anchor he is standing at right now — only meaningful while he is on screen, which is the
  /// only case where carrying it forward means anything.
  WalkAnchor get _currentAnchor => _fromVisible && WalkingMan.showsWalker(_toTab)
      ? WalkAnchor.lerp(_fromAnchor, WalkingMan.anchorFor(_toTab), _eased.value)
      : _fromAnchor;

  /// The botanical stage under the walker — on Home AND inside the You frame's circle (D-149):
  /// the same art is the mock's backdrop on both screens. Its podium SURFACE — 86 % of the way
  /// down the art — sits exactly at his feet, from the same [WalkingMan.boundsIn] the walker
  /// uses. It fades with his travel so it never hangs in the air over Plan or Progress.
  Widget _stageFor(BuildContext context, ClientTab tab) {
    final arriving = _toTab == tab;
    final leaving = _fromTab == tab && _fromVisible;
    if (!arriving && !leaving) return const SizedBox.shrink();

    final t = _eased.value;
    final opacity = arriving ? t : (1 - t);
    if (opacity <= 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final man = WalkingMan.boundsAt(constraints.biggest, tab);
        final width = man.height * AppSizes.stageWidthFactor;
        final height = width * AppSizes.stageAspect;

        return Stack(
          children: [
            Positioned(
              left: man.center.dx - width / 2,
              top: man.bottom - height * AppSizes.stagePodiumLine,
              width: width,
              height: height,
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: Image.asset(
                    AppAssets.themed(AppAssets.dashboardStage, Theme.of(context).brightness),
                    width: width,
                    // Explicit, never decode-derived: an Image with only a width is 0 pt tall
                    // until the asset loads, and the podium line jumps a frame later (D-138).
                    height: height,
                    fit: BoxFit.contain,
                    errorBuilder: (context, _, _) => SizedBox(width: width, height: height),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _animateTo(ClientTab tab) {
    if (tab == _toTab) return;
    setState(() {
      // Retargeting mid-turn starts from where the walker actually is, so a second tap does not
      // snap him back to the tab he had already left.
      _from = _position;
      _fromAnchor = _currentAnchor;
      // Where THIS leg starts: on screen only if he is still on it. Mid-descent he is not, so the
      // new leg brings him in from the top rather than pretending he never left.
      _fromVisible = _slide.value >= 1
          ? WalkingMan.showsWalker(_toTab)
          : _fromVisible && WalkingMan.showsWalker(_toTab);
      _fromTab = _slide.value < 0.5 ? _fromTab : _toTab;
      _to = _nav.indexOf(tab).toDouble();
      _toTab = tab;
    });
    _slide
      // Reduced motion is a request, not a preference: the tab still changes, it just does not
      // travel. Zero duration lands on the next frame with no interpolation.
      ..duration = AppMotion.enabled(context) ? AppMotion.tabSwitch : Duration.zero
      ..forward(from: 0);
  }

  Widget _pageFor(ClientTab tab) => switch (tab) {
    // Const so the element survives the rebuild every animation frame: an identical widget is not
    // rebuilt, which is what stops the turn from re-running each page's controller and its request.
    ClientTab.home => const HomePage(),
    ClientTab.plan => const PlanPage(),
    ClientTab.progress => const ProgressPage(),
    ClientTab.you => const AccountPage(),
  };

  /// Which tab's face is showing and how far it has turned, in quarter-turns.
  ///
  /// First half of a tab change: the tab being left swings out through the edge it leaves by.
  /// Second half: the tab being opened swings in through the opposite edge. Read once per frame so
  /// the page and anything layered over it turn as one object rather than as two that agree by
  /// coincidence (D-69).
  ///
  /// You is not one of them — it slides rather than turns. See [_youIn].

  /// Wraps only while there is a turn to show. At rest the page is itself — a settled tab must not
  /// carry a permanent Transform and Opacity, and `shell_walker_test` pins that.
  static Widget _turning(double turn, Widget child) =>
      turn == 0 ? child : CubeTransition(turn: turn, child: child);

  /// How far the You sheet has come in: 0 is fully above the screen, 1 is in place.
  ///
  /// It SLIDES down over the walker instead of turning like the other tabs (D-71). A cube face
  /// shrinks in perspective as it turns, and the walker does not — mid-turn he stood at full size
  /// poking out of every edge of a page that was supposed to be covering him, which read as the
  /// page arriving from underneath him. A full-screen sheet that translates always covers.
  double get _youIn => (_position - (ClientTab.you.index - 1)).clamp(0.0, 1.0);

  ({ClientTab tab, double turn}) _face() {
    final t = _eased.value;
    if (t >= 1 || _fromTab == _toTab) return (tab: _toTab, turn: 0);

    // Forwards, the old page drops out through the BOTTOM so the new one arrives from the top.
    // The other way round sent every new tab climbing up from the bottom of the screen.
    final forwards = _to >= _from;
    final leaving = forwards ? 1.0 : -1.0;
    return t < 0.5
        ? (tab: _fromTab, turn: leaving * (t * 2))
        : (tab: _toTab, turn: -leaving * (2 - t * 2));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _eased,
          builder: (context, _) {
            final face = _face();
            final youIn = _youIn;
            final involvesYou = _fromTab == ClientTab.you || _toTab == ClientTab.you;

            // The page BEHIND him is never You. While You is coming or going it does not turn
            // either: two transitions at once — one sliding, one rotating — reads as neither.
            final behindTab = involvesYou
                ? (_fromTab == ClientTab.you ? _toTab : _fromTab)
                : face.tab;
            final behindTurns = !involvesYou;

            return Stack(
              children: [
                // The stage, then him, then the PAGE (D-140): the pages paint no background of
                // their own, so he shows wherever a page has nothing — and the moment it scrolls,
                // its cards pass OVER him instead of being trampled. He still belongs to the
                // shell and walks between tabs rather than turning with them (D-60).
                Positioned.fill(child: _stageFor(context, ClientTab.home)),
                Positioned.fill(child: _stageFor(context, ClientTab.you)),
                Positioned.fill(
                  child: WalkingMan(
                    fromAnchor: _fromAnchor,
                    fromVisible: _fromVisible,
                    to: _toTab,
                    t: _eased.value,
                  ),
                ),
                // Gone once the You sheet is fully in place (D-145): with the walker BEHIND the
                // pages (D-140), a page left mounted here paints its cards over him. And since
                // You stopped being an opaque sheet (D-152) it no longer covers this page as it
                // slides — so the page FADES with the slide (D-154): without the fade it sat
                // fully visible under the transparent You page and then popped away in one frame,
                // which read as a flicker. Leaving You, the same fade runs backwards.
                if (behindTab != ClientTab.you && youIn < 1)
                  Positioned.fill(
                    child: behindTurns
                        ? _turning(face.turn, _pageFor(behindTab))
                        : Opacity(opacity: 1 - youIn, child: _pageFor(behindTab)),
                  ),
                // You, in front of him and coming down from the top (D-70, D-71). Its full-bleed
                // sheet is what hides him; he shows through the hole in it and nowhere else.
                if (youIn > 0)
                  Positioned.fill(
                    child: FractionalTranslation(
                      // Keyed so a test can tell this slide apart from the several the Scaffold,
                      // the nav bar and the FAB contribute, all of which sit at zero.
                      key: ClientShell.youSlideKey,
                      // -1 is a full screen height above; 0 is in place.
                      translation: Offset(0, youIn - 1),
                      child: _pageFor(ClientTab.you),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => LogSheet.show(context),
        tooltip: l10n.logEntry,
        child: const Icon(Icons.add, size: AppSpacing.xl),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: Obx(
        () => NavigationBar(
          selectedIndex: _nav.indexOf(_nav.selected.value),
          onDestinationSelected: (i) => _nav.current = ClientTab.values[i],
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home),
              label: l10n.tabHome,
            ),
            NavigationDestination(
              icon: const Icon(Icons.restaurant_menu_outlined),
              selectedIcon: const Icon(Icons.restaurant_menu),
              label: l10n.tabPlan,
            ),
            NavigationDestination(
              icon: const Icon(Icons.show_chart_outlined),
              selectedIcon: const Icon(Icons.show_chart),
              label: l10n.tabProgress,
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: l10n.tabYou,
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/domain/repositories/coach_repository.dart';
import 'package:health_pro/presentation/features/coach/chat_page.dart';
import 'package:health_pro/presentation/features/coach/check_ins_tab.dart';
import 'package:health_pro/presentation/features/coach/coach_dashboard_page.dart';
import 'package:health_pro/presentation/features/coach/coach_you_tab.dart';
import 'package:health_pro/presentation/features/coach/dashboard_controller.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The coach's shell. CLAUDE.md rule 1 fixes the tabs: `Clients · Check-ins · [+] · Messages · You`.
/// Adding or renaming one needs an ADR.
///
/// **Reached from the You tab, not instead of it (D-174).** A coach is a client of their own app:
/// a nutritionist who becomes a partner still tracks their own food, so this surface ADDS to the
/// client shell rather than replacing it. That is why it has a back arrow.
///
/// **A skeleton, deliberately.** The tabs are real and every one says plainly that its screen is
/// unbuilt. E6 is the epic that fills them.
///
/// What must NOT be built into it later, from docs/10 §5: no client export, of any kind, in any
/// format. That prohibition is the difference between a platform and a lead-generation leak, and
/// it is easiest to honour before a "share client list" button feels obvious.
class CoachShell extends StatefulWidget {
  const CoachShell({super.key});

  @override
  State<CoachShell> createState() => _CoachShellState();
}

class _CoachShellState extends State<CoachShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    // The `[+]` of rule 1 is the client shell's centre action. A coach's equivalent is "invite a
    // client", and docs/09 §6 makes that a POST the CLIENT must then accept — so it is a real
    // action with a real flow, not a tab, and it is left out until that flow exists.
    final tabs = <({IconData icon, String label, String body})>[
      (icon: Icons.group_outlined, label: l.coachTabClients, body: l.coachClientsSoon),
      (icon: Icons.fact_check_outlined, label: l.coachTabCheckins, body: l.coachCheckinsSoon),
      (icon: Icons.forum_outlined, label: l.coachTabMessages, body: l.coachMessagesSoon),
      (icon: Icons.person_outline, label: l.coachTabYou, body: l.coachProfileSoon),
    ];

    final current = tabs[_tab];

    return Scaffold(
      // The default leading back arrow is the point: this is a place you go and come back from,
      // not a mode you are locked into.
      appBar: AppBar(title: Text(current.label)),
      // Every tab is real now (D-225, D-226): clients, the week's reviews, the conversations, and
      // where this account stands as a partner.
      body: switch (_tab) {
        0 => const _ClientsTab(),
        1 => const CheckInsTab(),
        2 => const ThreadsView(),
        _ => const CoachYouTab(),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          for (final tab in tabs) NavigationDestination(icon: Icon(tab.icon), label: tab.label),
        ],
      ),
    );
  }
}

/// What this coach has asked and nobody has answered yet.
///
/// NOT a client list. A coach with three open invites and no acceptances has no clients, and a
/// screen that blurred the two would tell them otherwise. The accepted roster is E6.
/// The Clients tab: the coach's dashboard (D-200).
///
/// Counts, who needs chasing, the roster, earnings and the referral code — all inside this one tab,
/// because `CLAUDE.md` rule 1 fixes the coach's five destinations and a Dashboard tab would be a
/// sixth. Adding one needs an ADR.
class _ClientsTab extends StatelessWidget {
  const _ClientsTab();

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(
      CoachDashboardController(coach: Get.find<CoachRepository>()),
      permanent: true,
    );

    return CoachDashboardPage(controller: controller);
  }
}

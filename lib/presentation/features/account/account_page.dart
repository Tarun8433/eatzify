import 'package:flutter/material.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/presentation/features/tab_scaffold.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// tabYou tab. docs/14 §1.
///
/// Currently renders the Empty state: nothing is wired to the API yet, and showing an empty state
/// is correct where showing a spinner forever would not be (CLAUDE.md rule 6).
class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TabScaffold(
      title: l10n.tabYou,
      subtitle: l10n.accountSubtitle,
      child: EmptyView(title: l10n.accountEmptyTitle, body: l10n.accountEmptyBody),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/domain/entities/session_role.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// D-269: on the You tab of each dashboard — go to the other one, and choose which one the app
/// opens on. Draws nothing unless the server lets this account switch.
class DashboardSwitchCard extends StatelessWidget {
  const DashboardSwitchCard({required this.current, super.key});

  /// The dashboard this card sits on; the row offers the other one.
  final DashboardMode current;

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<SessionController>()) return const SizedBox.shrink();
    final session = Get.find<SessionController>();
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final other = current == DashboardMode.mine ? DashboardMode.clients : DashboardMode.mine;

    return Obx(() {
      if (!session.canSwitchDashboard.value) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.swap_horiz, color: theme.colorScheme.primary),
                  title: Text(
                    other == DashboardMode.clients
                        ? l.dashboardSwitchToClients
                        : l.dashboardSwitchToMine,
                    style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    other == DashboardMode.clients
                        ? l.dashboardSwitchToClientsBody
                        : l.dashboardSwitchToMineBody,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => session.switchDashboard(other),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(l.dashboardOpenOn, style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              SegmentedButton<DashboardMode>(
                segments: [
                  ButtonSegment(value: DashboardMode.mine, label: Text(l.dashboardMyTracking)),
                  ButtonSegment(value: DashboardMode.clients, label: Text(l.dashboardMyClients)),
                ],
                selected: {session.defaultDashboard.value},
                onSelectionChanged: (picked) => session.setDefaultDashboard(picked.single),
              ),
            ],
          ),
        ),
      );
    });
  }
}

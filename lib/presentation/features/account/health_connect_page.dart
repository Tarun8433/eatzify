import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/health_metric.dart';
import 'package:health_pro/domain/repositories/health_repository.dart';
import 'package:health_pro/domain/usecases/sync_health.dart';
import 'package:health_pro/presentation/features/account/health_connect_controller.dart';
import 'package:health_pro/presentation/features/onboarding/enum_labels.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// "Health data" (D-215). Says exactly what is read and what is not, and is the one place a
/// health permission sheet may appear — always after a tap on it, never on a launch.
///
/// Every state keeps manual entry in view (rule 10): not connecting is a normal choice here, not a
/// problem to fix.
class HealthConnectPage extends StatelessWidget {
  const HealthConnectPage({super.key});

  /// Opens the screen. The controller is bound to the route, so it — and the resume observer it
  /// holds — goes away when the screen does.
  static Future<void>? open() => Get.to<void>(
    () => const HealthConnectPage(),
    binding: BindingsBuilder<void>(() {
      Get.lazyPut(
        () => HealthConnectController(
          health: Get.find<HealthRepository>(),
          sync: Get.find<SyncHealth>(),
        ),
      );
    }),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = Get.find<HealthConnectController>();

    return Scaffold(
      appBar: AppBar(title: Text(l.healthTitle)),
      body: Obx(
        () => switch (c.state.value) {
          Loading<HealthConnection>() => const LoadingView(),
          Failed<HealthConnection>(:final failure) => FailedView(failure: failure, onRetry: c.load),
          // Not produced today — both questions answer with a state — but a screen that cannot
          // say anything should still say manual entry works.
          Empty<HealthConnection>() => EmptyView(title: l.healthUnsupported),
          Ready<HealthConnection>(:final data) => _Body(controller: c, connection: data),
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller, required this.connection});

  final HealthConnectController controller;
  final HealthConnection connection;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final platform = SyncHealth.platformSource.label(l);

    return RefreshIndicator(
      onRefresh: controller.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          HintCard(icon: Icons.favorite_outline, text: l.healthExplainer(platform)),
          const SizedBox(height: AppSpacing.lg),
          _Status(controller: controller, connection: connection, platform: platform),
          const SizedBox(height: AppSpacing.lg),
          const _WhatIsRead(),
        ],
      ),
    );
  }
}

/// Where things stand, and the one action that moves them.
class _Status extends StatelessWidget {
  const _Status({required this.controller, required this.connection, required this.platform});

  final HealthConnectController controller;
  final HealthConnection connection;
  final String platform;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return switch (connection) {
      (availability: HealthAvailability.unsupported, permission: _) => HintCard(
        icon: Icons.phone_android_outlined,
        text: l.healthUnsupported,
      ),
      (availability: HealthAvailability.needsInstall, permission: _) => _ActionCard(
        body: l.healthNeedsInstall,
        action: l.healthInstall,
        controller: controller,
        onPressed: controller.install,
      ),
      (availability: HealthAvailability.ready, permission: HealthPermission.denied) => _ActionCard(
        body: l.healthDeniedBody,
        action: l.healthConnect(platform),
        controller: controller,
        onPressed: controller.syncNow,
      ),
      (availability: HealthAvailability.ready, :final permission) => _Connected(
        controller: controller,
        platform: platform,
        // iOS never says what was granted, so the screen says who decides instead of claiming.
        body: permission == HealthPermission.unknown ? l.healthUnknownBody : l.healthConnectedBody,
      ),
    };
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.body,
    required this.action,
    required this.controller,
    required this.onPressed,
  });

  final String body;
  final String action;
  final HealthConnectController controller;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(body, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.md),
          Obx(
            () => FilledButton(
              onPressed: controller.busy.value ? null : onPressed,
              child: Text(action),
            ),
          ),
        ],
      ),
    );
  }
}

class _Connected extends StatelessWidget {
  const _Connected({required this.controller, required this.platform, required this.body});

  final HealthConnectController controller;
  final String platform;
  final String body;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline, color: theme.colorScheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(l.healthConnectedTitle(platform), style: theme.textTheme.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(body, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.md),
          Obx(
            () => OutlinedButton(
              onPressed: controller.busy.value ? null : controller.syncNow,
              child: Text(controller.busy.value ? l.healthSyncing : l.healthSyncNow(platform)),
            ),
          ),
          Obx(() {
            final result = controller.lastSync.value;
            if (result == null) return const SizedBox.shrink();
            final text = healthSyncMessage(l, result);
            return Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(text, style: theme.textTheme.bodySmall),
            );
          }),
        ],
      ),
    );
  }
}

/// What a tapped sync says afterwards, on Home and here (D-218). A failure names what failed — the
/// phone's health store or the connection to Eatzify — because the advice differs.
String healthSyncMessage(AppLocalizations l, SyncHealthResult result) {
  final platform = SyncHealth.platformSource.label(l);
  return switch (result) {
    SyncHealthResult.written => l.healthSyncDone(platform),
    SyncHealthResult.unchanged || SyncHealthResult.nothingToWrite => l.healthSyncNothing(platform),
    SyncHealthResult.readFailed => l.healthSyncReadFailed(platform),
    SyncHealthResult.sendFailed => l.healthSyncSendFailed,
    SyncHealthResult.notPermitted => l.healthSyncNotPermitted(platform),
    SyncHealthResult.unavailable || SyncHealthResult.noWindow => l.healthSyncUnavailable,
  };
}

/// The whole list, in and out. Saying what is NOT read matters as much as what is.
class _WhatIsRead extends StatelessWidget {
  const _WhatIsRead();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.healthReadsTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          for (final metric in HealthMetric.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Icon(_iconFor(metric), color: theme.colorScheme.primary),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: Text(_labelFor(l, metric), style: theme.textTheme.bodyLarge)),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l.healthNotRead,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(HealthMetric metric) => switch (metric) {
    HealthMetric.steps => Icons.directions_walk,
    HealthMetric.activeEnergy => Icons.local_fire_department_outlined,
    HealthMetric.distance => Icons.route_outlined,
  };

  static String _labelFor(AppLocalizations l, HealthMetric metric) => switch (metric) {
    HealthMetric.steps => l.healthMetricSteps,
    HealthMetric.activeEnergy => l.healthMetricEnergy,
    HealthMetric.distance => l.healthMetricDistance,
  };
}

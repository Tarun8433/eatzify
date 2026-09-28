import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/privacy.dart';
import 'package:health_pro/domain/repositories/privacy_repository.dart';
import 'package:health_pro/presentation/features/account/privacy_controller.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// "Privacy & data" (docs/14 §6, docs/13 §3 and §9).
///
/// Three things on one screen, in this order: what we may do with your data, a copy of it, and the
/// way out. docs/13 §3 forbids dark patterns here — the toggles say plainly what switching one off
/// costs, and nothing asks twice with guilt copy.
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  static Future<void>? open() => Get.to<void>(
    () => const PrivacyPage(),
    binding: BindingsBuilder<void>(() {
      Get.lazyPut(() => PrivacyController(privacy: Get.find<PrivacyRepository>()));
    }),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = Get.find<PrivacyController>();

    return Scaffold(
      appBar: AppBar(title: Text(l.privacyTitle)),
      body: Obx(
        () => switch (c.state.value) {
          Loading<PrivacyState>() => const LoadingView(),
          Failed<PrivacyState>(:final failure) => FailedView(failure: failure, onRetry: c.load),
          // A person always has consents, even when every one of them is off — so this state is
          // unreachable in practice. Handled anyway rather than left to fall through.
          Empty<PrivacyState>() => EmptyView(
            title: l.privacyTitle,
            actionLabel: l.privacyRetry,
            onAction: c.load,
          ),
          Ready<PrivacyState>(:final data) => RefreshIndicator(
            onRefresh: () => c.load(quiet: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              children: [
                Text(l.privacyConsentsTitle, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                for (final consent in data.consents) ...[
                  _ConsentRow(consent: consent, controller: c),
                  const SizedBox(height: AppSpacing.sm),
                ],
                const SizedBox(height: AppSpacing.lg),
                _ExportCard(controller: c),
                const SizedBox(height: AppSpacing.lg),
                _DeleteCard(controller: c),
                Obx(
                  () => c.error.value == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.md),
                          child: Text(
                            // Rule 7: the server's own words.
                            c.error.value!,
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(color: AppColors.danger),
                          ),
                        ),
                ),
              ],
            ),
          ),
        },
      ),
    );
  }
}

/// One consent, its plain-language explanation, and what turning it off costs.
class _ConsentRow extends StatelessWidget {
  const _ConsentRow({required this.consent, required this.controller});

  final ConsentItem consent;
  final PrivacyController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final (title, body) = switch (consent.type) {
      'health_data_storage' => (l.privacyConsentHealth, l.privacyConsentHealthBody),
      'plan_generation' => (l.privacyConsentPlan, l.privacyConsentPlanBody),
      'marketing' => (l.privacyConsentMarketing, l.privacyConsentMarketingBody),
      // Rule 4: a key the app has not heard of is still never shown raw.
      _ => (l.privacyConsentOther, ''),
    };

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(body, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Obx(
            () => Switch(
              value: consent.granted,
              onChanged: controller.saving.value != null
                  ? null
                  : (granted) => controller.setConsent(consent.type, granted: granted),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportCard extends StatelessWidget {
  const _ExportCard({required this.controller});

  final PrivacyController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.privacyExportTitle, style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(l.privacyExportBody, style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.md),
          Obx(
            () => FilledButton(
              onPressed: controller.working.value ? null : controller.export,
              child: Text(l.privacyExportAction),
            ),
          ),
          Obx(() {
            final bundle = controller.bundle.value;
            if (bundle == null) return const SizedBox.shrink();

            // Counts, not contents: the point on screen is "this is what we hold", and printing a
            // year of food logs into a card helps nobody.
            final rows = <String>[
              for (final entry in bundle.entries)
                if (entry.value is List)
                  l.privacyExportRows(entry.key, '${(entry.value as List).length}'),
            ];

            return Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.privacyExportReady, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: AppSpacing.xs),
                  for (final row in rows)
                    Text(
                      row,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _DeleteCard extends StatelessWidget {
  const _DeleteCard({required this.controller});

  final PrivacyController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();

    return Obx(() {
      final pending = controller.pendingDeletion;

      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.privacyDeleteTitle, style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              pending == null ? l.privacyDeleteBody : l.privacyDeletePendingBody,
              style: theme.textTheme.bodySmall,
            ),
            if (pending?.executeAfter != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                l.privacyDeleteOn(DateFormat.yMMMd(locale).format(pending!.executeAfter!)),
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            if (pending == null)
              OutlinedButton(
                onPressed: controller.working.value ? null : () => _confirm(context, controller),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                child: Text(l.privacyDeleteAction),
              )
            else
              FilledButton(
                onPressed: controller.working.value ? null : controller.cancelDeletion,
                child: Text(l.privacyDeleteKeep),
              ),
          ],
        ),
      );
    });
  }

  /// One confirmation, because the action is irreversible after seven days — and exactly one,
  /// because docs/13 §3 rules out asking again with guilt copy.
  Future<void> _confirm(BuildContext context, PrivacyController controller) async {
    final l = AppLocalizations.of(context);

    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l.privacyDeleteConfirmTitle),
        content: Text(l.privacyDeleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(l.privacyDeleteConfirmNo),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(l.privacyDeleteConfirmYes),
          ),
        ],
      ),
    );

    if (yes ?? false) await controller.requestDeletion();
  }
}

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/coach_application.dart';
import 'package:health_pro/domain/repositories/coach_repository.dart';
import 'package:health_pro/presentation/features/coach/become_partner_controller.dart';
import 'package:health_pro/presentation/features/coach/become_partner_page.dart';
import 'package:health_pro/presentation/features/onboarding/enum_labels.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The coach's own You tab: where they stand as a partner, and the way back to their own account.
///
/// Deliberately thin. Earnings and the referral code live on the Clients tab (D-200), and a coach's
/// profile, plan and diary are the CLIENT app's — a coach is a client of their own app (D-174), so
/// this tab points there rather than building a second copy of it.
class CoachYouTab extends StatelessWidget {
  const CoachYouTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(BecomePartnerController(coach: Get.find<CoachRepository>()), permanent: true);

    return Obx(
      () => switch (c.state.value) {
        Loading<CoachApplication>() => const LoadingView(),
        Failed<CoachApplication>(:final failure) => FailedView(failure: failure, onRetry: c.load),
        // Never applied: the standing is "not a partner yet", which is a real answer and not an
        // error — the same screen still offers the way in.
        Empty<CoachApplication>() => const _Standing(application: null),
        Ready<CoachApplication>(:final data) => _Standing(application: data),
      },
    );
  }
}

class _Standing extends StatelessWidget {
  const _Standing({required this.application});

  final CoachApplication? application;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final app = application;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: [
        AppCard(
          accent: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_status(l, app), style: theme.textTheme.titleLarge),
              if (app != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(l.coachYouLevel('${app.level}'), style: muted),
                if (app.discipline case final discipline?) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(discipline.label(l), style: theme.textTheme.bodyMedium),
                ],
              ],
            ],
          ),
        ),
        // docs/12 §6's level 3, the only one that may ask a client for chat (D-235). Shown only to
        // a verified partner — before that there is nothing to agree to yet.
        if (app != null && app.isVerified) ...[
          const SizedBox(height: AppSpacing.lg),
          _CoachingCard(application: app),
        ],
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          height: AppSizes.primaryButton,
          child: FilledButton.icon(
            onPressed: () => Get.to<void>(() => const BecomePartnerPage()),
            icon: const Icon(Icons.badge_outlined),
            label: Text(l.coachYouManage),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: AppSizes.primaryButton,
          child: OutlinedButton.icon(
            // D-174: the coach surface was reached from the client's You tab, so leaving it is a
            // pop rather than another shell.
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
            label: Text(l.coachYouBack),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(l.coachYouBackBody, style: muted),
      ],
    );
  }

  /// Rule 4: a status is a wire value and l10n on screen. The screen never claims verified — that
  /// is an admin's decision (docs/09 §9).
  String _status(AppLocalizations l, CoachApplication? app) => switch (app?.status) {
    null => l.coachYouNotYet,
    'verified' => l.coachYouVerified,
    'submitted' || 'under_review' => l.coachYouPending,
    _ => l.coachYouNotYet,
  };
}

/// Where a verified partner stands against level 3: the agreement to accept, the client still to
/// say yes, or done. Three states, each saying what happens next rather than what is missing.
class _CoachingCard extends StatelessWidget {
  const _CoachingCard({required this.application});

  final CoachApplication application;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = Get.find<BecomePartnerController>();

    final (title, body) = application.isCoachingPartner
        ? (l.coachingPartnerTitle, l.coachingPartnerBody)
        : application.coachingAgreementAccepted
        ? (l.coachingWaitingTitle, l.coachingWaitingBody)
        : (l.coachingAgreementTitle, l.coachingAgreementBody);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(body, style: theme.textTheme.bodySmall),
          if (application.canAcceptCoachingAgreement) ...[
            const SizedBox(height: AppSpacing.md),
            Obx(
              () => FilledButton(
                onPressed: c.saving.value ? null : c.acceptCoachingAgreement,
                child: Text(l.coachingAgreementAccept),
              ),
            ),
          ],
          Obx(
            () => c.error.value == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    // Rule 7: the server's words, verbatim.
                    child: Text(
                      c.error.value!,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

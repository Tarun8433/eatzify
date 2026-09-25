import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/format/rupees.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/section_header.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/coach_client.dart';
import 'package:health_pro/domain/entities/coach_dashboard.dart';
import 'package:health_pro/domain/entities/onboarding_enums.dart';
import 'package:health_pro/presentation/features/coach/client_detail_page.dart';
import 'package:health_pro/presentation/features/coach/dashboard_controller.dart';
import 'package:health_pro/presentation/features/coach/dashboard_widgets.dart';
import 'package:health_pro/presentation/features/coach/data_access_page.dart' show scopeLabel;
import 'package:health_pro/presentation/features/coach/invite_client_sheet.dart';
import 'package:health_pro/presentation/features/onboarding/enum_labels.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The coach's Clients tab — what a trainer, nutritionist or doctor opens their day on (D-200).
///
/// Inside the Clients tab rather than a tab of its own: `CLAUDE.md` rule 1 fixes the coach's five
/// destinations, and a Dashboard tab would be a sixth.
///
/// **Nothing here is computed.** Every count, percentage and status arrives decided by the server
/// (rule 2), already filtered to what each client allowed. A widget that worked out who was at risk
/// would be a second place the rule lived.
class CoachDashboardPage extends StatelessWidget {
  const CoachDashboardPage({required this.controller, super.key});

  final CoachDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Obx(
      () => switch (controller.state.value) {
        Loading<CoachDesk>() => const LoadingView(),
        // docs/14 §6 asks an empty state for ONE clear action. With nobody invited and nobody
        // accepted, there is exactly one thing to do.
        Empty<CoachDesk>() => Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: EmptyView(
            title: l.coachDashEmptyTitle,
            body: l.coachDashEmptyBody,
            actionLabel: l.coachInviteAction,
            onAction: () async {
              await InviteClientSheet.show(context);
              await controller.load(quiet: true);
            },
          ),
        ),
        Failed<CoachDesk>(:final failure) => FailedView(failure: failure, onRetry: controller.load),
        Ready<CoachDesk>(:final data) => RefreshIndicator(
          onRefresh: () => controller.load(quiet: true),
          child: _Body(desk: data, controller: controller),
        ),
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.desk, required this.controller});

  final CoachDesk desk;
  final CoachDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: [
        _Tiles(desk: desk),
        const SizedBox(height: AppSpacing.lg),

        if (desk.summary.totalClients > 0 || desk.summary.pendingInvites > 0)
          _TodaysWork(summary: desk.summary),

        // The people who need chasing, above the people who do not. docs/12 §9 calls this the most
        // valuable widget a coach gets, so it sits where the eye lands first.
        if (desk.summary.needsAttention.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(title: l.coachDashNeedsAttention),
          for (final client in desk.summary.needsAttention)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: CoachClientCard(client: client),
            ),
        ],

        if (desk.clients.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(title: l.coachDashYourClients),
          for (final client in desk.clients)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: CoachClientCard(client: client),
            ),
        ],

        // An invite is a question and a client is an answered one. Below the roster, because the
        // people who said yes are who a coach opened this to work with.
        if (oneRowPerPerson(desk.invites) case final waiting when waiting.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(title: l.coachInvitedTitle),
          for (final invite in waiting)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: InvitedCard(invite: invite),
            ),
        ],

        // An affiliate reaches no scope at all, so their roster is empty however many people they
        // referred. Saying why beats a screen that looks broken.
        if (desk.clients.isEmpty && desk.summary.pendingInvites > 0) ...[
          const SizedBox(height: AppSpacing.lg),
          HintCard(icon: Icons.lock_outline, title: l.coachDashLocked, text: l.coachDashLockedBody),
        ],

        if (desk.earnings case final earnings?) ...[
          const SizedBox(height: AppSpacing.lg),
          _Earnings(earnings: earnings),
        ],

        if (desk.referral case final referral?) ...[
          const SizedBox(height: AppSpacing.lg),
          _Referral(referral: referral),
        ],

        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          height: AppSizes.primaryButton,
          child: FilledButton.icon(
            onPressed: () async {
              await InviteClientSheet.show(context);
              await controller.load(quiet: true);
            },
            icon: const Icon(Icons.person_add_alt),
            label: Text(l.coachInviteAction),
          ),
        ),
      ],
    );
  }
}

/// The four figures, in a row that scrolls when it has to.
///
/// The layout technique is Home's nutrient row: compute an even share, take the larger of that and
/// the minimum, and always wrap in a horizontal scroller. When the even share wins nothing exceeds
/// the viewport, so it simply does not scroll — one branch rather than two.
class _Tiles extends StatelessWidget {
  const _Tiles({required this.desk});

  final CoachDesk desk;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final earnings = desk.earnings;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // Room for the cards' shadow inside the scroll clip, which would otherwise be sliced off.
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CoachStatTile(
              icon: Icons.group_outlined,
              tint: AppColors.success,
              value: '${desk.summary.totalClients}',
              label: l.coachDashTotalClients,
            ),
            const SizedBox(width: AppSpacing.md),
            CoachStatTile(
              icon: Icons.person_outline,
              tint: AppColors.macroFat,
              value: '${desk.summary.activeClients}',
              label: l.coachDashActiveClients,
            ),
            const SizedBox(width: AppSpacing.md),
            CoachStatTile(
              icon: Icons.notifications_active_outlined,
              tint: AppColors.warning,
              value: '${desk.summary.atRiskClients}',
              label: l.coachDashNeedsAttention,
            ),
            const SizedBox(width: AppSpacing.md),
            CoachStatTile(
              icon: Icons.currency_rupee,
              tint: AppColors.macroCarb,
              // Paise on the wire, rupees on the tile — the one place the two units meet here.
              value: Rupees.format((earnings?.totalPaise ?? 0) ~/ 100),
              label: l.coachDashEarningsThisMonth,
              trendPct: earnings?.pctChange,
              trendCaption: l.coachDashVsLastMonth,
            ),
          ],
        ),
      ),
    );
  }
}

class _TodaysWork extends StatelessWidget {
  const _TodaysWork({required this.summary});

  final CoachDashboard summary;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              l.coachDashTodaysWork,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          IntrinsicHeight(
            child: Row(
              children: [
                CoachTask(
                  icon: Icons.schedule_outlined,
                  tint: AppColors.warning,
                  count: summary.atRiskClients,
                  label: l.coachDashNoLogs,
                ),
                const VerticalDivider(width: 1),
                CoachTask(
                  icon: Icons.mark_email_unread_outlined,
                  tint: AppColors.macroFat,
                  count: summary.pendingInvites,
                  label: l.coachDashPendingInvites,
                ),
                const VerticalDivider(width: 1),
                CoachTask(
                  icon: Icons.autorenew,
                  tint: AppColors.macroCarb,
                  count: summary.renewalsDue30d,
                  label: l.coachDashRenewalsDue,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One client, as much as the grant allows, and a way in.
///
/// The card shows what the server sent and nothing more. A field the client did not share draws no
/// row at all — not a dash, not a zero — because a blank is a boundary, not a gap in their profile.
class CoachClientCard extends StatelessWidget {
  const CoachClientCard({required this.client, super.key});

  final CoachClient client;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final goal = enumFromWire(Goal.values, client.goal ?? '', (e) => e.wire);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: () =>
          Get.to<void>(() => ClientDetailPage(clientUserId: client.userId, name: client.name)),
      child: Row(
        children: [
          ExcludeSemantics(
            child: CircleAvatar(
              radius: AppSpacing.xl,
              backgroundColor: scheme.surfaceContainerHighest,
              child: Icon(Icons.person, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        client.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (client.tier case final tier?) ...[
                      const SizedBox(width: AppSpacing.sm),
                      BadgePill(label: coachTierLabel(l, tier), tint: AppColors.macroCarb),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  // The permissions NAMED, in the same words the client read when they granted
                  // them, alongside what those permissions actually revealed. "3 permissions"
                  // tells a coach nothing about what they may open.
                  [
                    if (client.ageYears case final years?) '$years',
                    if (client.ageBand case final band?) band,
                    if (goal != null) goal.label(l),
                    ...client.scopes.map((s) => scopeLabel(l, s)),
                  ].join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                if (client.hasMetrics) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _Metrics(client: client),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (client.adherencePct != null || client.hasMetrics)
            AdherenceRing(pct: client.adherencePct),
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.client});

  final CoachClient client;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        BadgePill(label: coachStatusLabel(l, client.status), tint: coachStatusTint(client.status)),
        if (client.weightKg case final kg?)
          Text(
            // A gain reads in the same voice as a loss: no colour, no arrow. docs/05 §6.
            client.weightChange30d == null
                ? l.accountWeightValue(kg.toStringAsFixed(1))
                : '${l.accountWeightValue(kg.toStringAsFixed(1))}  '
                      '(${client.weightChange30d! >= 0 ? '+' : ''}'
                      '${client.weightChange30d!.toStringAsFixed(1)})',
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        // Absent at zero. docs/05 §6 — "0 day streak" is the failure banner the rules exist to
        // prevent, and a streak is worth showing only once there is one.
        if (client.streakDays case final days? when days > 0)
          Text(
            '${l.coachStreak}  ${l.coachStreakDays(days)}',
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

class _Earnings extends StatelessWidget {
  const _Earnings({required this.earnings});

  final CoachEarnings earnings;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.coachDashEarnings,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (earnings.isEmpty)
            Text(
              l.coachDashNoEarnings,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  Rupees.format(earnings.totalPaise ~/ 100),
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (earnings.pctChange case final pct?)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: TrendLine(pct: pct, caption: l.coachDashVsLastMonth),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _Breakdown(label: l.coachDashClientPayments, paise: earnings.clientPaymentsPaise),
            _Breakdown(label: l.coachDashBonus, paise: earnings.bonusPaise),
            _Breakdown(label: l.coachDashOther, paise: earnings.otherPaise),
          ],
        ],
      ),
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.label, required this.paise});

  final String label;
  final int paise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Text(
            Rupees.format(paise ~/ 100),
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// The link and the code, either of which brings somebody in.
///
/// Says what the partner earns from it in the same breath. docs/12 §6 forbids implying an
/// accreditation, and it is equally worth not implying an earning that does not exist.
class _Referral extends StatelessWidget {
  const _Referral({required this.referral});

  final CoachReferral referral;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AppCard(
      accent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.coachDashReferralTitle,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l.coachDashReferralBody,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          _CopyRow(label: referral.code, value: referral.code),
          const SizedBox(height: AppSpacing.sm),
          _CopyRow(label: referral.url, value: referral.url),
        ],
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: value));
            if (!context.mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l.coachDashReferralCopied)));
          },
          icon: const Icon(Icons.copy, size: AppSpacing.lg),
          label: Text(l.coachDashCopy),
        ),
      ],
    );
  }
}

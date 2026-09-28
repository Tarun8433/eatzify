import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/coach_discipline.dart';
import 'package:health_pro/domain/entities/coach_invite.dart';
import 'package:health_pro/domain/entities/data_access.dart';
import 'package:health_pro/presentation/features/coach/data_access_controller.dart';
import 'package:health_pro/presentation/features/onboarding/enum_labels.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// "Who can see my data" — docs/10 §3 names this screen and requires it to be ONE screen with a
/// one-tap revoke.
///
/// It lists paused grants too. What access used to exist is part of the answer, and a list that
/// quietly forgets a revoked coach cannot be audited by the person it belongs to.
class DataAccessPage extends StatelessWidget {
  const DataAccessPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = Get.find<DataAccessController>();

    return Scaffold(
      appBar: AppBar(title: Text(l.accessTitle)),
      body: Obx(
        () => switch (c.state.value) {
          Loading<List<DataAccess>>() => const LoadingView(),
          Failed<List<DataAccess>>(:final failure) => FailedView(failure: failure, onRetry: c.load),
          // Empty is a real answer here, not a failure — most people have given nobody anything —
          // so it renders inside the page rather than replacing it. It used to swap the whole body
          // for a centred block, which left an open request stranded above a screen that said
          // "nobody can see your data".
          Empty<List<DataAccess>>() => _Composed(controller: c, granted: const []),
          Ready<List<DataAccess>>(:final data) => _Composed(controller: c, granted: data),
        },
      ),
    );
  }
}

/// The whole screen as one scroll: what you were asked, then what you have given.
///
/// One list rather than a fixed section over a scrolling one, because the two halves grow
/// independently — two open requests at 200 % text used to squeeze the granted list into a strip.
class _Composed extends StatelessWidget {
  const _Composed({required this.controller, required this.granted});

  final DataAccessController controller;
  final List<DataAccess> granted;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

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
          // Shown in every state, including the empty one. It explains the rule the screen runs
          // on, and somebody who has granted nothing is exactly who has not read it yet.
          HintCard(icon: Icons.lock_outline, text: l.accessExplainer),
          const SizedBox(height: AppSpacing.lg),

          Obx(() {
            final invites = controller.invites;
            if (invites.isEmpty) return const SizedBox.shrink();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Head(title: l.accessRequestsTitle, count: invites.length),
                const SizedBox(height: AppSpacing.md),
                for (final invite in invites)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: _InviteCard(invite: invite, controller: controller),
                  ),
                const SizedBox(height: AppSpacing.lg),
              ],
            );
          }),

          _Head(title: l.accessGrantedTitle, count: granted.length),
          const SizedBox(height: AppSpacing.md),

          if (granted.isEmpty)
            // Reassuring, not an error: nobody having access is the healthy state.
            HintCard(
              icon: Icons.shield_outlined,
              title: l.accessNobodyTitle,
              text: l.accessNobodyBody,
            )
          else
            for (final row in granted)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _AccessCard(access: row, controller: controller),
              ),

          // Revoke, accept and decline all park their failure in `error`, and nothing on this
          // screen was showing it — a declined request the server refused looked exactly like one
          // that went through. Rule 7: the server's words, verbatim.
          _ErrorLine(controller: controller),
        ],
      ),
    );
  }
}

/// A heading with its count, so each half says how big it is before any card is read.
class _Head extends StatelessWidget {
  const _Head({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            '$count',
            style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.invite, required this.controller});

  final CoachInvite invite;
  final DataAccessController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Who is asking. "Partner #25" was what this said before, and nobody can decide whether
          // to hand over their weight and steps to a number.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: AppSpacing.lg,
                backgroundImage: invite.coachPhotoUrl == null
                    ? null
                    : NetworkImage(invite.coachPhotoUrl!),
                child: invite.coachPhotoUrl == null ? const Icon(Icons.person) : null,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invite.coachName ?? l.accessRequestUnnamed,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    // Self-declared, and it says so by sitting apart from the verified line below.
                    if (_discipline(l, invite.coachDiscipline) case final what?)
                      Text(
                        what,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: AppSpacing.xs),
                    _VerificationLine(invite: invite),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(l.accessRequestsBody, style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.sm),

          // The same named scopes the grant list shows. A request answered without naming what it
          // asks for is not consent.
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final scope in invite.scopes)
                Chip(label: Text(scopeLabel(l, scope)), visualDensity: VisualDensity.compact),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          Obx(() {
            final busy = controller.answering.value == invite.id;

            // Decline first and quieter, accept last and solid: the destructive-sounding option is
            // not the emphasised one, and neither is pre-selected for them.
            return Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: busy ? null : () => controller.decline(invite.id),
                  child: Text(l.accessDecline),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: busy ? null : () => controller.accept(invite.id),
                  child: Text(busy ? l.accessAnswering : l.accessAccept),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

/// Self-declared discipline, through l10n (rule 4). Null when they never answered.
String? _discipline(AppLocalizations l, String? wire) {
  if (wire == null) return null;
  return enumFromWire(CoachDiscipline.values, wire, (e) => e.wire)?.label(l);
}

/// Verified or not, and — when a human did check — exactly what they checked.
///
/// doc 00 §8: Eatzify does not accredit anybody. So the badge never stands alone: the server's own
/// sentence about what verification means travels with it, verbatim (rule 7, docs/12 §6).
class _VerificationLine extends StatelessWidget {
  const _VerificationLine({required this.invite});

  final CoachInvite invite;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (!invite.coachVerified) {
      return Text(
        l.accessNotVerifiedBadge,
        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }

    final checked = invite.coachVerifiedAttributes
        .map((a) => _attribute(l, a))
        .where((a) => a.isNotEmpty)
        .join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.verified, size: AppSpacing.md, color: theme.colorScheme.primary),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                l.accessVerifiedBadge,
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
              ),
            ),
          ],
        ),
        if (checked.isNotEmpty)
          Text(
            l.accessVerifiedChecked(checked),
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        if (invite.whatVerificationMeans.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            invite.whatVerificationMeans,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  /// rule 4 again: the server sends wire values, the screen shows words.
  String _attribute(AppLocalizations l, String wire) => switch (wire) {
    'identity' => l.accessVerifiedIdentity,
    'qualification_document' => l.accessVerifiedQualification,
    _ => wire,
  };
}

/// CLAUDE.md rule 4: a scope is a wire value and l10n on screen. Shared by both cards — the words
/// a person accepts must be the same words they later read back.
String scopeLabel(AppLocalizations l, String scope) => switch (scope) {
  'basic' => l.accessScopeBasic,
  'progress' => l.accessScopeProgress,
  'plan_view' => l.accessScopePlanView,
  'plan_edit' => l.accessScopePlanEdit,
  'chat' => l.accessScopeChat,
  'health_conditions' => l.accessScopeConditions,
  _ => scope,
};

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.controller});

  final DataAccessController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Obx(() {
      final message = controller.error.value;
      if (message == null) return const SizedBox.shrink();

      return Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
        child: Text(
          message,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
        ),
      );
    });
  }
}

class _AccessCard extends StatelessWidget {
  const _AccessCard({required this.access, required this.controller});

  final DataAccess access;
  final DataAccessController controller;

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
              Expanded(
                child: Text(
                  l.accessPartner(access.coachUserId),
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (!access.isActive)
                Text(
                  l.accessEnded,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Named, not counted. "3 permissions" tells somebody nothing about what they gave away.
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final scope in access.scopes)
                Chip(label: Text(scopeLabel(l, scope)), visualDensity: VisualDensity.compact),
            ],
          ),

          if (access.isActive) ...[
            const SizedBox(height: AppSpacing.sm),
            Obx(() {
              final busy = controller.revoking.value == access.coachUserId;

              // One tap. No confirmation dialog: docs/10 §3 forbids a retention dark pattern, and
              // "are you sure you want to stop sharing your health data" is the shape one takes.
              return TextButton(
                onPressed: busy ? null : () => controller.revoke(access.coachUserId),
                child: Text(busy ? l.accessRevoking : l.accessRevoke),
              );
            }),
          ],
        ],
      ),
    );
  }
}

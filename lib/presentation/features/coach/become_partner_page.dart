import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_assets.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/coach_application.dart';
import 'package:health_pro/domain/entities/coach_discipline.dart';
import 'package:health_pro/presentation/features/coach/become_partner_controller.dart';
import 'package:health_pro/presentation/features/onboarding/enum_labels.dart';
import 'package:health_pro/presentation/features/onboarding/widgets/choice_tile.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:image_picker/image_picker.dart';

/// Coach onboarding, docs/12 §6.
///
/// One screen rather than a wizard, because the steps are a LADDER and the applicant needs to see
/// where they are on it: agreement, then documents, then a human. A wizard hides the last step,
/// which is the one that takes days.
///
/// The screen never claims verified. Level 2 is a decision an admin makes
/// (`POST /admin/coaches/{id}/verify`, docs/09 §9), and this surface can only reach "submitted".
class BecomePartnerPage extends StatelessWidget {
  const BecomePartnerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<BecomePartnerController>();

    return Scaffold(
      // No title in the bar: the hero says "Become a partner" in 32 pt right under it, and the
      // same words twice in the same viewport is chrome competing with content. The back arrow is
      // what the bar is actually for here.
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Obx(
        () => switch (c.state.value) {
          Loading<CoachApplication>() => const LoadingView(),
          // Never applied. The offer to start is the single action docs/14 §6 asks an empty state
          // for, and starting is just accepting the agreement.
          Empty<CoachApplication>() => _Intro(controller: c),
          Failed<CoachApplication>(:final failure) => FailedView(failure: failure, onRetry: c.load),
          Ready<CoachApplication>(:final data) => _Progress(application: data, controller: c),
        },
      ),
    );
  }
}

/// What a partner is, and the one thing to do about it.
class _Intro extends StatelessWidget {
  const _Intro({required this.controller});

  final BecomePartnerController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () => controller.load(quiet: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(l.partnerIntroTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Text(l.partnerIntroBody, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.lg),
          HintCard(icon: Icons.info_outline, text: l.partnerAgreementNote),
          const SizedBox(height: AppSpacing.xl),
          Obx(
            () => FilledButton(
              onPressed: controller.saving.value ? null : controller.acceptAgreement,
              child: Text(l.partnerAcceptAgreement),
            ),
          ),
          _ErrorLine(controller: controller),
        ],
      ),
    );
  }
}

/// The headline and the trainer beside it (D-185).
///
/// The art carries its own "Make an impact" lettering, so it is excluded from semantics: a screen
/// reader that announced it would read the slogan on top of the headline it sits next to. It is
/// also the reason the illustration is not mirrored in RTL — flipping baked-in text is worse than
/// leaving it.
class _PartnerHero extends StatelessWidget {
  const _PartnerHero();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Below this the art stops earning its width and the headline gets the row to itself —
        // the same rule the onboarding heroes use (rule 12: survive 200 % text).
        final stacked =
            constraints.maxWidth < AppSizes.heroBreakpoint ||
            MediaQuery.textScalerOf(context).scale(1) >= AppSizes.heroStackTextScale;

        final words = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Two lines, the second in the brand colour — the reference's emphasis, built from
            // one l10n string split on its own space so translations that reorder it still work.
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '${_firstWords(l.partnerHeroTitle)}\n'),
                  TextSpan(
                    text: _lastWord(l.partnerHeroTitle),
                    style: TextStyle(color: theme.colorScheme.primary),
                  ),
                ],
              ),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.05,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l.partnerHeroBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );

        final art = ExcludeSemantics(
          child: Image.asset(
            AppAssets.partnerHero,
            fit: BoxFit.contain,
            // Decorative: if it fails to decode the screen must still be usable.
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              words,
              const SizedBox(height: AppSpacing.md),
              SizedBox(height: 150, width: double.infinity, child: art),
            ],
          );
        }

        return Row(
          children: [
            Expanded(flex: 5, child: words),
            const SizedBox(width: AppSpacing.sm),
            Expanded(flex: 4, child: SizedBox(height: 168, child: art)),
          ],
        );
      },
    );
  }
}

/// "Become a partner" -> "Become a". Everything but the final word.
String _firstWords(String title) {
  final parts = title.trim().split(' ');
  return parts.length < 2 ? title : parts.sublist(0, parts.length - 1).join(' ');
}

/// "Become a partner" -> "partner".
String _lastWord(String title) => title.trim().split(' ').last;

/// The ladder, with the applicant's position on it.
class _Progress extends StatelessWidget {
  const _Progress({required this.application, required this.controller});

  final CoachApplication application;
  final BecomePartnerController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return RefreshIndicator(
      // A reviewer's verdict lands on the server, not in the app — pulling is how an applicant
      // who has been waiting checks for it.
      onRefresh: () => controller.load(quiet: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        children: [
          const _PartnerHero(),
          const SizedBox(height: AppSpacing.lg),

          // First rung, and the only one the applicant may revise. Onboarding asked the same
          // question and kept nothing, so this row is where the answer lives and where it changes.
          _Step(
            index: 1,
            done: application.discipline != null,
            title: l.partnerStepDiscipline,
            body: application.discipline?.label(l) ?? l.partnerStepDisciplineBody,
            icon: Icons.person_outline,
            tint: AppColors.success,
            // A reviewer checks the documents AGAINST this, so it stops being the applicant's to
            // change the moment one of them picks the application up.
            onTap: application.isWaitingForReview
                ? null
                : () => _pickDiscipline(context, controller, application),
          ),
          _Step(
            index: 2,
            done: application.agreementAccepted,
            title: l.partnerStepAgreement,
            body: l.partnerStepAgreementBody,
            icon: Icons.description_outlined,
            tint: AppColors.info,
          ),
          // Tappable, because an unchecked circle with no way to check it is not a step — it is a
          // status row pretending to be one, which is what shipped first.
          _Step(
            index: 3,
            done: application.hasIdDocument,
            title: l.partnerStepId,
            body: application.hasIdDocument ? l.partnerDocumentOnFile : l.partnerStepIdBody,
            icon: Icons.badge_outlined,
            tint: AppColors.macroCarb,
            onTap: application.isWaitingForReview
                ? null
                : () => _pick(context, controller, isIdDocument: true),
          ),
          _Step(
            index: 4,
            done: application.hasQualificationDocument,
            title: l.partnerStepQualification,
            body: application.hasQualificationDocument
                ? l.partnerDocumentOnFile
                : l.partnerStepQualificationBody,
            icon: Icons.workspace_premium_outlined,
            tint: AppColors.warning,
            onTap: application.isWaitingForReview
                ? null
                : () => _pick(context, controller, isIdDocument: false),
          ),
          const SizedBox(height: AppSpacing.lg),

          // docs/12 §6: publish exactly what verification means. Server-authored (rule 7), shown
          // wherever the badge or the promise of one appears.
          HintCard(
            icon: Icons.verified_outlined,
            title: l.partnerWhatVerificationMeans,
            text: application.whatVerificationMeans,
          ),
          const SizedBox(height: AppSpacing.lg),

          if (application.isVerified)
            // Nothing left to submit. The button used to survive into this state and the server
            // refused it — an enabled button whose only outcome is an error.
            HintCard(icon: Icons.verified, text: l.partnerVerified)
          else if (application.isWaitingForReview)
            HintCard(icon: Icons.hourglass_top, text: l.partnerInReview)
          else if (application.rejectionReason case final reason?)
            // Rule 7: the server's own words, never the app's summary of them.
            HintCard.important(icon: Icons.error_outline, title: l.partnerNotApproved, text: reason)
          else
            Obx(() {
              // Read FIRST. `canSubmit` is a plain bool, so `canSubmit && !saving.value`
              // short-circuits before the observable is touched and Obx throws for having
              // nothing to watch — a disabled button that crashes the screen it is on.
              final busy = controller.saving.value;

              return SizedBox(
                height: AppSizes.primaryButton,
                child: FilledButton(
                  onPressed: application.canSubmit && !busy ? controller.submit : null,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(l.partnerSubmit),
                      const SizedBox(width: AppSpacing.sm),
                      const Icon(Icons.arrow_forward, size: AppSpacing.lg),
                    ],
                  ),
                ),
              );
            }),

          _ErrorLine(controller: controller),
        ],
      ),
    );
  }
}

/// Where the document comes from. A photo of a certificate is the common case, and a scan already
/// in the gallery is the other one; nothing else is worth a third option.
Future<void> _pick(
  BuildContext context,
  BecomePartnerController controller, {
  required bool isIdDocument,
}) async {
  final l = AppLocalizations.of(context);

  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(l.partnerDocumentCamera),
            onTap: () => Navigator.of(sheet).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(l.partnerDocumentGallery),
            onTap: () => Navigator.of(sheet).pop(ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return;

  // Capped like the profile photo: a document has to be READABLE, not archival, and a 12 MP
  // certificate is a slow upload on the connection most of these arrive over.
  final picked = await ImagePicker().pickImage(
    source: source,
    maxWidth: 2000,
    maxHeight: 2000,
    imageQuality: 85,
  );
  if (picked == null) return;

  await controller.uploadDocument(
    filePath: picked.path,
    fileName: picked.name,
    isIdDocument: isIdDocument,
  );
}

/// The question, and the four answers to it.
///
/// A sheet rather than a screen: it is one question with a short list, and the applicant is in the
/// middle of a ladder they should not lose their place on.
Future<void> _pickDiscipline(
  BuildContext context,
  BecomePartnerController controller,
  CoachApplication application,
) async {
  final picked = await showModalBottomSheet<CoachDiscipline>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) {
      final l = AppLocalizations.of(sheetContext);
      final theme = Theme.of(sheetContext);

      return SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.partnerDisciplineTitle,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final discipline in CoachDiscipline.values)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: ChoiceTile(
                  label: discipline.label(l),
                  icon: discipline.icon,
                  selected: application.discipline == discipline,
                  onTap: () => Navigator.of(sheetContext).pop(discipline),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            // Says how long the answer stays theirs, before they give one — docs/12 §6 forbids
            // implying accreditation, and a question with no stated consequence invites a guess.
            HintCard(icon: Icons.info_outline, text: l.partnerDisciplineNote),
          ],
        ),
      );
    },
  );

  if (picked == null || picked == application.discipline) return;
  await controller.setDiscipline(picked);
}

class _Step extends StatelessWidget {
  const _Step({
    required this.index,
    required this.done,
    required this.title,
    required this.body,
    required this.icon,
    required this.tint,
    this.onTap,
  });

  /// 1-based. Printed as "01" — the reference numbers the rungs, and a ladder whose steps are not
  /// numbered is just a list of cards.
  final int index;
  final bool done;
  final String title;
  final String body;
  final IconData icon;

  /// The icon tile's colour. Each rung gets its own so the four are distinguishable at a glance
  /// rather than being one repeated shape.
  final Color tint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        onTap: onTap,
        child: Row(
          children: [
            // The number, or a tick once the rung is behind them. Same box either way, so the
            // rows do not shift as the applicant completes them.
            SizedBox(
              width: 34,
              child: done
                  ? Icon(Icons.check_circle, size: 22, color: theme.colorScheme.primary)
                  : Text(
                      index.toString().padLeft(2, '0'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Container(
              height: 46,
              width: 46,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.tile),
              ),
              child: Icon(icon, size: 22, color: tint),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // Only where tapping does something. A chevron on a locked row promises a screen that
            // will not open.
            if (enabled) ...[
              const SizedBox(width: AppSpacing.sm),
              Container(
                height: 30,
                width: 30,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Rule 7: whatever the server refused with, verbatim.
class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.controller});

  final BecomePartnerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Obx(() {
      final message = controller.error.value;
      if (message == null) return const SizedBox.shrink();

      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: Text(
          message,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
        ),
      );
    });
  }
}

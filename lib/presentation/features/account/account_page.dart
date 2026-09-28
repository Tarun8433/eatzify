import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Condition;
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/progress_ring.dart';
import 'package:health_pro/core/widgets/section_header.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/profile_view.dart';
import 'package:health_pro/domain/entities/session_role.dart';
import 'package:health_pro/domain/repositories/billing_repository.dart';
import 'package:health_pro/domain/repositories/chat_repository.dart';
import 'package:health_pro/domain/repositories/coach_repository.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';
import 'package:health_pro/domain/repositories/notifications_repository.dart';
import 'package:health_pro/domain/repositories/plan_repository.dart';
import 'package:health_pro/domain/repositories/privacy_repository.dart';
import 'package:health_pro/domain/repositories/profile_repository.dart';
import 'package:health_pro/domain/repositories/tickets_repository.dart';
import 'package:health_pro/domain/usecases/plan_reminders.dart';
import 'package:health_pro/domain/usecases/sync_health.dart';
import 'package:health_pro/presentation/features/account/account_controller.dart';
import 'package:health_pro/presentation/features/account/edit_sheets.dart';
import 'package:health_pro/presentation/features/account/health_connect_page.dart';
import 'package:health_pro/presentation/features/account/invite_friends.dart';
import 'package:health_pro/presentation/features/account/notifications_controller.dart';
import 'package:health_pro/presentation/features/coach/chat_page.dart';
import 'package:health_pro/presentation/features/account/notifications_page.dart';
import 'package:health_pro/presentation/features/account/privacy_page.dart';
import 'package:health_pro/presentation/features/account/profile_details_sheet.dart';
import 'package:health_pro/presentation/features/account/profile_frame.dart';
import 'package:health_pro/presentation/features/account/reminders_page.dart';
import 'package:health_pro/presentation/features/account/tickets_page.dart';
import 'package:health_pro/presentation/features/billing/subscription_page.dart';
import 'package:health_pro/presentation/features/coach/become_partner_controller.dart';
import 'package:health_pro/presentation/features/coach/become_partner_page.dart';
import 'package:health_pro/presentation/features/coach/data_access_controller.dart';
import 'package:health_pro/presentation/features/coach/data_access_page.dart';
import 'package:health_pro/presentation/features/gym/gym_page.dart';
import 'package:health_pro/presentation/features/tab_scaffold.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/coach_shell.dart';
import 'package:health_pro/presentation/shell/nav_controller.dart';
import 'package:health_pro/presentation/shell/walking_man.dart';
import 'package:intl/intl.dart';

/// tabYou tab. docs/14 §1. All four states per CLAUDE.md rule 6.
class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = Get.put(
      AccountController(
        profiles: Get.find<ProfileRepository>(),
        plans: Get.find<PlanRepository>(),
        diary: Get.isRegistered<DiaryRepository>() ? Get.find<DiaryRepository>() : null,
        measurements: Get.isRegistered<MeasurementsRepository>()
            ? Get.find<MeasurementsRepository>()
            : null,
        session: Get.isRegistered<SessionController>() ? Get.find<SessionController>() : null,
        reminders: Get.isRegistered<RefreshReminders>() ? Get.find<RefreshReminders>() : null,
      ),
      permanent: true,
    );

    // No sheet, no hole (D-152) — the page works exactly like Home: it paints no background of
    // its own, so the walker and his stage art show through wherever the hero leaves room, and
    // the cards pass OVER him the moment the list scrolls. The mock's "blob" was never a cut-out;
    // it is the stage art itself. The LayoutBuilder's box is the shell's body: exactly the
    // coordinate space `WalkingMan.boundsIn` answers in (D-63).
    return LayoutBuilder(
      builder: (context, body) {
        final man = WalkingMan.boundsAt(body.biggest, ClientTab.you);
        return _content(context, c, l10n, man.bottom, body.maxHeight);
      },
    );
  }

  Widget _content(
    BuildContext context,
    AccountController c,
    AppLocalizations l10n,
    double walkerBottom,
    double bodyHeight,
  ) {
    return TabScaffold(
      // The page heads itself "Profile" (the mock's word); the TAB stays "You" — docs/14 §1 owns
      // the shell's names, not the page's heading.
      title: l10n.accountTitle,
      subtitle: l10n.accountSubtitle,
      // The sign-out button lives INSIDE the list now (D-146): pinned below it, its height was
      // silently counted into `_Details`' headerHeight and the frame band came up short — the
      // stat strip printed into the walker's circle.
      child: Obx(
        () => switch (c.state.value) {
          Loading<ProfileView>() => const LoadingView(),
          Empty<ProfileView>() => EmptyView(
            title: l10n.accountEmptyTitle,
            body: l10n.accountEmptyBody,
          ),
          Failed<ProfileView>(:final failure) => FailedView(
            failure: failure,
            onRetry: c.load,
            retryLabel: l10n.accountRetry,
          ),
          Ready<ProfileView>(:final data) => _Details(
            profile: data,
            controller: c,
            walkerBottom: walkerBottom,
            bodyHeight: bodyHeight,
            // The sheet returns true only after the server accepted the change, so the
            // reload reflects what was actually stored, not what was typed.
            onEdited: c.load,
          ),
        },
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({
    required this.profile,
    required this.controller,
    required this.onEdited,
    required this.walkerBottom,
    required this.bodyHeight,
  });

  final ProfileView profile;
  final AccountController controller;
  final Future<void> Function() onEdited;

  /// Bottom of the walker's box, in the shell BODY's coordinates. The list lives further down the
  /// page than that, so it is converted below rather than used directly.
  final double walkerBottom;
  final double bodyHeight;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return LayoutBuilder(
      builder: (context, list) {
        // The list is not the page: the tab's title sits above it. Everything the hole is measured
        // in is body coordinates, so convert once, here, rather than hard-coding a header height
        // that changes with the font scale.
        final headerHeight = bodyHeight - list.maxHeight;

        return RefreshIndicator(
          onRefresh: () => controller.load(quiet: true),
          child: ListView(
            // The gesture has to be available even when the profile is short enough to fit.
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
            children: [
              // The band the walker and his stage occupy, exactly as on Home (D-152). The heading
              // and photo sit in it, to the LEFT of him.
              SizedBox(
                height: (walkerBottom - headerHeight).clamp(AppSizes.profileFrame, bodyHeight),
                // The mock's hero is three corners, not a column (D-151): the LEFT half lays out
                // on its own — avatar row at the top, straight under the subtitle; the stat strip
                // at the foot, beside the stage's lower third — and neither waits for the walker.
                child: LayoutBuilder(
                  builder: (context, band) => Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: AppSpacing.md,
                        width: band.maxWidth * 0.58,
                        child: ProfileFrame(
                          name: profile.name,
                          photoUrl: profile.photoUrl,
                          onPhotoChanged: onEdited,
                        ),
                      ),
                      // Age and height at a glance. "Member since" waits on the server sending
                      // the account's created_at (docs/21 §7).
                      Positioned(
                        left: 0,
                        bottom: AppSpacing.sm,
                        width: band.maxWidth * 0.55,
                        child: _StatStrip(profile: profile),
                      ),
                      // The mock's step pill, hung on the frame's lower edge — only when the
                      // phone reported a count today (D-146).
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Obx(() {
                          final steps = controller.today.value?.steps;
                          if (steps == null) return const SizedBox.shrink();
                          return _StepsChip(steps: steps);
                        }),
                      ),
                    ],
                  ),
                ),
              ),
              // Today at a glance (D-144): the day's figures in miniature, with the way to Home.
              // Only when a diary answered — no card of dashes for a day that never loaded.
              Obx(() {
                final day = controller.today.value;
                if (day == null) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionHeader(
                      title: l.homeSubtitle,
                      actionLabel: l.progressSeeAll,
                      onAction: () {
                        if (Get.isRegistered<NavController>()) {
                          Get.find<NavController>().current = ClientTab.home;
                        }
                      },
                    ),
                    _GlanceCard(day: day),
                  ],
                );
              }),
              SectionHeader(title: l.accountDailyGoals),
              Obx(() => _GoalTiles(goals: controller.goals.value, today: controller.today.value)),
              // Quick actions (D-144), each going somewhere that exists. Everything that used to sit
              // between the goals and here is one tap away in the Explore sheet (D-237).
              SectionHeader(title: l.accountQuickActions),
              _quickActions(context, l),
              const SizedBox(height: AppSpacing.lg),
              const _SignOutButton(),
              // Clears the docked FAB, which otherwise sits on top of the button.
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        );
      },
    );
  }

  Widget _quickActions(BuildContext context, AppLocalizations l) {
    // No session, no Obx. An Obx whose only observable sits behind a `&&` that short-circuits
    // reads nothing and throws "improper use of a GetX" — so whether to observe is decided here,
    // where the controller is either present or it is not.
    final session = Get.isRegistered<SessionController>() ? Get.find<SessionController>() : null;
    final messages = Get.isRegistered<NotificationsController>()
        ? Get.find<NotificationsController>()
        : null;
    if (session == null) return _pills(context, l, isCoach: false);

    // Obx around the whole Wrap, not just the coach pill: `role` is an Rx read from inside a
    // CHILD's build, which the page-level Obx never subscribes to — so the pill appeared only on
    // the next cold start. Wrapping the Wrap also keeps a hidden pill from leaving a gap.
    return Obx(
      () => _pills(
        context,
        l,
        isCoach: session.role.value == SessionRole.coach,
        unread: messages?.unread.value ?? 0,
      ),
    );
  }

  Widget _pills(BuildContext context, AppLocalizations l, {required bool isCoach, int unread = 0}) {
    // A settings list rather than a wrap of pills (D-237): fifteen pills read as a wall, and a row
    // can say in one line what is behind it.
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      // The tiles draw their ink on the nearest Material, which would otherwise be the page behind
      // the card's fill.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            // Everything about the person below their daily goals lives in this sheet (D-237).
            _ActionTile(
              icon: Icons.explore_outlined,
              tint: AppColors.success,
              label: l.accountExplore,
              body: l.accountExploreBody,
              onTap: () => ProfileDetailsSheet.show(context, controller),
            ),
            _ActionTile(
              icon: Icons.edit_outlined,
              tint: AppColors.info,
              label: l.accountEditProfile,
              body: l.accountEditProfileBody,
              onTap: () async {
                final changed = await EditSheets.details(context, profile);
                if (changed ?? false) await onEdited();
              },
            ),
            // D-241: the Gym section — routines, workouts and what they burn.
            _ActionTile(
              icon: Icons.fitness_center,
              tint: AppColors.info,
              label: l.gymAccountTile,
              body: l.gymAccountTileBody,
              onTap: GymPage.open,
            ),
            _ActionTile(
              icon: Icons.restaurant_menu_outlined,
              tint: AppColors.success,
              label: l.accountMyPlan,
              body: l.accountMyPlanBody,
              onTap: () {
                if (Get.isRegistered<NavController>()) {
                  Get.find<NavController>().current = ClientTab.plan;
                }
              },
            ),
            // The coach surface, for accounts that have one (D-174). An entry point rather than a
            // replacement shell: a coach still tracks their own food, and taking their Home and
            // Progress away to give them a client list served nobody.
            if (isCoach)
              _ActionTile(
                icon: Icons.groups_outlined,
                tint: AppColors.macroCarb,
                label: l.accountCoachDashboard,
                body: l.accountCoachDashboardBody,
                onTap: () => Get.to<void>(() => const CoachShell()),
              ),
            // Nothing to do with the partner route below it: no code, no commission, no attribution
            // (docs/12 §3 locks that to a partner code at signup). Just a person telling a person.
            _ActionTile(
              icon: Icons.ios_share_outlined,
              tint: AppColors.accent,
              label: l.accountInviteFriends,
              body: l.accountInviteFriendsBody,
              onTap: () => InviteFriends.share(context),
            ),
            // docs/12 §6. Shown to everyone: level 1 is "signup + agreement", so anyone with an
            // account may take it, and hiding the door behind an invite is a growth decision nobody
            // has made yet.
            _ActionTile(
              icon: Icons.handshake_outlined,
              tint: AppColors.warning,
              label: l.accountBecomePartner,
              body: l.accountBecomePartnerBody,
              onTap: () {
                if (!Get.isRegistered<BecomePartnerController>()) {
                  Get.put(
                    BecomePartnerController(coach: Get.find<CoachRepository>()),
                    permanent: true,
                  );
                }
                Get.to<void>(() => const BecomePartnerPage());
              },
            ),
            // docs/10 §3 requires this to be ONE screen the client can find. Beside the partner
            // door on purpose: the place you give access away is the place you take it back.
            _ActionTile(
              icon: Icons.lock_outline,
              tint: AppColors.macroProtein,
              label: l.accountWhoCanSee,
              body: l.accountWhoCanSeeBody,
              onTap: () {
                if (!Get.isRegistered<DataAccessController>()) {
                  Get.put(
                    DataAccessController(coach: Get.find<CoachRepository>()),
                    permanent: true,
                  );
                }
                Get.to<void>(() => const DataAccessPage());
              },
            ),
            // D-215. Beside "who can see my data": both answer "what leaves my phone, and to whom".
            // Absent only where nothing can sync — tests that register no health sync.
            if (Get.isRegistered<SyncHealth>())
              _ActionTile(
                icon: Icons.favorite_outline,
                tint: AppColors.danger,
                label: l.accountHealthData,
                body: l.accountHealthDataBody,
                onTap: HealthConnectPage.open,
              ),
            // docs/02 FR-5.5: the client's side of the coach chat. The list says so itself when
            // nobody has shared chat with them.
            if (Get.isRegistered<ChatRepository>())
              _ActionTile(
                icon: Icons.forum_outlined,
                tint: AppColors.info,
                label: l.accountMessages,
                body: l.accountMessagesBody,
                onTap: ThreadsPage.open,
              ),
            // docs/14 §6 puts the subscription under You: the plan, its renewal date, and the two
            // things docs/11 lets a person do about it.
            if (Get.isRegistered<BillingRepository>())
              _ActionTile(
                icon: Icons.card_membership_outlined,
                tint: AppColors.macroFat,
                label: l.accountSubscription,
                body: l.accountSubscriptionBody,
                onTap: SubscriptionPage.open,
              ),
            // docs/14 §6 puts the message list under You. The count is what makes it worth opening.
            if (Get.isRegistered<NotificationsRepository>())
              _ActionTile(
                icon: Icons.mail_outline,
                tint: AppColors.warmCoral,
                label: unread > 0 ? l.accountNotificationsUnread('$unread') : l.notificationsTitle,
                body: l.accountNotificationsBody,
                onTap: NotificationsPage.open,
              ),
            // docs/13 §3: withdrawal has to be as easy as granting, which means one tap from You.
            if (Get.isRegistered<PrivacyRepository>())
              _ActionTile(
                icon: Icons.privacy_tip_outlined,
                tint: AppColors.macroCarb,
                label: l.accountPrivacy,
                body: l.accountPrivacyBody,
                onTap: PrivacyPage.open,
              ),
            // docs/14 §6 puts help under You: a person with a problem writes to a person (D-228).
            if (Get.isRegistered<TicketsRepository>())
              _ActionTile(
                icon: Icons.help_outline,
                tint: AppColors.success,
                label: l.accountHelp,
                body: l.accountHelpBody,
                onTap: TicketsPage.open,
              ),
            // D-222. docs/14 §6 puts reminders under You.
            if (Get.isRegistered<RefreshReminders>())
              _ActionTile(
                icon: Icons.notifications_none_outlined,
                tint: AppColors.warning,
                label: l.remindersTitle,
                body: l.accountRemindersBody,
                onTap: RemindersPage.open,
              ),
            _ActionTile(
              icon: Icons.bar_chart,
              tint: AppColors.accent,
              label: l.accountReports,
              body: l.accountReportsBody,
              onTap: () {
                if (Get.isRegistered<NavController>()) {
                  Get.find<NavController>().current = ClientTab.progress;
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The mock's goal rows (D-144, restyling D-61's saturated bands): a white row per target, the
/// macro's colour on its disc and its progress bar. Calories takes the brand green — it is the
/// day's total, not a macro, and giving it a fourth hue would imply a fourth ring. When today's
/// diary is present the bar shows eaten-against-goal; without it the row states the goal alone.
///
/// Null goals means no plan, which is said in words instead of shown as four zeroes (D-43).
/// There is deliberately no "Edit goals" and no "Add more goals": targets are the SERVER's
/// answer to the profile (rule 2) — the way to change them is to change the profile or the plan.
class _GoalTiles extends StatelessWidget {
  const _GoalTiles({required this.goals, this.today});

  final Macros? goals;
  final DiaryDay? today;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final g = goals;
    if (g == null) {
      return Text(l.accountNoGoalsYet, style: theme.textTheme.bodyMedium);
    }

    double? ratio(double? eaten, double target) =>
        eaten == null || target <= 0 ? null : eaten / target;
    final waterTarget = today?.waterTargetMl;

    return Column(
      children: [
        _GoalRow(
          icon: Icons.local_fire_department_outlined,
          color: theme.colorScheme.primary,
          label: l.accountGoalCalories,
          value: '${g.kcal.round()}',
          progress: ratio(today?.totals.kcal, g.kcal),
        ),
        _GoalRow(
          icon: Icons.egg_alt_outlined,
          color: AppColors.macroProtein,
          label: l.homeProtein,
          value: '${g.proteinG.round()} g',
          progress: ratio(today?.totals.proteinG, g.proteinG),
        ),
        _GoalRow(
          icon: Icons.grain_outlined,
          color: AppColors.macroCarb,
          label: l.homeCarbs,
          value: '${g.carbG.round()} g',
          progress: ratio(today?.totals.carbG, g.carbG),
        ),
        _GoalRow(
          icon: Icons.water_drop_outlined,
          color: AppColors.macroFat,
          label: l.homeFat,
          value: '${g.fatG.round()} g',
          progress: ratio(today?.totals.fatG, g.fatG),
        ),
        if (waterTarget != null && waterTarget > 0)
          _GoalRow(
            icon: Icons.local_drink_outlined,
            color: AppColors.info,
            label: l.homeWater,
            value: '${(waterTarget / 1000).toStringAsFixed(1)} L',
            progress: ratio((today?.waterLoggedMl ?? 0).toDouble(), waterTarget.toDouble()),
          ),
      ],
    );
  }
}

/// One goal row: the macro's solid disc and white glyph, the label, today's bar in the same hue
/// (clamped — the number never is, docs/05 §6), the target on the right.
class _GoalRow extends StatelessWidget {
  const _GoalRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.progress,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  /// Today's eaten-against-goal; null draws no bar rather than a bar of nothing.
  final double? progress;

  static const _disc = 36.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
        // Vertical sm, not md (D-153): five of these stack, and the 48 pt floor above already
        // keeps a sparse row tall enough.
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.tile),
          boxShadow: AppElevation.card(theme.brightness),
        ),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Container(
                height: _disc,
                width: _disc,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Icon(icon, size: AppSpacing.lg, color: AppColors.lightSurface),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      child: LinearProgressIndicator(
                        value: progress!.clamp(0.0, 1.0),
                        minHeight: AppSizes.barHeight * 0.75,
                        color: color,
                        backgroundColor: color.withValues(alpha: 0.18),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// Today in miniature (D-144): calories against the goal with the ring, the three macros and
/// water as small bars, and the phone's step count when the day carries one.
class _GlanceCard extends StatelessWidget {
  const _GlanceCard({required this.day});

  final DiaryDay day;

  static const _ring = 64.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final targets = day.targets;
    final kcalTarget = targets?.kcal;
    final tiles = <(String, String, double?, Color)>[
      if (targets != null) ...[
        (
          l.homeProtein,
          '${day.totals.proteinG.round()} / ${targets.proteinG.round()} g',
          targets.proteinG <= 0 ? null : day.totals.proteinG / targets.proteinG,
          AppColors.macroProtein,
        ),
        (
          l.homeCarbs,
          '${day.totals.carbG.round()} / ${targets.carbG.round()} g',
          targets.carbG <= 0 ? null : day.totals.carbG / targets.carbG,
          AppColors.macroCarb,
        ),
        (
          l.homeFat,
          '${day.totals.fatG.round()} / ${targets.fatG.round()} g',
          targets.fatG <= 0 ? null : day.totals.fatG / targets.fatG,
          AppColors.macroFat,
        ),
      ],
      if (day.waterTargetMl != null && day.waterTargetMl! > 0)
        (
          l.homeWater,
          '${((day.waterLoggedMl ?? 0) / 1000).toStringAsFixed(1)} / '
              '${(day.waterTargetMl! / 1000).toStringAsFixed(1)} L',
          (day.waterLoggedMl ?? 0) / day.waterTargetMl!,
          AppColors.info,
        ),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const ExcludeSemantics(
                          child: Icon(
                            Icons.local_fire_department,
                            size: AppSpacing.lg,
                            color: AppColors.warning,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(l.accountGoalCalories, style: theme.textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        kcalTarget == null
                            ? '${day.totals.kcal.round()} kcal'
                            : '${day.totals.kcal.round()} / ${kcalTarget.round()} kcal',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              ProgressRing(
                size: _ring,
                strokeWidth: 6,
                progress: kcalTarget == null || kcalTarget <= 0
                    ? null
                    : day.totals.kcal / kcalTarget,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        kcalTarget == null || kcalTarget <= 0
                            ? '—'
                            : '${(day.totals.kcal / kcalTarget * 100).round()}%',
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(l.progressOfGoal, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (tiles.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            LayoutBuilder(
              builder: (context, constraints) {
                final perRow = constraints.maxWidth < AppSizes.heroBreakpoint ? 1 : 2;
                final width = (constraints.maxWidth - AppSpacing.sm * (perRow - 1)) / perRow;
                return Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final (label, value, ratio, color) in tiles)
                      SizedBox(
                        width: width,
                        child: _GlanceTile(label: label, value: value, ratio: ratio, color: color),
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// The mock's hero strip: a figure with its icon and caption, dividers between (D-146).
class _StatStrip extends StatelessWidget {
  const _StatStrip({required this.profile});

  final ProfileView profile;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final items = [
      (Icons.cake_outlined, l.fieldAge, l.accountAgeValue(profile.ageYears)),
      (Icons.height, l.fieldHeightCm, l.accountHeightValue(profile.heightCm)),
    ];

    return Row(
      children: [
        for (final (i, (icon, label, value)) in items.indexed) ...[
          if (i > 0)
            Container(
              width: 1,
              height: AppSpacing.xxl,
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              color: scheme.outline,
            ),
          Expanded(
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Icon(icon, size: AppSpacing.lg, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: theme.textTheme.bodySmall),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The white pill at the walker's feet: today's step count, the phone's own figure (D-146).
class _StepsChip extends StatelessWidget {
  const _StepsChip({required this.steps});

  final int steps;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final formatted = NumberFormat.decimalPattern(locale).format(steps);

    return Semantics(
      label: l.accountStepsToday(formatted),
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.tile),
            boxShadow: AppElevation.raised(theme.brightness),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.directions_walk, size: AppSpacing.xl, color: AppColors.success),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatted,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(l.accountStepsCaption, style: theme.textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One small figure in the glance card: label, value, and the bar in the macro's colour. The bar
/// clamps; the number does not (docs/05 §6).
class _GlanceTile extends StatelessWidget {
  const _GlanceTile({
    required this.label,
    required this.value,
    required this.ratio,
    required this.color,
  });

  final String label;
  final String value;
  final double? ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(
            value: (ratio ?? 0).clamp(0.0, 1.0),
            minHeight: AppSizes.barHeight * 0.75,
            color: color,
            backgroundColor: color.withValues(alpha: 0.18),
          ),
        ),
      ],
    );
  }
}

/// One quick action as a settings row (D-237): a tinted glyph, what it is, one line on what is
/// behind it, and the chevron that says it goes somewhere.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.tint,
    required this.label,
    required this.body,
    required this.onTap,
  });

  final IconData icon;
  final Color tint;
  final String label;
  final String body;
  final VoidCallback onTap;

  static const _disc = 44.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      // Decoration: the title beside it carries the meaning.
      leading: ExcludeSemantics(
        child: Container(
          height: _disc,
          width: _disc,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Icon(icon, size: AppSpacing.xl, color: tint),
        ),
      ),
      title: Text(label, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(body),
      trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
    );
  }
}

/// Disables itself while the call is in flight so a double tap cannot fire two logouts.
class _SignOutButton extends StatefulWidget {
  const _SignOutButton();

  @override
  State<_SignOutButton> createState() => _SignOutButtonState();
}

class _SignOutButtonState extends State<_SignOutButton> {
  bool _busy = false;

  Future<void> _signOut() async {
    setState(() => _busy = true);
    // SessionController clears local state even if the server call fails, then RootGate flips back
    // to the login page — there is nothing to navigate here.
    await Get.find<SessionController>().signOut();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    // The list it sits in carries the horizontal padding now (D-146).
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(onPressed: _busy ? null : _signOut, child: Text(l10n.signOut)),
    );
  }
}

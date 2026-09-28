import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_assets.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/progress_ring.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';
import 'package:health_pro/presentation/features/home/home_controller.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/nav_controller.dart';
import 'package:intl/intl.dart';

/// Water, logged a glass at a time (D-86).
///
/// The goal is the ENGINE's — body weight against the rule pack's `ml_per_kg`, floor and ceiling.
/// Nothing here works out how much anyone should drink; it shows the number the server sent and
/// counts up to it.
///
/// **Sends the running total, not the increment.** A measurement row is "this kind, this diary
/// day", written once and overwritten — the same rule that stops two weigh-ins counting as two
/// people. Water is the one thing users add to through the day, so the addition happens here and
/// the server still stores a day's total. The cost is that two devices adding at the same moment
/// would have one win rather than both adding, which is the better failure of the two: a lost glass
/// is recoverable by tapping again, a double-counted one is invisible.
class WaterLogTab extends StatefulWidget {
  const WaterLogTab({super.key});

  /// What a glass, a bottle and a big bottle hold. Rounded to what people actually pour.
  static const amountsMl = [200, 250, 500];

  @override
  State<WaterLogTab> createState() => _WaterLogTabState();
}

class _WaterLogTabState extends State<WaterLogTab> {
  bool _saving = false;
  String? _error;

  /// What was logged before the last tap, so it can be undone. Null when there is nothing to undo.
  int? _previousMl;

  DiaryDay? get _day {
    if (!Get.isRegistered<HomeController>()) return null;
    final state = Get.find<HomeController>().state.value;
    return state is Ready<DiaryDay> ? state.data : null;
  }

  Future<void> _setTotal(int totalMl, {required int? undoTo}) async {
    setState(() {
      _saving = true;
      _error = null;
    });

    final result = await Get.find<MeasurementsRepository>().record(
      kind: 'water_ml',
      value: totalMl.toDouble(),
      unit: 'ml',
    );

    final failure = result.fold((f) => f.userMessage, (_) => null);

    // Home owns the day, and the day is what carries the running total — so it has to be asked
    // again rather than this screen keeping its own copy.
    if (failure == null && Get.isRegistered<HomeController>()) {
      await Get.find<HomeController>().load();
    }

    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = failure;
      _previousMl = failure == null ? undoTo : _previousMl;
    });
  }

  /// Leaves the sheet and lands on Progress, where the week of water sits (D-128). "View history"
  /// that opened a second history inside a modal would be a third place the same rows live.
  void _openHistory() {
    Navigator.of(context).pop();
    if (Get.isRegistered<NavController>()) Get.find<NavController>().current = ClientTab.progress;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final day = _day;
    final logged = day?.waterLoggedMl ?? 0;
    final target = day?.waterTargetMl;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WaterHero(logged: logged, target: target),
          const SizedBox(height: AppSpacing.xl),
          Text(
            l.logWaterQuickAdd,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              for (final amount in WaterLogTab.amountsMl) ...[
                if (amount != WaterLogTab.amountsMl.first) const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _QuickAdd(
                    amount: amount,
                    onTap: _saving ? null : () => _setTotal(logged + amount, undoTo: logged),
                  ),
                ),
              ],
            ],
          ),
          if (_previousMl != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                // A mis-tap on a running total is otherwise only fixable by knowing the old number.
                onPressed: _saving ? null : () => _setTotal(_previousMl!, undoTo: null),
                icon: const Icon(Icons.undo),
                label: Text(l.logWaterUndo),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                child: Text(
                  l.logWaterTodayLog,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(onPressed: _openHistory, child: Text(l.logWaterHistory)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // ONE row, not a list of sips. A day's water is a single measurement row that this screen
          // adds to (see the class comment) — drawing separate entries would be inventing a history
          // the server does not keep, and one that would vanish the moment the sheet was reopened.
          _TodayRow(logged: logged, onTap: logged == 0 ? null : _openHistory),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            // Rule 7: the server's own words.
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          HintCard(
            icon: Icons.water_drop_outlined,
            title: l.logWaterFactTitle,
            text: l.logWaterFactBody,
          ),
        ],
      ),
    );
  }
}

/// The day's total against the goal, and the bottle.
///
/// The goal is the ENGINE's — body weight against the rule pack, floor and ceiling. There is no
/// pencil beside it: a goal the app let the user edit would be the app setting a target, which is
/// the server's job (CLAUDE.md rule 2). It arrives with the plan or it does not exist yet.
class _WaterHero extends StatelessWidget {
  const _WaterHero({required this.logged, required this.target});

  final int logged;
  final int? target;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final number = NumberFormat.decimalPattern(locale);

    return LayoutBuilder(
      builder: (context, constraints) {
        final art = (constraints.maxWidth * AppSizes.heroArtFraction).clamp(
          0.0,
          AppSizes.heroArtMax,
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.logWaterTitle,
                    style: theme.textTheme.headlineMedium?.copyWith(color: scheme.onSurface),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Center(
                    child: ProgressRing(
                      size: AppSizes.heroRings * 0.65,
                      // Null, never zero, when there is no plan: an empty ring would say the user
                      // is at nought of a goal that does not exist yet (D-43).
                      progress: target == null || target == 0 ? null : logged / target!,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            number.format(logged),
                            style: theme.textTheme.displayLarge?.copyWith(color: scheme.primary),
                          ),
                          Text(l.logWaterUnit, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Center(
                    child: Text(
                      target == null ? l.logWaterNoGoal : l.logWaterGoal(number.format(target)),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Column(
              children: [
                ExcludeSemantics(
                  child: Image.asset(
                    AppAssets.themed(AppAssets.waterHero, Theme.of(context).brightness),
                    width: art,
                    fit: BoxFit.contain,
                  ),
                ),
                if (target != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: art,
                    child: AppCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        children: [
                          Text(
                            '${number.format(target)} ${l.logWaterUnit}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: scheme.primary,
                            ),
                          ),
                          Text(l.logWaterDailyGoal, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }
}

/// One pour. A glass, its size, and nothing else to decide.
class _QuickAdd extends StatelessWidget {
  const _QuickAdd({required this.amount, required this.onTap});

  final int amount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.sm),
      child: Column(
        children: [
          ExcludeSemantics(
            child: Icon(Icons.local_drink_outlined, size: AppSpacing.xxl, color: scheme.primary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l.logWaterAdd('$amount'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
          ),
        ],
      ),
    );
  }
}

/// What today holds so far, or an invitation to start it.
class _TodayRow extends StatelessWidget {
  const _TodayRow({required this.logged, required this.onTap});

  final int logged;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Container(
              height: AppSizes.ringSmall,
              width: AppSizes.ringSmall,
              decoration: BoxDecoration(
                color: scheme.secondaryContainer.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.local_drink_outlined,
                size: AppSpacing.lg,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  logged == 0 ? l.logWaterNone : l.logWaterLogged(logged),
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (logged == 0) Text(l.logWaterNoneHint, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right, size: AppSpacing.xl, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

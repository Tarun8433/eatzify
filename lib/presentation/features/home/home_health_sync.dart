import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/domain/usecases/sync_health.dart';
import 'package:health_pro/presentation/features/account/health_connect_page.dart';
import 'package:health_pro/presentation/features/home/home_controller.dart';
import 'package:health_pro/presentation/features/onboarding/enum_labels.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// Connect, or Sync, under the day's activity (D-218).
///
/// Shown whether or not the day already has a figure: somebody who typed their steps this morning
/// is exactly who may want the watch's number now. One button, and it does the whole job — asks for
/// access if that is not settled yet, fills in the last 30 days, and puts today's device figures in.
class HomeHealthSync extends StatelessWidget {
  /// Its own line: the offer to connect, and Sync unless [syncShownInline].
  const HomeHealthSync({required this.controller, this.syncShownInline = false, super.key})
    : _inline = false;

  /// Sync only, as a round icon button for the end of the steps row. Nothing while not connected —
  /// the offer to connect needs words, so it keeps a line of its own.
  const HomeHealthSync.inline({required this.controller, super.key})
    : _inline = true,
      syncShownInline = true;

  final HomeController controller;

  /// Whether the steps row is already showing Sync, so this line leaves it out.
  final bool syncShownInline;

  final bool _inline;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final platform = SyncHealth.platformSource.label(l);

    return Obx(() {
      final offer = controller.healthOffer.value;
      final linked = controller.healthLinked.value;
      final busy = controller.syncing.value;

      if (_inline) {
        if (offer || !linked) return const SizedBox.shrink();
        return IconButton.filledTonal(
          // The tooltip is also what a screen reader says.
          tooltip: l.healthSyncNow(platform),
          // Small beside a number, but still a 48 dp target (rule 12).
          visualDensity: VisualDensity.compact,
          iconSize: AppSpacing.lg + AppSpacing.xs,
          onPressed: busy ? null : () => syncAndReport(context, controller),
          icon: busy
              // Tied to the request, and replaced by its result a moment later.
              ? const SizedBox.square(
                  dimension: AppSpacing.lg,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync),
        );
      }

      if (!offer && (!linked || syncShownInline)) return const SizedBox.shrink();
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: busy ? null : () => syncAndReport(context, controller),
          icon: Icon(offer ? Icons.favorite_outline : Icons.sync),
          label: Text(
            busy
                ? l.healthSyncing
                : offer
                ? l.homeConnectHealth(platform)
                : l.healthSyncNow(platform),
          ),
        ),
      );
    });
  }
}

/// Runs a tapped sync and says how it went. The sentence is the outcome, never a spinner left
/// behind: a sync that could not happen says why.
Future<void> syncAndReport(BuildContext context, HomeController controller) async {
  final messenger = ScaffoldMessenger.of(context);
  final l = AppLocalizations.of(context);
  final result = await controller.syncHealthNow();
  if (result == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(healthSyncMessage(l, result))));
}

/// The once-per-account offer to connect (D-218). Puts a sheet up when Home raises
/// [HomeController.healthPrompt]; the system's own permission sheet only ever follows the tap on
/// "Connect" inside it, never the app opening.
class HomeHealthPrompt extends StatefulWidget {
  const HomeHealthPrompt({required this.controller, super.key});

  final HomeController controller;

  @override
  State<HomeHealthPrompt> createState() => _HomeHealthPromptState();
}

class _HomeHealthPromptState extends State<HomeHealthPrompt> {
  late final Worker _worker;

  @override
  void initState() {
    super.initState();
    _worker = ever<bool>(widget.controller.healthPrompt, (raised) {
      if (raised) WidgetsBinding.instance.addPostFrameCallback((_) => _open());
    });
  }

  @override
  void dispose() {
    _worker.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (!mounted || !widget.controller.healthPrompt.value) return;
    widget.controller.healthPromptShown();

    final connect = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      // Sized to its content, scrolling past the screen height — at 200 % text the buttons would
      // otherwise sit below a fixed nine-sixteenths sheet.
      isScrollControlled: true,
      builder: (_) => const _PromptSheet(),
    );
    if (connect != true || !mounted) return;
    await syncAndReport(context, widget.controller);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _PromptSheet extends StatelessWidget {
  const _PromptSheet();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final platform = SyncHealth.platformSource.label(l);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.favorite_outline, size: AppSpacing.xxl, color: theme.colorScheme.primary),
            const SizedBox(height: AppSpacing.md),
            Text(
              l.healthPromptTitle,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l.healthExplainer(platform),
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l.healthConnect(platform)),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.healthPromptLater),
            ),
          ],
        ),
      ),
    );
  }
}

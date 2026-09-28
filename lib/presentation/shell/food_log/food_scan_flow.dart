import 'dart:async';

import 'package:dartz/dartz.dart' show Either;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/ads/rewarded_ad_gate.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/domain/entities/food_scan.dart';
import 'package:health_pro/domain/repositories/billing_repository.dart';
import 'package:health_pro/domain/repositories/scan_repository.dart';
import 'package:health_pro/presentation/features/billing/billing_controller.dart';
import 'package:health_pro/presentation/features/billing/paywall_sheet.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/food_log/scan_result_sheet.dart';
import 'package:image_picker/image_picker.dart';

/// Scan Food, end to end (D-238): may I → the ad, if the tier needs one → a photo → which of our
/// foods are on it → "Are you having this?". Everything is the server's call; this only sequences
/// the screens and says what the server said.
class FoodScanFlow {
  FoodScanFlow({required this.scans, this.ads, ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ScanRepository scans;

  /// Null where no ad can be shown (tests, or a build without ads); a tier that needs one then gets
  /// the "couldn't load an ad" message rather than a free pass.
  final RewardedAdGate? ads;
  final ImagePicker _picker;

  /// A phone photo at this size identifies a dish as well as the original and uploads in a second.
  static const _maxPhotoSide = 1024.0;
  static const _photoQuality = 80;

  Future<ScanOutcome?> run(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    void say(String text) => messenger?.showSnackBar(SnackBar(content: Text(text)));

    final status = await scans.status();
    if (!context.mounted) return null;
    final allowed = status.fold<ScanStatus?>((failure) {
      say(failure.userMessage);
      return null;
    }, (s) => s);
    if (allowed == null) return null;
    if (!allowed.allowed) {
      if (allowed.needsUpgrade && _openUpgrade(context)) return null;
      say(allowed.userMessage ?? l.scanUnavailable);
      return null;
    }

    if (allowed.requiresAd) {
      final watch = await _askForAd(context, allowed.remainingToday);
      if (watch != true || !context.mounted) return null;
      final outcome = await ads?.show() ?? AdOutcome.unavailable;
      if (!context.mounted) return null;
      if (outcome != AdOutcome.earned) {
        say(outcome == AdOutcome.skipped ? l.scanAdSkipped : l.scanAdUnavailable);
        return null;
      }
    }

    final source = await _chooseSource(context);
    if (source == null || !context.mounted) return null;
    final photo = await _picker.pickImage(
      source: source,
      maxWidth: _maxPhotoSide,
      maxHeight: _maxPhotoSide,
      imageQuality: _photoQuality,
    );
    if (photo == null || !context.mounted) return null;

    final result = await showModalBottomSheet<Either<Failure, ScanEstimate>>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => _AnalysingSheet(
        photoPath: photo.path,
        work: scans.scan(photo.path, photo.name, adWatched: allowed.requiresAd),
      ),
    );
    if (result == null || !context.mounted) return null;

    final estimate = result.fold<ScanEstimate?>((failure) {
      final upgrade = failure is ApiFailure && failure.isEntitlementRequired;
      if (!(upgrade && _openUpgrade(context))) say(failure.userMessage);
      return null;
    }, (e) => e);
    if (estimate == null) return null;

    // Not recognised is its own answer, never a guess — and the server kept no photo of it.
    if (!estimate.recognised) {
      return showModalBottomSheet<ScanOutcome>(
        context: context,
        showDragHandle: true,
        builder: (_) => ScanNoMatchSheet(photoPath: photo.path),
      );
    }

    final outcome = await showModalBottomSheet<ScanOutcome>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ScanResultSheet(photoPath: photo.path, estimate: estimate),
    );
    // "No", or the sheet swiped away: the server deletes the photo now, not at tonight's sweep
    // (D-240). Nothing is waiting on the answer, so it is not awaited.
    if (outcome is! ScanConfirmed) unawaited(scans.discard(estimate.scanId!));
    return outcome;
  }

  /// Rule 3: ENTITLEMENT_REQUIRED is answered with the upgrade sheet, never by hiding the feature.
  /// False where billing is not wired up, so the caller falls back to the server's words.
  bool _openUpgrade(BuildContext context) {
    if (!Get.isRegistered<BillingRepository>()) return false;
    final billing = Get.isRegistered<BillingController>()
        ? Get.find<BillingController>()
        : Get.put(BillingController(billing: Get.find<BillingRepository>()), permanent: true);
    unawaited(PaywallSheet.show(context, billing));
    return true;
  }

  /// Said before the ad, not sprung: the person chooses to watch it.
  Future<bool?> _askForAd(BuildContext context, int remaining) {
    final l = AppLocalizations.of(context);
    return showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.scanAdTitle, style: Theme.of(sheet).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(l.scanAdBody(remaining)),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: () => Navigator.of(sheet).pop(true),
              child: Text(l.scanAdWatch),
            ),
            TextButton(
              onPressed: () => Navigator.of(sheet).pop(false),
              child: Text(l.commonCancel),
            ),
          ],
        ),
      ),
    );
  }

  Future<ImageSource?> _chooseSource(BuildContext context) {
    final l = AppLocalizations.of(context);
    return showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l.accountPhotoTakePhoto),
              onTap: () => Navigator.of(sheet).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l.accountPhotoChooseGallery),
              onTap: () => Navigator.of(sheet).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }
}

/// The photo and a progress line while the server looks. It closes itself with the answer, and the
/// request carries its own timeout — this never spins forever (rule 6).
class _AnalysingSheet extends StatefulWidget {
  const _AnalysingSheet({required this.photoPath, required this.work});

  final String photoPath;
  final Future<Either<Failure, ScanEstimate>> work;

  @override
  State<_AnalysingSheet> createState() => _AnalysingSheetState();
}

class _AnalysingSheetState extends State<_AnalysingSheet> {
  @override
  void initState() {
    super.initState();
    unawaited(
      widget.work.then((result) {
        if (mounted) Navigator.of(context).pop(result);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScanPhoto(path: widget.photoPath),
          const SizedBox(height: AppSpacing.lg),
          const LinearProgressIndicator(),
          const SizedBox(height: AppSpacing.md),
          Text(l.scanAnalysing, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

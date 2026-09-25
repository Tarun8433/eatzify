import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/ads/rewarded_ad_gate.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/food_scan.dart';
import 'package:health_pro/domain/repositories/scan_repository.dart';
import 'package:image_picker/image_picker.dart';

import 'fakes.dart';
import 'food_log_tab_test.dart' show tabUnderTest;

/// D-240. Scan Food: the server says whether, the ad comes first when the tier needs one, and the
/// model's estimate of the plate is only logged after "Yes" — one entry, the kept items, the photo.

const rice = ScanItem(
  name: 'Rice (cooked white)',
  nutrition: NutritionPreview(
    grams: 200,
    kcal: 252,
    proteinG: 5.4,
    carbG: 56,
    fatG: 0.6,
    fibreG: 0.8,
    sodiumMg: 2,
    addedSugarG: 0,
    saturatedFatG: 0.2,
  ),
);
const dal = ScanItem(
  name: 'Dal tadka',
  nutrition: NutritionPreview(
    grams: 180,
    kcal: 216,
    proteinG: 10.8,
    carbG: 27,
    fatG: 7.2,
    fibreG: 5.4,
    sodiumMg: 540,
    addedSugarG: 0,
    saturatedFatG: 3.1,
  ),
);
const plate = ScanEstimate(
  scanId: 5,
  dishName: 'Rice with dal tadka',
  confidence: 0.8,
  items: [rice, dal],
);

class FakeScanRepository implements ScanRepository {
  FakeScanRepository({
    this.statusResult = const Right(
      ScanStatus(allowed: true, remainingToday: 10, requiresAd: false),
    ),
    this.scanResult = const Right(plate),
  });

  final Either<Failure, ScanStatus> statusResult;
  final Either<Failure, ScanEstimate> scanResult;

  /// The `ad_watched` of every scan sent.
  final scansSent = <bool>[];
  final confirmed = <({int scanId, String slot, List<int> keep})>[];
  final discarded = <int>[];

  @override
  Future<Either<Failure, ScanStatus>> status() async => statusResult;

  @override
  Future<Either<Failure, ScanEstimate>> scan(
    String filePath,
    String fileName, {
    required bool adWatched,
  }) async {
    scansSent.add(adWatched);
    return scanResult;
  }

  @override
  Future<Either<Failure, LogEntry>> confirm(
    int scanId, {
    required String slot,
    required List<int> keep,
  }) async {
    confirmed.add((scanId: scanId, slot: slot, keep: keep));
    return Right(
      LogEntry(
        id: 'log-1',
        slot: slot,
        name: 'Rice with dal tadka',
        quantityG: 380,
        kcal: 468,
        locked: false,
        estimated: true,
      ),
    );
  }

  @override
  Future<Either<Failure, Unit>> discard(int scanId) async {
    discarded.add(scanId);
    return const Right(unit);
  }
}

class FakeAdGate implements RewardedAdGate {
  FakeAdGate(this.outcome);

  final AdOutcome outcome;
  int shown = 0;

  @override
  Future<AdOutcome> show() async {
    shown++;
    return outcome;
  }
}

/// Answers the camera with a file that does not exist — the photo tile falls back to its
/// placeholder, which is all a test needs to see.
class FakePicker extends ImagePicker {
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async => XFile('/nonexistent/meal.jpg', name: 'meal.jpg');
}

Future<FakeDiaryRepository> pumpTab(
  WidgetTester tester, {
  required FakeScanRepository scans,
  RewardedAdGate? ads,
}) async {
  final diary = FakeDiaryRepository();
  final app = tabUnderTest(diary);
  Get
    ..put<ScanRepository>(scans, permanent: true)
    ..put<ImagePicker>(FakePicker(), permanent: true);
  if (ads != null) Get.put<RewardedAdGate>(ads, permanent: true);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  return diary;
}

/// Scan → camera → the sheets settle on whatever the flow shows next.
Future<void> scanAPlate(WidgetTester tester) async {
  await tester.tap(find.text('Scan'));
  await tester.pumpAndSettle();
  if (find.text('Take a photo').evaluate().isNotEmpty) {
    await tester.tap(find.text('Take a photo'));
    await tester.pumpAndSettle();
  }
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('should show the plate, its items and the estimated total, labelled as an estimate', (
    tester,
  ) async {
    await pumpTab(tester, scans: FakeScanRepository());

    await scanAPlate(tester);

    expect(find.text('Are you having this?'), findsOneWidget);
    expect(find.text('Looks like Rice with dal tadka'), findsOneWidget);
    expect(find.text('Rice (cooked white)'), findsOneWidget);
    expect(find.text('180 g · 216 kcal'), findsOneWidget);
    expect(find.text('468'), findsOneWidget, reason: '252 + 216 kcal');
    expect(find.textContaining('AI estimate'), findsOneWidget);
  });

  testWidgets('should take an unticked item out of the total', (tester) async {
    await pumpTab(tester, scans: FakeScanRepository());
    await scanAPlate(tester);

    await tapVisible(tester, find.text('Dal tadka'));

    expect(find.text('252'), findsOneWidget);
    expect(find.text('468'), findsNothing);
  });

  testWidgets('should log the kept items to the chosen meal on yes', (tester) async {
    final scans = FakeScanRepository();
    await pumpTab(tester, scans: scans);
    await scanAPlate(tester);

    await tapVisible(tester, find.text('Rice (cooked white)'));
    await tapVisible(tester, find.text('Dinner'));
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Yes, add to Dinner'));

    // Which items, never numbers — the server sums its own stored estimate.
    final sent = scans.confirmed.single;
    expect(sent.scanId, 5);
    expect(sent.slot, 'dinner');
    expect(sent.keep, [1]);
    expect(scans.discarded, isEmpty);
    expect(find.text('Added to Dinner'), findsOneWidget);
  });

  testWidgets('should not offer yes when every item is unticked', (tester) async {
    await pumpTab(tester, scans: FakeScanRepository());
    await scanAPlate(tester);

    await tapVisible(tester, find.text('Dinner'));
    await tapVisible(tester, find.text('Rice (cooked white)'));
    await tapVisible(tester, find.text('Dal tadka'));

    final yes = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Yes, add to Dinner'),
    );
    expect(yes.onPressed, isNull);
  });

  testWidgets('should delete the photo and search the plate when the user says no', (tester) async {
    final scans = FakeScanRepository();
    final diary = await pumpTab(tester, scans: scans);
    await scanAPlate(tester);

    await tapVisible(tester, find.widgetWithText(OutlinedButton, 'No'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(scans.confirmed, isEmpty);
    expect(scans.discarded, [5]);
    expect(diary.searchCalls.last.query, 'Rice with dal tadka');
  });

  testWidgets('should say so, never guess, when the photo was not recognised', (tester) async {
    await pumpTab(
      tester,
      scans: FakeScanRepository(
        scanResult: const Right(ScanEstimate(scanId: null, dishName: '', confidence: 0, items: [])),
      ),
    );

    await scanAPlate(tester);

    expect(find.text("We couldn't recognise this"), findsOneWidget);
    expect(find.text('Search instead'), findsOneWidget);
  });

  testWidgets('should play the ad first when the tier requires one, and tell the server', (
    tester,
  ) async {
    final scans = FakeScanRepository(
      statusResult: const Right(ScanStatus(allowed: true, remainingToday: 3, requiresAd: true)),
    );
    final ads = FakeAdGate(AdOutcome.earned);
    await pumpTab(tester, scans: scans, ads: ads);

    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 free scans left today'), findsOneWidget);
    await tester.tap(find.text('Watch ad'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take a photo'));
    await tester.pumpAndSettle();

    expect(ads.shown, 1);
    expect(scans.scansSent, [true]);
  });

  testWidgets('should not scan when the ad was closed early', (tester) async {
    final scans = FakeScanRepository(
      statusResult: const Right(ScanStatus(allowed: true, remainingToday: 3, requiresAd: true)),
    );
    await pumpTab(tester, scans: scans, ads: FakeAdGate(AdOutcome.skipped));

    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Watch ad'));
    await tester.pumpAndSettle();

    expect(scans.scansSent, isEmpty);
    expect(find.text('Watch the whole ad to scan your meal.'), findsOneWidget);
  });

  testWidgets("should show the server's words when today's scans are used up", (tester) async {
    final scans = FakeScanRepository(
      statusResult: const Right(
        ScanStatus(
          allowed: false,
          reason: 'limit_reached',
          remainingToday: 0,
          requiresAd: false,
          userMessage: "You've used today's 10 meal scans.",
        ),
      ),
    );
    await pumpTab(tester, scans: scans);

    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();

    // Rule 7: the server's sentence, not one written here.
    expect(find.text("You've used today's 10 meal scans."), findsOneWidget);
    expect(scans.scansSent, isEmpty);
  });

  testWidgets('should survive 200 % font scale on the confirm sheet (rule 12)', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpTab(tester, scans: FakeScanRepository());

    await scanAPlate(tester);

    expect(find.text('Are you having this?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

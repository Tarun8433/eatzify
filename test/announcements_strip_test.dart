import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/domain/entities/announcement.dart';
import 'package:health_pro/domain/repositories/announcements_repository.dart';
import 'package:health_pro/presentation/features/home/widgets/announcements_strip.dart';

/// Admin panel plan, Phase C: the team's announcements on Home, and silence when there are none.
class _Repo implements AnnouncementsRepository {
  _Repo(this.result);

  final Either<Failure, List<Announcement>> result;

  @override
  Future<Either<Failure, List<Announcement>>> active() async => result;
}

Future<void> pump(WidgetTester tester, AnnouncementsRepository? repo) async {
  Get.reset();
  if (repo != null) Get.put<AnnouncementsRepository>(repo);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: SingleChildScrollView(child: AnnouncementsStrip())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('should show each live announcement and let the person close one', (tester) async {
    await pump(
      tester,
      _Repo(
        const Right([
          Announcement(
            id: 'a',
            title: 'Diwali hours',
            body: 'Support answers until 6 pm.',
            priority: AnnouncementPriority.critical,
          ),
          Announcement(
            id: 'b',
            title: 'New recipes',
            body: 'Fifty more.',
            priority: AnnouncementPriority.normal,
          ),
        ]),
      ),
    );
    expect(find.text('Diwali hours'), findsOneWidget);
    expect(find.text('New recipes'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(find.text('Diwali hours'), findsNothing);
    expect(find.text('New recipes'), findsOneWidget);
  });

  testWidgets('should draw nothing on failure, when empty, or without a repository', (
    tester,
  ) async {
    await pump(tester, _Repo(const Left(ApiFailure('down', code: 'X'))));
    expect(find.byType(Card), findsNothing);
    expect(find.text('down'), findsNothing, reason: 'an announcement is never worth an error');

    await pump(tester, _Repo(const Right([])));
    expect(find.byIcon(Icons.close), findsNothing);

    await pump(tester, null);
    expect(find.byIcon(Icons.close), findsNothing);
  });
}

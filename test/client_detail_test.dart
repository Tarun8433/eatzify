import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/domain/entities/coach_client.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/coach_dashboard.dart';
import 'package:health_pro/domain/repositories/coach_repository.dart';
import 'package:health_pro/presentation/features/coach/client_detail_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// D-199. One client, opened from the roster.
///
/// The server decides what may appear (D-195); the page renders what arrived. So what is tested
/// here is not access control — it is that the page never INVENTS a value for something the grant
/// left out, and never turns a boundary into what looks like a gap in the client's profile.

class FakeCoachRepository implements CoachRepository {
  FakeCoachRepository({this.detail, this.failure});

  final CoachClientDetail? detail;
  final Failure? failure;

  @override
  Future<Either<Failure, CoachClientDetail>> client(int clientUserId) async {
    final f = failure;
    if (f != null) return Left(f);
    return Right(detail!);
  }

  /// The page loads the logs section separately (D-203). This fake has none, and the 404 is the
  /// same answer the server gives when the grant does not carry `progress`.
  @override
  Future<Either<Failure, DiaryDay>> clientDiary(int clientUserId, {String? date}) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, ClientProgress>> clientProgress(int clientUserId) async =>
      const Left(ApiFailure('no access', code: 'CLIENT_NOT_FOUND', status: 404));

  @override
  Future<Either<Failure, CoachDashboard>> dashboard() => throw UnimplementedError();

  @override
  Future<Either<Failure, CoachEarnings>> earnings({String? period}) => throw UnimplementedError();

  @override
  Future<Either<Failure, CoachReferral>> referral() => throw UnimplementedError();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Widget pageWith(FakeCoachRepository repo) {
  Get
    ..reset()
    ..put<CoachRepository>(repo, permanent: true);

  return GetMaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: const ClientDetailPage(clientUserId: 9, name: 'Ritu Agarwal'),
  );
}

const _full = CoachClientDetail(
  userId: 9,
  name: 'Ritu Agarwal',
  scopes: ['basic', 'progress', 'health_conditions'],
  ageYears: 34,
  goal: 'fat_loss',
  sexAtBirth: 'female',
  heightCm: 165,
  weightKg: 72,
  conditions: ['pcos'],
  allergies: [],
);

/// What a `basic` grant alone comes back as: a name, and nothing else.
const _basicOnly = CoachClientDetail(userId: 9, name: 'Ritu Agarwal', scopes: ['basic']);

void main() {
  testWidgets('should show every field the client shared', (tester) async {
    await tester.pumpWidget(pageWith(FakeCoachRepository(detail: _full)));
    await tester.pumpAndSettle();

    expect(find.text('34'), findsOneWidget);
    expect(find.text('165'), findsOneWidget);
    expect(find.text('72.0 kg'), findsOneWidget);
    // Through l10n, never the wire value (rule 4).
    expect(find.text('fat_loss'), findsNothing);
  });

  /// An absent list and an empty one are different answers. No `conditions` key means the client
  /// did not share them; an empty list means they declared none. Only the second reads as "None".
  testWidgets('should print None for a list the client shared as empty', (tester) async {
    await tester.pumpWidget(pageWith(FakeCoachRepository(detail: _full)));
    await tester.pumpAndSettle();

    expect(find.text('pcos'), findsOneWidget);
    expect(find.text('None'), findsOneWidget); // allergies, declared as none
  });

  /// The whole point of the page. A field the grant did not cover is ABSENT — not a dash, not an
  /// empty row, nothing that reads as a hole in the client's own profile.
  testWidgets('should show no row at all for what was not shared', (tester) async {
    await tester.pumpWidget(pageWith(FakeCoachRepository(detail: _basicOnly)));
    await tester.pumpAndSettle();

    expect(find.text('Current weight'), findsNothing);
    expect(find.text('Height'), findsNothing);
    expect(find.text('—'), findsNothing);
    expect(find.text('Not set'), findsNothing);
  });

  /// And it says why, rather than leaving a coach looking at a near-empty page wondering what
  /// broke. The limit is the client's decision (docs/10 §3), so it is stated as one.
  testWidgets('should explain a near-empty page instead of looking broken', (tester) async {
    await tester.pumpWidget(pageWith(FakeCoachRepository(detail: _basicOnly)));
    await tester.pumpAndSettle();

    expect(find.text('Only the basics are shared'), findsOneWidget);
  });

  /// The server answers "no grant" and "no such person" identically so an id cannot be used to
  /// learn who exists. For a coach that is access ending, not a server error.
  testWidgets('should read a refused client as access ending', (tester) async {
    await tester.pumpWidget(
      pageWith(
        FakeCoachRepository(
          failure: const ApiFailure(
            'You do not have access to this client.',
            code: 'CLIENT_NOT_FOUND',
            status: 404,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Access has ended'), findsOneWidget);
  });

  /// Rule 6 and rule 7: a real failure is still a failure, with the server's words and a retry.
  testWidgets('should show the server message and a retry when the read fails', (tester) async {
    await tester.pumpWidget(
      pageWith(
        FakeCoachRepository(
          failure: const ApiFailure('Could not load this client.', code: 'X', status: 500),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load this client.'), findsOneWidget);
    expect(find.text('Access has ended'), findsNothing);
  });
}

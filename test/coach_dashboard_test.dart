import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/errors/failures.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/domain/entities/coach_client.dart';
import 'package:health_pro/domain/entities/food.dart';
import 'package:health_pro/domain/entities/coach_dashboard.dart';
import 'package:health_pro/domain/entities/sent_invite.dart';
import 'package:health_pro/domain/repositories/coach_repository.dart';
import 'package:health_pro/presentation/features/coach/coach_dashboard_page.dart';
import 'package:health_pro/presentation/features/coach/dashboard_controller.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

import 'pumping.dart';

/// D-200. The screen a trainer, nutritionist or doctor opens their day on.
///
/// What is tested is not access control — the server decides that, and `client-view.spec.ts` holds
/// it to the docs/10 matrix. What is tested here is that the screen never INVENTS a number: a
/// client who shared only the basics must show no adherence, no streak and no weight, rather than
/// three zeroes that read as a person doing badly.

class FakeCoachRepository implements CoachRepository {
  FakeCoachRepository({
    this.summary,
    this.roster = const [],
    this.sent = const [],
    this.money,
    this.code,
    this.failure,
    this.earningsFail = false,
  });

  final CoachDashboard? summary;
  final List<CoachClient> roster;

  /// Named `sent` because `invites` is already a method on the repository — the inbox a CLIENT
  /// reads, which is a different list from the asks a coach has made.
  final List<SentInvite> sent;
  final CoachEarnings? money;
  final CoachReferral? code;
  final Failure? failure;

  /// The ledger being unreachable must not take the client list down with it.
  final bool earningsFail;

  @override
  Future<Either<Failure, DiaryDay>> clientDiary(int clientUserId, {String? date}) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, ClientProgress>> clientProgress(int clientUserId) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, CoachDashboard>> dashboard() async =>
      failure != null ? Left(failure!) : Right(summary ?? _empty);

  @override
  Future<Either<Failure, List<CoachClient>>> clients() async =>
      failure != null ? Left(failure!) : Right(roster);

  @override
  Future<Either<Failure, List<SentInvite>>> sentInvites() async =>
      failure != null ? Left(failure!) : Right(sent);

  @override
  Future<Either<Failure, CoachEarnings>> earnings({String? period}) async =>
      earningsFail || money == null
      ? const Left(ApiFailure('no ledger', code: 'X', status: 404))
      : Right(money!);

  @override
  Future<Either<Failure, CoachReferral>> referral() async =>
      code == null ? const Left(ApiFailure('no code', code: 'X', status: 404)) : Right(code!);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

const _empty = CoachDashboard(
  totalClients: 0,
  activeClients: 0,
  atRiskClients: 0,
  pendingInvites: 0,
  renewalsDue30d: 0,
  needsAttention: [],
);

/// Somebody who shared everything a verified coach can be given.
const _full = CoachClient(
  userId: 9,
  name: 'Ritu Agarwal',
  scopes: ['basic', 'progress'],
  tier: 'PRO',
  ageYears: 34,
  goal: 'fat_loss',
  adherencePct: 64,
  streakDays: 4,
  daysSinceLastLog: 1,
  weightKg: 72,
  weightChange30d: -1.4,
  status: 'active',
);

/// Somebody who shared only the basics. Every metric is absent, not zero.
const _basicOnly = CoachClient(
  userId: 11,
  name: 'Sameer Khan',
  scopes: ['basic'],
  tier: 'BASIC',
  ageYears: 29,
  goal: 'muscle_gain',
);

Widget pageWith(FakeCoachRepository repo) {
  Get
    ..reset()
    ..put<CoachRepository>(repo, permanent: true);

  // Through the container, not `new`: GetX fires `onInit` on registration, and a directly
  // constructed controller never loads — the screen would sit on its spinner forever.
  final controller = Get.put(CoachDashboardController(coach: repo), permanent: true);

  return GetMaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: CoachDashboardPage(controller: controller)),
  );
}

void main() {
  group('the four states (rule 6)', () {
    testWidgets('should offer one thing to do when nobody has been invited', (tester) async {
      await tester.pumpWidget(pageWith(FakeCoachRepository()));
      await settle(tester);

      expect(find.byType(EmptyView), findsOneWidget);
      expect(find.text('No clients yet'), findsOneWidget);
    });

    /// Rule 7: the server's own words, never the app's summary of them.
    testWidgets('should show the server message and a retry when it fails', (tester) async {
      await tester.pumpWidget(
        pageWith(
          FakeCoachRepository(
            failure: const ApiFailure('Could not load your clients.', code: 'X', status: 500),
          ),
        ),
      );
      await settle(tester);

      expect(find.text('Could not load your clients.'), findsOneWidget);
      expect(find.byType(FailedView), findsOneWidget);
    });

    testWidgets('should render the roster once it arrives', (tester) async {
      await tester.pumpWidget(
        pageWith(
          FakeCoachRepository(
            summary: const CoachDashboard(
              totalClients: 1,
              activeClients: 1,
              atRiskClients: 0,
              pendingInvites: 0,
              renewalsDue30d: 0,
              needsAttention: [],
            ),
            roster: const [_full],
          ),
        ),
      );
      await settle(tester);

      expect(find.text('Ritu Agarwal'), findsOneWidget);
      expect(find.byType(EmptyView), findsNothing);
    });
  });

  /// The point of the screen. Absent is a boundary the client drew; zero is a claim about how they
  /// are doing, and the two must never look the same.
  group('a client who shared only the basics', () {
    testWidgets('should show no adherence, no streak and no weight', (tester) async {
      await tester.pumpWidget(
        pageWith(
          FakeCoachRepository(
            summary: const CoachDashboard(
              totalClients: 1,
              activeClients: 0,
              atRiskClients: 0,
              pendingInvites: 0,
              renewalsDue30d: 0,
              needsAttention: [],
            ),
            roster: const [_basicOnly],
          ),
        ),
      );
      await settle(tester);

      expect(find.text('Sameer Khan'), findsOneWidget);
      expect(find.textContaining('0%'), findsNothing);
      expect(find.textContaining('0 days'), findsNothing);
      expect(find.textContaining('kg'), findsNothing);
    });

    testWidgets('should still name what they did share', (tester) async {
      await tester.pumpWidget(pageWith(FakeCoachRepository(roster: const [_basicOnly])));
      await settle(tester);

      expect(find.textContaining('Build muscle'), findsOneWidget);
    });
  });

  group('the numbers on the tiles', () {
    testWidgets('should count what the server counted, never recount it', (tester) async {
      await tester.pumpWidget(
        pageWith(
          FakeCoachRepository(
            summary: const CoachDashboard(
              totalClients: 48,
              activeClients: 38,
              atRiskClients: 6,
              pendingInvites: 2,
              renewalsDue30d: 3,
              // The server sent a smaller list than the count, which happens when a grant lapses
              // mid-read. The tile must show what the server said (rule 2), not `list.length`.
              needsAttention: [_full],
            ),
            roster: const [_full],
          ),
        ),
      );
      await settle(tester);

      expect(find.text('48'), findsOneWidget);
      expect(find.text('38'), findsOneWidget);
      expect(find.text('6'), findsWidgets);
    });
  });

  group('earnings', () {
    testWidgets('should show the month total and its breakdown', (tester) async {
      await tester.pumpWidget(
        pageWith(
          FakeCoachRepository(
            roster: const [_full],
            money: const CoachEarnings(
              period: '2026-09',
              totalPaise: 7865000,
              clientPaymentsPaise: 6540000,
              bonusPaise: 825000,
              otherPaise: 500000,
              daily: [1, 2, 3],
              pctChange: 18,
            ),
          ),
        ),
      );
      await settle(tester);

      expect(find.text('₹78,650'), findsWidgets);
      expect(find.text('₹65,400'), findsOneWidget);
    });

    /// A partner whose ledger is briefly unreachable has not lost their client list, so the screen
    /// drops the card rather than failing over it.
    testWidgets('should keep the roster when the ledger cannot be read', (tester) async {
      await tester.pumpWidget(
        pageWith(FakeCoachRepository(roster: const [_full], earningsFail: true)),
      );
      await settle(tester);

      expect(find.text('Ritu Agarwal'), findsOneWidget);
      expect(find.byType(FailedView), findsNothing);
    });
  });

  /// docs/12 §9 calls the at-risk list the most valuable widget a coach gets, so it sits above the
  /// roster — and it is never sorted by weight lost or streak, which docs/05 §6 bans as ranking.
  testWidgets('should put who needs attention above everyone else', (tester) async {
    const quiet = CoachClient(
      userId: 12,
      name: 'Neha Gupta',
      scopes: ['basic', 'progress'],
      adherencePct: 20,
      daysSinceLastLog: 9,
      status: 'no_recent_logs',
    );

    await tester.pumpWidget(
      pageWith(
        FakeCoachRepository(
          summary: const CoachDashboard(
            totalClients: 2,
            activeClients: 1,
            atRiskClients: 1,
            pendingInvites: 0,
            renewalsDue30d: 0,
            needsAttention: [quiet],
          ),
          roster: const [_full, quiet],
        ),
      ),
    );
    await settle(tester);

    expect(find.text('Needs attention'), findsWidgets);
    // A long absence is stated as a fact about the diary, never as a verdict on the person.
    expect(find.text('No recent logs'), findsWidgets);
    expect(find.text('Inactive'), findsNothing);
  });
}

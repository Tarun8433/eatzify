import 'dart:async';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/ads/rewarded_ad_gate.dart';
import 'package:health_pro/core/home_widget/home_screen_widget.dart';
import 'package:health_pro/core/home_widget/home_widget_actions.dart';
import 'package:health_pro/core/network/api_client.dart';
import 'package:health_pro/core/notifications/reminder_copy.dart';
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/core/storage/secure_store.dart';
import 'package:health_pro/core/theme/app_theme.dart';
import 'package:health_pro/data/datasources/local/gym_local_data_source.dart';
import 'package:health_pro/data/datasources/remote/auth_remote_data_source.dart';
import 'package:health_pro/data/datasources/remote/billing_remote_data_source.dart';
import 'package:health_pro/data/datasources/remote/chat_remote_data_source.dart';
import 'package:health_pro/data/datasources/remote/chat_socket.dart';
import 'package:health_pro/data/datasources/remote/coach_remote_data_source.dart';
import 'package:health_pro/data/datasources/remote/diary_remote_data_source.dart';
import 'package:health_pro/data/datasources/remote/google_auth_data_source.dart';
import 'package:health_pro/data/datasources/remote/gym_remote_data_source.dart';
import 'package:health_pro/data/datasources/remote/measurements_remote_data_source.dart';
import 'package:health_pro/data/datasources/remote/notifications_remote_data_source.dart';
import 'package:health_pro/data/datasources/remote/plan_remote_data_source.dart';
import 'package:health_pro/data/datasources/remote/privacy_remote_data_source.dart';
import 'package:health_pro/data/datasources/remote/profile_remote_data_source.dart';
import 'package:health_pro/data/datasources/remote/scan_remote_data_source.dart';
import 'package:health_pro/data/datasources/remote/tickets_remote_data_source.dart';
import 'package:health_pro/data/repositories/auth_repository_impl.dart';
import 'package:health_pro/data/repositories/billing_repository_impl.dart';
import 'package:health_pro/data/repositories/chat_repository_impl.dart';
import 'package:health_pro/data/repositories/coach_repository_impl.dart';
import 'package:health_pro/data/repositories/diary_repository_impl.dart';
import 'package:health_pro/data/repositories/gym_repository_impl.dart';
import 'package:health_pro/data/repositories/health_repository_impl.dart';
import 'package:health_pro/data/repositories/measurements_repository_impl.dart';
import 'package:health_pro/data/repositories/notifications_repository_impl.dart';
import 'package:health_pro/data/repositories/plan_repository_impl.dart';
import 'package:health_pro/data/repositories/privacy_repository_impl.dart';
import 'package:health_pro/data/repositories/profile_repository_impl.dart';
import 'package:health_pro/data/repositories/reminder_repository_impl.dart';
import 'package:health_pro/data/repositories/scan_repository_impl.dart';
import 'package:health_pro/data/repositories/tickets_repository_impl.dart';
import 'package:health_pro/domain/repositories/billing_repository.dart';
import 'package:health_pro/domain/repositories/chat_repository.dart';
import 'package:health_pro/domain/repositories/coach_repository.dart';
import 'package:health_pro/domain/repositories/diary_repository.dart';
import 'package:health_pro/domain/repositories/gym_repository.dart';
import 'package:health_pro/domain/repositories/health_repository.dart';
import 'package:health_pro/domain/repositories/measurements_repository.dart';
import 'package:health_pro/domain/repositories/notifications_repository.dart';
import 'package:health_pro/domain/repositories/plan_repository.dart';
import 'package:health_pro/domain/repositories/privacy_repository.dart';
import 'package:health_pro/domain/repositories/profile_repository.dart';
import 'package:health_pro/domain/repositories/reminder_repository.dart';
import 'package:health_pro/domain/repositories/scan_repository.dart';
import 'package:health_pro/domain/repositories/tickets_repository.dart';
import 'package:health_pro/domain/usecases/plan_reminders.dart';
import 'package:health_pro/domain/usecases/sync_health.dart';
import 'package:health_pro/presentation/features/account/account_controller.dart';
import 'package:health_pro/presentation/features/auth/login_controller.dart';
import 'package:health_pro/presentation/features/auth/login_page.dart';
import 'package:health_pro/presentation/features/gym/gym_controller.dart';
import 'package:health_pro/presentation/features/home/home_controller.dart';
import 'package:health_pro/presentation/features/onboarding/onboarding_controller.dart';
import 'package:health_pro/presentation/features/onboarding/onboarding_page.dart';
import 'package:health_pro/presentation/features/plan/plan_controller.dart';
import 'package:health_pro/presentation/features/progress/progress_controller.dart';
import 'package:health_pro/presentation/features/splash/splash_page.dart';
import 'package:health_pro/presentation/features/welcome/welcome_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/shell/client_shell.dart';
import 'package:health_pro/presentation/shell/nav_controller.dart';
import 'package:home_widget/home_widget.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The home-screen widget (D-210). Failing to set this up must never stop the app starting — a
  // launcher that refused the app group is a widget nobody sees, not an app nobody can open.
  try {
    await HomeScreenWidget.init();
    await HomeWidgetActions.register(widgetBackgroundTap);
    // A tile that needs a screen: route it once the app is up — now, and on every later tap.
    HomeWidgetActions.taps.listen(_openFromWidget);
  } on Object {
    // Swallowed on purpose. There is nothing a user could do and nothing worth showing them.
  }

  // Reminders (D-222). Same rule: a phone that will not take notifications still opens the app.
  try {
    await _initReminders();
  } on Object {
    // Nothing to show; the Reminders screen says so when it is opened.
  }

  runApp(const EatzifyApp());

  // A tap that started the app cold. After the first frame, so the shell it routes exists.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      _openFromWidget(await HomeWidgetActions.launchAction());
    } on Object {
      // Nothing to route is the normal case.
    }
  });
}

/// A widget tap that arrived without the app: only the glass button sends one (D-219).
///
/// Top-level and annotated, because it runs in a background isolate the VM has to find by name.
@pragma('vm:entry-point')
Future<void> widgetBackgroundTap(Uri? uri) async {
  if (HomeWidgetAction.from(uri) != HomeWidgetAction.addWater) return;
  final total = await _addGlassOfWater();
  if (total != null) await _replanAfterGlass(total);
}

/// "Log a glass" on a water reminder, with the app closed (D-222). Top-level and annotated for the
/// same reason as [widgetBackgroundTap]: it runs in an isolate the VM finds by name.
@pragma('vm:entry-point')
Future<void> reminderBackgroundTap(NotificationResponse response) async {
  if (response.actionId != ReminderRepositoryImpl.logGlassAction) return;
  try {
    // The widget's figures live in the app group on iOS, and this isolate has not been told which.
    await HomeScreenWidget.init();
  } on Object {
    // Android has no app group; the read below still works.
  }
  final total = await _addGlassOfWater();
  if (total != null) await _replanAfterGlass(total);
}

Future<void> _initReminders() => ReminderRepositoryImpl.init(
  logGlassLabel: phoneLocalizations().reminderLogGlass,
  onTap: _openFromReminder,
  onBackgroundTap: reminderBackgroundTap,
);

/// A glass logged with the app closed may have met the target, so the rest of today's water
/// reminders may need to go. Runs in the background isolate, with nothing from the app's DI.
Future<void> _replanAfterGlass(int totalMl) async {
  try {
    await _initReminders();
    await RefreshReminders(ReminderRepositoryImpl(copy: reminderCopy)).waterLogged(totalMl);
  } on Object {
    // The week stays as it was; the next open re-plans it.
  }
}

/// A reminder tapped with the app running, or its button pressed while it is open.
void _openFromReminder(NotificationResponse response) {
  if (response.actionId == ReminderRepositoryImpl.logGlassAction) {
    unawaited(_addGlassFromApp());
    return;
  }
  if (Get.isRegistered<NavController>()) Get.find<NavController>().current = ClientTab.home;
}

/// Where the API lives.
///
/// Top-level because the home-screen widget's background isolate needs it too, and a second copy
/// would be a second thing to change when the host moves.
String resolveBaseUrl() {
  const override = String.fromEnvironment('API_BASE_URL');
  const live = 'http://187.127.137.245:3002/api/v1';
  const dev = 'http://THINKs-MacBook-Air.local:3001/api/v1';

  return override.isNotEmpty ? override : (kReleaseMode ? live : dev);
}

/// A glass of water, logged from the home screen with the app closed.
///
/// **Runs in a background isolate**, where none of the app's dependency injection exists. So it
/// builds the one client it needs and nothing else — and it is the ONLY widget action that writes,
/// because it is one integer with one meaning. Anything requiring a choice opens the app.
///
/// Water is stored as the day's TOTAL (D-86), so this adds a glass to what the widget was last
/// told and hands the server the new figure. Two taps in the same second would race; the losing
/// one costs a glass, which is the cheaper failure than double-counting somebody's day.
/// Returns the new total, or null when nothing was logged.
@pragma('vm:entry-point')
Future<int?> _addGlassOfWater() async {
  // The app's own store, not a raw key. One place decides where a token lives.
  final session = await SecureStore().read();
  if (session == null) return null;

  final current = await HomeWidget.getWidgetData<int>('water_ml');
  final next = HomeScreenWidget.nextWaterTotal(current);

  final client = ApiClient(baseUrl: resolveBaseUrl());
  client.dio.options.headers['Authorization'] = 'Bearer ${session.accessToken}';

  try {
    await client.dio.post<void>(
      '/measurements',
      data: {'kind': 'water_ml', 'value': next, 'unit': 'ml'},
    );
    // Only after the server took it. Showing the new figure before it landed would be the widget
    // telling somebody they drank something they did not.
    await HomeWidget.saveWidgetData<int>('water_ml', next);
    await HomeScreenWidget.publish(
      waterMl: next,
      waterTargetMl: await HomeWidget.getWidgetData<int>('water_target_ml'),
      steps: await HomeWidget.getWidgetData<int>('steps'),
      kcal: await HomeWidget.getWidgetData<int>('kcal'),
      kcalTarget: await HomeWidget.getWidgetData<int>('kcal_target'),
      burnedKcal: await HomeWidget.getWidgetData<int>('burned_kcal'),
    );
    return next;
  } on Object {
    // The glass is not logged and the widget still shows the old figure, which is the truth.
    return null;
  }
}

/// A widget button that needs a screen. Routing happens once the app is up.
void _openFromWidget(HomeWidgetAction action) {
  if (action == HomeWidgetAction.unknown || !Get.isRegistered<NavController>()) return;

  // Only an iOS "+" arrives here as water: an iOS widget can only open its app, so the glass is
  // added now (D-219). Android's "+" logs in the background and never opens the app.
  if (action == HomeWidgetAction.addWater) unawaited(_addGlassFromApp());

  Get.find<NavController>().current = switch (action) {
    HomeWidgetAction.openSteps => ClientTab.progress,
    _ => ClientTab.home,
  };
}

Future<void> _addGlassFromApp() async {
  await _addGlassOfWater();
  if (Get.isRegistered<HomeController>()) await Get.find<HomeController>().load(quietly: true);
}

/// Root. docs/14: GetX for state, routing and DI.
class EatzifyApp extends StatelessWidget {
  const EatzifyApp({super.key});

  /// Overridable so tests can inject fakes without touching the keychain or the network.
  static void Function()? bindingOverride;

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // No themeMode: the default already follows the phone. docs/14 §5 wants a switch on the
      // settings screen; until that exists the OS setting is the user's stated preference, and
      // overriding it is the wrong default. Both themes are contrast-measured and render-tested.
      // docs/14 §5: the settings screen advertises a theme switch, so both themes must work.
      // themeMode defaults to ThemeMode.system — the honest default until that switch exists.
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      initialBinding: BindingsBuilder<SessionController>(bindingOverride ?? _bind),
      // Tapping anywhere outside a field dismisses the keyboard, app-wide. Doing it here rather
      // than per-screen means a new page cannot forget it.
      builder: (context, child) => GestureDetector(
        // Translucent so the tap still reaches whatever was underneath — this dismisses the
        // keyboard without swallowing the button the user was actually aiming for.
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child,
      ),
      home: const RootGate(),
    );
  }

  static void _bind() {
    // BACKEND_DOMAIN from api/.env.example. A device cannot reach the host's localhost, so this
    // needs a reachable address before sign-in works.
    //
    // The dev default is the Mac's BONJOUR NAME, not its LAN IP (D-93). A baked IP is wrong the
    // first time the machine changes network: this one was 192.168.2.18, became 172.20.10.4 on a
    // phone hotspot, and was back on 192.168.2.18 an hour later — each change is a 20-second
    // connection timeout with no clue as to why. `.local` is resolved by mDNS and follows the
    // machine, so it survives all of that without a rebuild. On a physical iPhone it needs the
    // local-network permission declared in ios/Runner/Info.plist.
    //
    // ponytail: override per-machine with --dart-define=API_BASE_URL=... — a tunnel URL, or
    // another developer's own hostname.
    //
    // A RELEASE build defaults to the live server (D-160): an APK handed to a tester must not
    // ship pointing at a developer's laptop. Debug keeps the Mac; the dart-define wins over both.
    final client = ApiClient(baseUrl: resolveBaseUrl());
    final auth = AuthRepositoryImpl(AuthRemoteDataSource(client.dio));
    // Held rather than only registered: SessionController reads it on boot to check a cached
    // `onboarding_required` against the server.
    final profile = ProfileRepositoryImpl(ProfileRemoteDataSource(client.dio));
    Get
      ..put<ProfileRepository>(profile, permanent: true)
      // docs/12 §6 coach onboarding. Registered for everyone, because level 1 is "signup +
      // agreement" and any account may take it — the repository knowing about partners does not
      // make the user one.
      ..put<CoachRepository>(
        CoachRepositoryImpl(CoachRemoteDataSource(client.dio)),
        permanent: true,
      )
      ..put<MeasurementsRepository>(
        MeasurementsRepositoryImpl(MeasurementsRemoteDataSource(client.dio)),
        permanent: true,
      )
      ..put<DiaryRepository>(
        DiaryRepositoryImpl(DiaryRemoteDataSource(client.dio)),
        permanent: true,
      )
      ..put<PlanRepository>(PlanRepositoryImpl(PlanRemoteDataSource(client.dio)), permanent: true)
      // The server's own messages — renewal notices today (docs/11 §8), admin sends later.
      ..put<NotificationsRepository>(
        NotificationsRepositoryImpl(NotificationsRemoteDataSource(client.dio)),
        permanent: true,
      )
      ..put<BillingRepository>(
        BillingRepositoryImpl(BillingRemoteDataSource(client.dio)),
        permanent: true,
      )
      // docs/13 §3 and §9: consents, a copy of everything, and the way out (D-233).
      ..put<PrivacyRepository>(
        PrivacyRepositoryImpl(PrivacyRemoteDataSource(client.dio)),
        permanent: true,
      )
      // Support conversations (docs/14 §6's help screen, D-228).
      ..put<TicketsRepository>(
        TicketsRepositoryImpl(TicketsRemoteDataSource(client.dio)),
        permanent: true,
      )
      // Meal-photo scanning (D-238). Who may scan is the server's answer per tier; the ad is only
      // loaded for a tier that needs one, and the SDK starts on that first tap, not at launch.
      ..put<ScanRepository>(ScanRepositoryImpl(ScanRemoteDataSource(client.dio)), permanent: true)
      // The Gym section (ADR-013). Its phone-side store is the encrypted Hive box: the workout in
      // progress, workouts waiting to be sent, and the last plan so a session starts with no signal.
      ..put<GymRepository>(
        GymRepositoryImpl(GymRemoteDataSource(client.dio), HiveGymLocalDataSource(SecureStore())),
        permanent: true,
      )
      ..put(RewardedAdGate(), permanent: true)
      // HealthKit / Health Connect (D-214). Registered on every platform; it reports
      // `unsupported` where there is nothing behind it, and Home simply carries no activity.
      ..put<HealthRepository>(HealthRepositoryImpl(), permanent: true)
      // Reminders, scheduled on the phone (D-222).
      ..put<ReminderRepository>(ReminderRepositoryImpl(copy: reminderCopy), permanent: true)
      ..put(RefreshReminders(Get.find<ReminderRepository>()), permanent: true)
      // One instance, so Home and the connect screen share what it has already sent.
      ..put(
        SyncHealth(
          health: Get.find<HealthRepository>(),
          measurements: Get.find<MeasurementsRepository>(),
          diary: Get.find<DiaryRepository>(),
        ),
        permanent: true,
      );
    final session = Get.put(
      SessionController(store: SecureStore(), auth: auth, profile: profile),
      permanent: true,
    );
    client.attachAuth(
      accessToken: () => session.accessToken,
      onRefresh: session.refreshAccessToken,
    );

    // Coach chat (docs/02 FR-5.5). The socket needs the same token the REST calls carry, and the
    // reader's own id to tell their messages from the other side's.
    Get.put<ChatRepository>(
      ChatRepositoryImpl(
        ChatRemoteDataSource(client.dio),
        ChatSocket(baseUrl: resolveBaseUrl(), token: () => session.accessToken),
        me: () => int.tryParse(session.userId ?? '') ?? 0,
      ),
      permanent: true,
    );
    Get
      ..put(NavController(), permanent: true)
      // Shared by the Gym screen and Home's workout card; rebuilt after a sign-out drops it.
      ..lazyPut(
        () =>
            GymController(gym: Get.find<GymRepository>(), reminders: Get.find<RefreshReminders>()),
        fenix: true,
      )
      ..lazyPut(
        () => LoginController(
          auth: auth,
          session: session,
          // Only when the OAuth client id was built in — see GoogleAuthDataSource. Unconfigured,
          // this is null and the sign-in screen simply has no Google button on it.
          googleIdToken: GoogleAuthDataSource.isConfigured ? GoogleAuthDataSource().idToken : null,
        ),
        fenix: true,
      );

    attachSessionCleanup(session);
  }

  /// Wires [clearUserScopedState] to the end of a session.
  ///
  /// The worker is never disposed on purpose: it lives exactly as long as the app, and a binding
  /// that quietly stopped listening would bring the bug straight back.
  static void attachSessionCleanup(SessionController session) {
    ever(session.status, (status) {
      if (status == AuthStatus.signedOut) clearUserScopedState();
    });
  }

  /// Drops everything holding one user's data.
  ///
  /// Every tab controller is registered `permanent: true`, and `Get.put` hands back an existing
  /// instance WITHOUT re-running `onInit`. So after a sign-out and a sign-in as somebody else, the
  /// same four controllers were still holding the previous user's diary, plan, measurements and
  /// profile, and nothing ever asked them to reload — the data only changed on a restart. Deleting
  /// them means the next `Get.put` builds a fresh one, which loads for whoever is signed in now.
  ///
  /// docs/13 also wants it gone at sign-out rather than at the next sign-in: health data must not
  /// sit in memory after the person it belongs to has left.
  static void clearUserScopedState() {
    void drop<T>() {
      if (Get.isRegistered<T>()) Get.delete<T>(force: true);
    }

    drop<HomeController>();
    drop<PlanController>();
    drop<ProgressController>();
    drop<AccountController>();
    // Holds a half-finished set of answers, which the next person must not inherit.
    drop<OnboardingController>();
    // The Gym's plan, library and any workout in progress — in memory and on disk (ADR-013).
    drop<GymController>();
    if (Get.isRegistered<GymRepository>()) {
      unawaited(Get.find<GymRepository>().clearLocal().catchError((Object _) {}));
    }

    // The last person's reminders must not ring for the next one. Their settings went with the
    // rest of the secure store.
    if (Get.isRegistered<ReminderRepository>()) {
      unawaited(Get.find<ReminderRepository>().cancelAll().catchError((Object _) {}));
    }

    // Not user data, so it is reset rather than dropped: the next sign-in should open on Home, not
    // on whichever tab the last person happened to leave behind.
    if (Get.isRegistered<NavController>()) Get.find<NavController>().current = ClientTab.home;
  }
}

/// The only place routing depends on auth state. docs/14 §3 asks for guards declared on routes
/// rather than checks inside pages; with four states and three destinations, one exhaustive switch
/// at the root is the same guarantee with less machinery — and it cannot be forgotten on a new page.
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Get.find<SessionController>();
    return Obx(
      () => switch (session.status.value) {
        AuthStatus.restoring => const SplashPage(),
        // Splash → intro → sign-in → registration (D-92). `signedOut` covers the first two
        // destinations because being signed out is the only thing they have in common; the
        // carousel is not an auth state and must not become one.
        AuthStatus.signedOut => session.introSeen.value ? const LoginPage() : const WelcomePage(),
        // Signed in with a number the server has no profile for — the registration screen.
        AuthStatus.onboardingRequired => const OnboardingPage(),
        // EVERY account lands on the client shell, coach or not (D-174).
        //
        // Swapping one shell for the other was wrong in a way no test caught: a nutritionist who
        // becomes a partner is still a person who tracks their own food, and replacing their tabs
        // took their own Home, Plan and Progress away. A coach is a client of their own app.
        // The coach surface is reached from the You tab instead, so it ADDS rather than replaces.
        AuthStatus.signedIn => const ClientShell(),
      },
    );
  }
}

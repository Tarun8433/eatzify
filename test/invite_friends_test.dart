import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro/presentation/features/account/invite_friends.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// D-192. A user inviting someone they know, without Eatzify learning who they know.
///
/// The share itself is a platform channel and belongs to the OS, so what is testable — and what
/// actually matters — is what leaves the app: one message, carrying a link and nothing else.

Future<AppLocalizations> localisationsFor(WidgetTester tester, Locale locale) async {
  late AppLocalizations l;

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          l = AppLocalizations.of(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );

  return l;
}

void main() {
  testWidgets('the invite carries the link and nothing about the sender', (tester) async {
    final l = await localisationsFor(tester, const Locale('en'));

    final message = InviteFriends.message(l);

    expect(message, contains(InviteFriends.link));
    // No code, no id, no phone number. docs/12 §3 locks attribution to a partner code entered at
    // signup, so a plain user's invite has nothing to attribute and must not pretend otherwise.
    expect(message, isNot(contains('?')));
  });

  /// Rule 5 and the l10n standard: the message is a translated string with a placeholder, not two
  /// strings glued together — which is how a Hindi invite ends up with English word order.
  testWidgets('it is translated, with the link still in it', (tester) async {
    final hindi = InviteFriends.message(await localisationsFor(tester, const Locale('hi')));
    final english = InviteFriends.message(await localisationsFor(tester, const Locale('en')));

    expect(hindi, isNot(english));
    expect(hindi, contains(InviteFriends.link));
  });
}

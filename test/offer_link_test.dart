import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/session/session_controller.dart';
import 'package:health_pro/core/storage/secure_store.dart';
import 'package:health_pro/domain/entities/session.dart';
import 'package:health_pro/presentation/features/billing/offer_link_controller.dart';

import 'fakes.dart';

/// D-265: `eatzify://offer/<code>` — which links count, and when the offer opens.
void main() {
  const code = 'Ab3_dE-f9GhIjKlMnOpQrS';
  const pendingKey = 'offer.pending_code';

  group('offerCode', () {
    test('should read the code from a well-formed offer link', () {
      expect(OfferLinkController.offerCode(Uri.parse('eatzify://offer/$code')), code);
    });

    test('should accept a trailing slash', () {
      expect(OfferLinkController.offerCode(Uri.parse('eatzify://offer/$code/')), code);
    });

    for (final link in [
      'eatzify://offer/short', // under 16
      'eatzify://offer/${'a' * 65}', // over 64
      'eatzify://offer/abc.def%20ghijklmnop', // outside base64url
      'eatzify://offer/$code/extra', // more than one segment
      'eatzify://offer/', // no code
      'eatzify://plan/$code', // another host
      'https://offer/$code', // another scheme
      'https://eatzify-api.zynthovo.com/offer/$code', // the web page, not the app link
    ]) {
      test('should ignore $link', () {
        expect(OfferLinkController.offerCode(Uri.parse(link)), isNull);
      });
    }
  });

  group('opening', () {
    late StreamController<Uri> links;
    late FakeSecureStorage storage;
    late SessionController session;
    late List<String> opened;

    Future<void> boot({bool signedIn = false}) async {
      Get.reset();
      links = StreamController<Uri>();
      storage = FakeSecureStorage();
      if (signedIn) {
        storage.data
          ..['auth.access'] = 'a1'
          ..['auth.refresh'] = 'r1'
          ..['auth.user_id'] = 'u-1'
          ..['auth.onboarding_required'] = 'false';
      }
      opened = [];
      final store = SecureStore(storage: storage);
      session = SessionController(
        store: store,
        auth: FakeAuthRepository(),
        profile: FakeProfileRepository(),
        splashFloor: Duration.zero,
      );
      Get
        ..put(session, permanent: true)
        ..put(
          OfferLinkController(
            links: links.stream,
            session: session,
            store: store,
            open: opened.add,
          ),
          permanent: true,
        );
      await pumpEventQueue();
    }

    Future<void> signIn({bool onboardingRequired = false}) async {
      await session.adopt(
        Session(
          accessToken: 'a2',
          refreshToken: 'r2',
          userId: 'u-2',
          roles: const ['client'],
          onboardingRequired: onboardingRequired,
        ),
      );
      await pumpEventQueue();
    }

    tearDown(() => links.close());

    test('should open the offer at once when signed in', () async {
      await boot(signedIn: true);
      expect(session.status.value, AuthStatus.signedIn);

      links.add(Uri.parse('eatzify://offer/$code'));
      await pumpEventQueue();

      expect(opened, [code]);
      expect(storage.data[pendingKey], isNull, reason: 'nothing to hold for later');
    });

    test('should keep the code when signed out and open it after sign-in', () async {
      await boot();
      expect(session.status.value, AuthStatus.signedOut);

      links.add(Uri.parse('eatzify://offer/$code'));
      await pumpEventQueue();

      expect(opened, isEmpty);
      expect(storage.data[pendingKey], code);

      await signIn();

      expect(opened, [code]);
      expect(storage.data[pendingKey], isNull, reason: 'opened once, not on every sign-in');
    });

    test('should wait until onboarding is finished before opening', () async {
      await boot();
      links.add(Uri.parse('eatzify://offer/$code'));
      await pumpEventQueue();

      await signIn(onboardingRequired: true);
      expect(opened, isEmpty);

      await session.markOnboardingComplete();
      await pumpEventQueue();
      expect(opened, [code]);
    });

    test('should open a code kept by an earlier run once that run signs in', () async {
      await boot();
      storage.data[pendingKey] = code;

      await signIn();

      expect(opened, [code]);
    });

    test('should ignore a link that is not an offer', () async {
      await boot(signedIn: true);

      links
        ..add(Uri.parse('eatzify://plan/$code'))
        ..add(Uri.parse('eatzify://offer/nope'));
      await pumpEventQueue();

      expect(opened, isEmpty);
    });
  });
}

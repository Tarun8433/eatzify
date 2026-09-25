import 'package:flutter/widgets.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:share_plus/share_plus.dart';

/// Inviting somebody you know, from the client app.
///
/// **It never reads the address book.** Handing the OS a message and letting the person choose who
/// to send it to gets the same outcome as a contact picker, and it is the difference between the
/// user inviting a friend and Eatzify holding a list of people who have not heard of Eatzify.
/// docs/13 §4 is collect less, and the DPDP Act attaches duties to personal data about third
/// parties who never agreed to anything — an uploaded address book is exactly that.
///
/// The contacts are still right there: WhatsApp, Messages and mail all open on the same list the
/// user already has, in the app that already has permission to read it.
abstract final class InviteFriends {
  /// Where the invite points. Build-time, the same way the API base URL is set — the store listing
  /// moves between dev, beta and production and a literal here would send testers to the wrong one.
  static const link = String.fromEnvironment('INVITE_LINK', defaultValue: 'https://eatzify.app');

  /// What gets shared. Separated from the sharing so it can be read in a test without a platform
  /// channel, and so the wording stays a translated string rather than a concatenation.
  static String message(AppLocalizations l) => l.inviteFriendsMessage(link);

  static Future<void> share(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final box = context.findRenderObject() as RenderBox?;

    await Share.share(
      message(l),
      // Only the targets that have one use it — mail being the obvious case.
      subject: l.inviteFriendsSubject,
      // iPad anchors the popover to this. Without it the sheet lands in a corner, or the platform
      // throws outright; every other platform ignores it.
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    );
  }
}

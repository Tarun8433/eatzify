import 'package:flutter/material.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a page of the website. Injectable so a test can see WHICH page a tap asked for without a
/// browser; a build never swaps it.
typedef UrlOpener = Future<bool> Function(Uri uri);

/// An in-app browser tab rather than an external app: the person reads the policy and comes back
/// to the screen they were on, which is where the decision they were making still is.
Future<bool> openInAppBrowser(Uri uri) => launchUrl(uri, mode: LaunchMode.inAppBrowserView);

/// Opens [uri], saying so if it could not — a legal link that silently does nothing is worse than
/// one that is missing, because the person believes they read something they never saw.
Future<void> openSiteLink(
  BuildContext context,
  Uri uri, {
  UrlOpener opener = openInAppBrowser,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final failed = AppLocalizations.of(context).legalOpenFailed;
  var opened = false;
  try {
    opened = await opener(uri);
  } on Object {
    opened = false;
  }
  if (!opened) messenger?.showSnackBar(SnackBar(content: Text(failed)));
}

/// "By …, you agree to our X and Y." with X and Y tappable — the line under a button that commits
/// someone to something. Wraps rather than truncates at large text (rule 12).
class AgreementLine extends StatelessWidget {
  const AgreementLine({
    required this.lead,
    required this.links,
    super.key,
    this.opener = openInAppBrowser,
  });

  final String lead;
  final List<({String label, Uri uri})> links;
  final UrlOpener opener;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final small = theme.textTheme.bodySmall;
    final link = small?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
    );

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('$lead ', style: small),
        for (final (i, item) in links.indexed) ...[
          if (i > 0) Text(' ${l.legalAnd} ', style: small),
          // A real button, not a gesture on a span: it gets a 48 dp target and a semantics role.
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              minimumSize: const Size(0, AppSpacing.minTouchTarget),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            onPressed: () => openSiteLink(context, item.uri, opener: opener),
            child: Text(item.label, style: link),
          ),
        ],
      ],
    );
  }
}

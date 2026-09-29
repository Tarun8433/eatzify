import 'package:flutter/material.dart';
import 'package:health_pro/core/config/site_links.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:health_pro/presentation/widgets/site_link.dart';

/// Terms, privacy policy, refunds and contact, from You. Each opens the website — the same page the
/// payment gateway reviewed and the Play listing links to — rather than a copy that could drift.
class LegalLinksCard extends StatelessWidget {
  const LegalLinksCard({super.key, this.opener = openInAppBrowser});

  final UrlOpener opener;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final rows = [
      (icon: Icons.description_outlined, label: l.legalTerms, uri: SiteLinks.terms),
      (icon: Icons.shield_outlined, label: l.legalPrivacy, uri: SiteLinks.privacy),
      (icon: Icons.currency_rupee, label: l.legalRefunds, uri: SiteLinks.refunds),
      (icon: Icons.support_agent_outlined, label: l.legalContact, uri: SiteLinks.contact),
    ];

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      // ListTile ink needs a Material of its own on a decorated card.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (final row in rows)
              ListTile(
                leading: Icon(row.icon),
                title: Text(row.label),
                // Says it leaves the screen, so the jump to a browser tab is not a surprise.
                trailing: Icon(Icons.open_in_new, semanticLabel: l.legalOpensWebsite),
                onTap: () => openSiteLink(context, row.uri, opener: opener),
              ),
          ],
        ),
      ),
    );
  }
}

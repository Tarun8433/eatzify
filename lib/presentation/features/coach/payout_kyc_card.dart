import 'package:flutter/material.dart';
import 'package:health_pro/core/format/rupees.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/domain/entities/payout_kyc.dart';
import 'package:health_pro/presentation/features/coach/payout_kyc_page.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// On the Clients tab only while it matters (D-255): details needed because a payout is due, or
/// details sent and waiting for review. Nothing at all before money is waiting.
class PayoutKycCard extends StatelessWidget {
  const PayoutKycCard({required this.kyc, required this.onSent, super.key});

  final PayoutKyc kyc;

  /// Called once details are sent, so the dashboard re-reads what the server now says.
  final VoidCallback onSent;

  static bool shows(PayoutKyc kyc) => kyc.required || kyc.isPending;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (kyc.isPending) {
      return HintCard(
        icon: Icons.hourglass_top_outlined,
        title: l.kycPendingTitle,
        text: l.kycPendingBody,
      );
    }
    return AppCard(
      accent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.kycCardTitle, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            kyc.isRejected ? l.kycRejectedBody : l.kycCardBody(Rupees.format(kyc.duePaise ~/ 100)),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(AppSizes.primaryButton),
            ),
            onPressed: () async {
              if (await PayoutKycPage.open() ?? false) onSent();
            },
            child: Text(l.kycCardTitle),
          ),
        ],
      ),
    );
  }
}

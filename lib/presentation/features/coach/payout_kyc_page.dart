import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/domain/entities/payout_kyc.dart';
import 'package:health_pro/domain/repositories/coach_repository.dart';
import 'package:health_pro/presentation/features/coach/payout_kyc_controller.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// docs/12 §5 KYC, asked for only when a payout is due (D-255). Returns true to the caller once the
/// details are sent, so the dashboard can re-read its state.
class PayoutKycPage extends StatefulWidget {
  const PayoutKycPage({super.key});

  static Future<bool?>? open() => Get.to<bool>(
    () => const PayoutKycPage(),
    binding: BindingsBuilder<void>(() {
      Get.lazyPut(() => PayoutKycController(coach: Get.find<CoachRepository>()));
    }),
  );

  @override
  State<PayoutKycPage> createState() => _PayoutKycPageState();
}

class _PayoutKycPageState extends State<PayoutKycPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _pan = TextEditingController();
  final _account = TextEditingController();
  final _ifsc = TextEditingController();
  final _gstin = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _pan, _account, _ifsc, _gstin]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = Get.find<PayoutKycController>();

    String? check(String? value, RegExp shape) =>
        shape.hasMatch(value?.trim().toUpperCase() ?? '') ? null : l.kycInvalid;

    return Scaffold(
      appBar: AppBar(title: Text(l.kycFormTitle)),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            TextFormField(
              controller: _name,
              decoration: InputDecoration(labelText: l.kycHolderName),
              textCapitalization: TextCapitalization.words,
              validator: (v) {
                final n = v?.trim().length ?? 0;
                return n < PayoutKycController.nameMin || n > PayoutKycController.nameMax
                    ? l.kycInvalid
                    : null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _pan,
              decoration: InputDecoration(labelText: l.kycPan),
              textCapitalization: TextCapitalization.characters,
              validator: (v) => check(v, PayoutKycController.pan),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _account,
              decoration: InputDecoration(labelText: l.kycAccount),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) => check(v, PayoutKycController.account),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _ifsc,
              decoration: InputDecoration(labelText: l.kycIfsc),
              textCapitalization: TextCapitalization.characters,
              validator: (v) => check(v, PayoutKycController.ifsc),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _gstin,
              decoration: InputDecoration(labelText: l.kycGstin),
              textCapitalization: TextCapitalization.characters,
              validator: (v) =>
                  (v?.trim().isEmpty ?? true) ? null : check(v, PayoutKycController.gstin),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l.kycPrivacyNote,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            // Rule 7: a refusal is the server's words.
            Obx(
              () => c.error.value == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: Text(
                        c.error.value!,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                      ),
                    ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Obx(
              () => FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(AppSizes.primaryButton),
                ),
                onPressed: c.saving.value ? null : () => _submit(c),
                child: Text(l.kycSubmit),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(PayoutKycController c) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final gstin = _gstin.text.trim().toUpperCase();
    final sent = await c.submit(
      PayoutKycSubmission(
        holderName: _name.text.trim(),
        pan: _pan.text.trim().toUpperCase(),
        accountNumber: _account.text.trim(),
        ifsc: _ifsc.text.trim().toUpperCase(),
        gstin: gstin.isEmpty ? null : gstin,
      ),
    );
    if (!sent || !mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(l.kycSaved)));
    Get.back<bool>(result: true);
  }
}

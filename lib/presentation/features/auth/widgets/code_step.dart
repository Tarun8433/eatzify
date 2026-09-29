import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/presentation/features/auth/login_controller.dart';
import 'package:health_pro/presentation/features/auth/widgets/auth_actions.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The 6-digit code emailed at sign-up, or after signing in to an address never confirmed (D-250).
class CodeStep extends StatelessWidget {
  const CodeStep({required this.controller, super.key});

  final LoginController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CodeCells(controller: controller),
        const SizedBox(height: AppSpacing.xl),
        Obx(
          () => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthFailureText(failure: controller.failure.value),
              AuthPrimaryButton(
                label: l.otpVerify,
                onPressed: controller.canVerify ? controller.verify : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              // Resending is useless to someone who mistyped their email — the code is going to an
              // inbox they do not have — so the way back to it sits beside it.
              // Expanded, not Flexible: a loose fit lets a TextButton keep its one-line intrinsic
              // width, and at 200 % font scale the pair overflowed the row by 71 pt rather than
              // wrapping (rule 12).
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: controller.canResend ? controller.resendCode : null,
                      child: Text(
                        controller.resendIn.value == 0
                            ? l.otpResend
                            : l.otpResendIn(controller.resendIn.value),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: controller.busy.value
                          ? null
                          : () => controller.goTo(AuthStep.signUp),
                      child: Text(l.otpChangeEmail, textAlign: TextAlign.center),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Six boxes with one field behind them.
///
/// The field is real and invisible: it owns the focus, the keyboard, autofill's one-time-code
/// suggestion and every paste and backspace, and the boxes only draw what it holds. Six separate
/// fields is the version that loses a pasted code, fights the OS autofill and has to hand focus
/// around by hand — six ways to get wrong what one `TextField` already gets right.
class _CodeCells extends StatefulWidget {
  const _CodeCells({required this.controller});

  final LoginController controller;

  @override
  State<_CodeCells> createState() => _CodeCellsState();
}

class _CodeCellsState extends State<_CodeCells> {
  final _focus = FocusNode();
  late final _text = TextEditingController(text: widget.controller.code.value);

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Stack(
      children: [
        // Sized by the boxes in front of it, so the two can never disagree about the tap area.
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: _text,
              focusNode: _focus,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: LoginController.codeLength,
              // iOS offers a code from Mail above the keyboard; elsewhere it is a harmless hint.
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (v) => setState(() => widget.controller.code.value = v),
              decoration: const InputDecoration(counterText: ''),
            ),
          ),
        ),
        GestureDetector(
          onTap: _focus.requestFocus,
          child: Row(
            children: [
              for (var i = 0; i < LoginController.codeLength; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _Cell(
                    digit: i < _text.text.length ? _text.text[i] : '',
                    // The cell the next digit lands in, which is the last one once the code is
                    // full — not a seventh box that does not exist.
                    active:
                        _focus.hasFocus &&
                        i == _text.text.length.clamp(0, LoginController.codeLength - 1),
                    label: l.otpDigit(LoginController.codeLength, i + 1),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.digit, required this.active, required this.label});

  final String digit;
  final bool active;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      label: label,
      value: digit,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.enter,
        // Squarish, and by aspect rather than a fixed height, so the row grows with the text scale
        // instead of clipping the numeral inside it (rule 12).
        constraints: const BoxConstraints(minHeight: AppSizes.otpCell),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.tile),
          border: Border.all(
            color: active ? scheme.primary : scheme.outline.withValues(alpha: 0.5),
            width: active ? 1.5 : 1,
          ),
          boxShadow: AppElevation.card(theme.brightness),
        ),
        child: Text(
          digit,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.primary,
          ),
        ),
      ),
    );
  }
}

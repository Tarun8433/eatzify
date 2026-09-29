import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// A text field bound to one of the controller's values. It owns its `TextEditingController`, seeded
/// from [value], so an email typed on one step is already there on the next.
class AuthTextField extends StatefulWidget {
  const AuthTextField({
    required this.value,
    required this.label,
    this.hint,
    this.keyboardType,
    this.autofillHints,
    this.obscure = false,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    super.key,
  });

  final RxString value;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final bool obscure;
  final TextInputAction textInputAction;
  final VoidCallback? onSubmitted;

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  late final _text = TextEditingController(text: widget.value.value);
  late bool _hidden = widget.obscure;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return TextField(
      controller: _text,
      keyboardType: widget.keyboardType,
      autofillHints: widget.autofillHints,
      obscureText: _hidden,
      autocorrect: false,
      enableSuggestions: !widget.obscure,
      textInputAction: widget.textInputAction,
      onChanged: (v) => widget.value.value = v,
      onSubmitted: (_) => widget.onSubmitted?.call(),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        suffixIcon: widget.obscure
            ? IconButton(
                // Icon-only, so it carries its own label (rule 12).
                tooltip: _hidden ? l.loginShowPassword : l.loginHidePassword,
                icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hidden = !_hidden),
              )
            : null,
      ),
    );
  }
}

class AuthEmailField extends StatelessWidget {
  const AuthEmailField({required this.value, super.key});

  final RxString value;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AuthTextField(
      value: value,
      label: l.loginEmailLabel,
      hint: l.loginEmailHint,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
    );
  }
}

class AuthPasswordField extends StatelessWidget {
  const AuthPasswordField({
    required this.value,
    required this.isNew,
    this.onSubmitted,
    this.textInputAction = TextInputAction.done,
    super.key,
  });

  final RxString value;

  /// Sign-up: the password manager offers to generate one, and the hint says how long it must be.
  final bool isNew;
  final VoidCallback? onSubmitted;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AuthTextField(
      value: value,
      label: l.loginPasswordLabel,
      hint: isNew ? l.loginPasswordHint : null,
      obscure: true,
      keyboardType: TextInputType.visiblePassword,
      autofillHints: [if (isNew) AutofillHints.newPassword else AutofillHints.password],
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
    );
  }
}

/// "New to Eatzify? Create account" — a sentence with its action at the end. Wraps rather than
/// overflowing at 200 % font scale (rule 12).
class AuthLinkRow extends StatelessWidget {
  const AuthLinkRow({required this.lead, required this.action, required this.onPressed, super.key});

  final String lead;
  final String action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(lead, style: theme.textTheme.bodyMedium),
        TextButton(onPressed: onPressed, child: Text(action)),
      ],
    );
  }
}

/// A hairline either side of the word. The alternative — a bare "or" on its own line — reads as a
/// stray caption rather than as the fork between two ways in.
class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = Expanded(child: Divider(color: theme.colorScheme.outline));

    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(label, style: theme.textTheme.bodySmall),
        ),
        line,
      ],
    );
  }
}

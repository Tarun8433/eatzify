import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/format/phone_e164.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/domain/repositories/coach_repository.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';

/// The coach asks one person to work with them (docs/09 §6).
///
/// **Asking, not adding.** Nothing here creates access: the client has to accept, and only then
/// does a grant exist (docs/10 §3). The sheet says so, because a button labelled "Add client"
/// would promise something the server will not do.
abstract final class InviteClientSheet {
  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _InviteBody(),
  );
}

/// What the coach may ask for. Deliberately the two narrowest scopes — plus `chat` for a Coaching
/// Partner (D-235), because level 3 is what docs/10 §1 puts chat behind.
///
/// Everything else stays off the form: the server refuses anything above the coach's level anyway,
/// and offering a scope that comes back refused teaches people to distrust the form.
const _requestableScopes = ['basic', 'progress'];
const _coachingScopes = ['chat'];

class _InviteBody extends StatefulWidget {
  const _InviteBody();

  @override
  State<_InviteBody> createState() => _InviteBodyState();
}

class _InviteBodyState extends State<_InviteBody> {
  final _phone = TextEditingController();
  final _scopes = {..._requestableScopes};

  /// Whether this coach is level 3, read when the sheet opens. `false` until it knows — so the
  /// sheet never offers chat to somebody the server would refuse it for.
  bool _coaching = false;

  @override
  void initState() {
    super.initState();
    _readLevel();
  }

  Future<void> _readLevel() async {
    final result = await Get.find<CoachRepository>().application();
    if (!mounted) return;
    result.fold((_) {}, (app) => setState(() => _coaching = app?.isCoachingPartner ?? false));
  }

  bool _sending = false;
  String? _error;
  bool _sent = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    // Sign-in stores `+91` + digits, and the server matches an invite to a client by EXACT phone
    // equality. Sending the field's raw text wrote invites nobody could ever be shown.
    final phone = PhoneE164.from(_phone.text);
    if (phone == null) {
      setState(() => _error = AppLocalizations.of(context).invitePhoneInvalid);
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    final result = await Get.find<CoachRepository>().invite(
      phoneE164: phone,
      scopes: _scopes.toList(),
    );

    if (!mounted) return;
    setState(() {
      _sending = false;
      result.fold((f) => _error = f.userMessage, (_) => _sent = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.inviteTitle,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(l.inviteSubtitle, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.lg),

          if (_sent) ...[
            // docs/09 §3: never reveal whether a number has an account. So the confirmation says
            // the invitation was SENT and nothing about who received it — a message that said
            // "they will see it in the app" would leak exactly what the rule protects.
            HintCard(
              icon: Icons.check_circle_outline,
              title: l.inviteSentTitle,
              text: l.inviteSentBody,
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              height: AppSizes.primaryButton,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l.commonDone),
              ),
            ),
          ] else ...[
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l.invitePhoneLabel,
                hintText: l.invitePhoneHint,
                prefixIcon: const Icon(Icons.phone_outlined),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.lg),

            Text(
              l.inviteScopesLabel,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final scope in [..._requestableScopes, if (_coaching) ..._coachingScopes])
              CheckboxListTile(
                value: _scopes.contains(scope),
                title: Text(switch (scope) {
                  'basic' => l.accessScopeBasic,
                  'chat' => l.accessScopeChat,
                  _ => l.accessScopeProgress,
                }),
                contentPadding: EdgeInsets.zero,
                onChanged: (on) => setState(() {
                  if (on ?? false) {
                    _scopes.add(scope);
                  } else {
                    _scopes.remove(scope);
                  }
                }),
              ),
            const SizedBox(height: AppSpacing.sm),

            // The honest line. docs/10 §3: a coach may request a scope; only the client grants it.
            HintCard(icon: Icons.info_outline, text: l.inviteConsentNote),
            const SizedBox(height: AppSpacing.lg),

            if (_error case final message?) ...[
              Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            SizedBox(
              height: AppSizes.primaryButton,
              child: FilledButton(
                onPressed: _phone.text.trim().isEmpty || _scopes.isEmpty || _sending ? null : _send,
                child: Text(_sending ? l.inviteSending : l.inviteSend),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

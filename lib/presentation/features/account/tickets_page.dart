import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_colors.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/support_ticket.dart';
import 'package:health_pro/domain/repositories/tickets_repository.dart';
import 'package:health_pro/presentation/features/account/tickets_controller.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// "Help" (docs/14 §6): the conversations this person has had with support, and the way to start
/// one. No FAQ and no chatbot — a person with a problem gets a person.
class TicketsPage extends StatelessWidget {
  const TicketsPage({super.key});

  static Future<void>? open() => Get.to<void>(
    () => const TicketsPage(),
    binding: BindingsBuilder<void>(() {
      Get.lazyPut(() => TicketsController(tickets: Get.find<TicketsRepository>()));
    }),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = Get.find<TicketsController>();

    return Scaffold(
      appBar: AppBar(title: Text(l.helpTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _compose(context, c),
        icon: const Icon(Icons.add),
        label: Text(l.helpNew),
      ),
      body: Obx(
        () => switch (c.state.value) {
          Loading<List<SupportTicket>>() => const LoadingView(),
          Failed<List<SupportTicket>>(:final failure) => FailedView(
            failure: failure,
            onRetry: c.load,
          ),
          Empty<List<SupportTicket>>() => EmptyView(
            title: l.helpEmpty,
            body: l.helpEmptyBody,
            actionLabel: l.helpNew,
            onAction: () => _compose(context, c),
          ),
          Ready<List<SupportTicket>>(:final data) => RefreshIndicator(
            onRefresh: () => c.load(quiet: true),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xxl * 2,
              ),
              itemCount: data.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (_, index) => _TicketCard(
                ticket: data[index],
                onTap: () async {
                  await TicketThreadPage.open(data[index]);
                  await c.load(quiet: true);
                },
              ),
            ),
          ),
        },
      ),
    );
  }

  Future<void> _compose(BuildContext context, TicketsController c) async {
    final ticket = await showModalBottomSheet<SupportTicket>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ComposeSheet(controller: c),
    );

    if (ticket != null) await TicketThreadPage.open(ticket);
  }
}

/// The "ask for help" sheet.
///
/// Stateful because it owns two [TextEditingController]s: created and disposed inside the sheet's
/// own lifetime, rather than around the `showModalBottomSheet` call — a sheet is still on screen
/// while it animates away, and a field whose controller was disposed the moment `pop` returned
/// throws on the next frame.
class _ComposeSheet extends StatefulWidget {
  const _ComposeSheet({required this.controller});

  final TicketsController controller;

  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  final _subject = TextEditingController();
  final _body = TextEditingController();

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = widget.controller;

    // Scrollable: two fields, a keyboard and a 200 % font do not fit on a short phone, and a sheet
    // that overflows hides the send button.
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.helpNew, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _subject,
            textInputAction: TextInputAction.next,
            maxLength: 140,
            decoration: InputDecoration(labelText: l.helpSubject),
          ),
          TextField(
            controller: _body,
            minLines: 3,
            maxLines: 6,
            maxLength: 4000,
            decoration: InputDecoration(labelText: l.helpMessage),
          ),
          // The server's own words when it refuses (rule 7).
          Obx(
            () => c.error.value == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(
                      c.error.value!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: AppColors.danger),
                    ),
                  ),
          ),
          Obx(
            () => FilledButton(
              onPressed: c.sending.value
                  ? null
                  : () async {
                      final created = await c.open(
                        subject: _subject.text.trim(),
                        body: _body.text.trim(),
                      );
                      if (created != null && context.mounted) {
                        Navigator.of(context).pop(created);
                      }
                    },
              child: Text(l.helpSend),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row in the list. The subject, what state it is in, and when it last moved.
class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket, required this.onTap});

  final SupportTicket ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final when = ticket.lastMessageAt ?? ticket.createdAt;

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ticket.subject, style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              // Never the raw enum (rule 4), and never a red "failed" chip (docs/05 §6 tone).
              Text(
                statusLabel(l, ticket.status),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ticket.isWaitingOnSupport
                      ? AppColors.info
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (when != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    DateFormat.yMMMd(locale).add_jm().format(when),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// docs/03 §5's states, in words. Unknown values fall back to the "with support" wording rather
/// than showing whatever the server sent.
String statusLabel(AppLocalizations l, String status) => switch (status) {
  'new' || 'open' => l.helpStatusOpen,
  'waiting_user' => l.helpStatusWaitingYou,
  'resolved' => l.helpStatusResolved,
  'closed' => l.helpStatusClosed,
  _ => l.helpStatusOpen,
};

/// One conversation, both sides of it, with the compose box at the bottom while it is still open.
class TicketThreadPage extends StatefulWidget {
  const TicketThreadPage({required this.ticket, super.key});

  final SupportTicket ticket;

  static Future<void>? open(SupportTicket ticket) => Get.to<void>(
    () => TicketThreadPage(ticket: ticket),
    binding: BindingsBuilder<void>(() {
      Get.lazyPut(
        () => TicketThreadController(tickets: Get.find<TicketsRepository>(), ticketId: ticket.id),
      );
    }),
  );

  @override
  State<TicketThreadPage> createState() => _TicketThreadPageState();
}

class _TicketThreadPageState extends State<TicketThreadPage> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    // The controller belongs to this screen; leaving it registered would hand the next
    // conversation the last one's messages.
    Get.delete<TicketThreadController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = Get.find<TicketThreadController>();

    return Scaffold(
      appBar: AppBar(title: Text(widget.ticket.subject)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Obx(
                () => switch (c.state.value) {
                  Loading<SupportThread>() => const LoadingView(),
                  Failed<SupportThread>(:final failure) => FailedView(
                    failure: failure,
                    onRetry: c.load,
                  ),
                  // A conversation always has the message that opened it, so Empty is not a state
                  // this screen can be in; it is still handled rather than left to fall through.
                  Empty<SupportThread>() => EmptyView(title: l.helpEmpty, body: l.helpEmptyBody),
                  Ready<SupportThread>(:final data) => ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: data.messages.length,
                    separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                    itemBuilder: (_, index) => _MessageBubble(message: data.messages[index]),
                  ),
                },
              ),
            ),
            Obx(() {
              final current = c.state.value;
              final ticket = current is Ready<SupportThread> ? current.data.ticket : widget.ticket;

              if (!ticket.isWritable) {
                return Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(l.helpClosedNote, style: Theme.of(context).textTheme.bodySmall),
                );
              }

              return Padding(
                padding: EdgeInsets.only(
                  left: AppSpacing.lg,
                  right: AppSpacing.lg,
                  top: AppSpacing.sm,
                  bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (c.error.value != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Text(
                          c.error.value!,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: AppColors.danger),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            minLines: 1,
                            maxLines: 4,
                            decoration: InputDecoration(hintText: l.helpReplyHint),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        IconButton(
                          tooltip: l.helpSend,
                          onPressed: c.sending.value
                              ? null
                              : () async {
                                  if (await c.reply(_input.text)) _input.clear();
                                },
                          icon: const Icon(Icons.send),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final SupportMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();

    return Align(
      alignment: message.fromSupport
          ? AlignmentDirectional.centerStart
          : AlignmentDirectional.centerEnd,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.fromSupport ? l.helpFromSupport : l.helpFromYou,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(message.body, style: theme.textTheme.bodyMedium),
            if (message.createdAt != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                DateFormat.yMMMd(locale).add_jm().format(message.createdAt!),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/app_card.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/chat.dart';
import 'package:health_pro/domain/repositories/chat_repository.dart';
import 'package:health_pro/presentation/features/coach/chat_controller.dart';
import 'package:health_pro/presentation/features/coach/invite_client_sheet.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// Who the caller can talk to (docs/02 FR-5.5). The coach's Messages tab, and the same list under
/// the client's You tab — one screen, because a conversation looks the same from both ends.
class ThreadsView extends StatelessWidget {
  const ThreadsView({super.key, this.asCoach = true});

  /// Only changes the empty state's sentence: a coach is waiting for a client to share chat, and a
  /// client is waiting to share it with a coach.
  final bool asCoach;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = Get.put(ThreadsController(chat: Get.find<ChatRepository>()), permanent: true);

    return Obx(
      () => switch (c.state.value) {
        Loading<List<ChatThread>>() => const LoadingView(),
        Failed<List<ChatThread>>(:final failure) => FailedView(failure: failure, onRetry: c.load),
        // A coach's empty inbox names the way in (D-235): chat opens at Coaching Partner level and
        // starts with an invite that asks for it. ui-standards: one clear action, not just text.
        Empty<List<ChatThread>>() => EmptyView(
          title: l.messagesEmpty,
          body: asCoach ? l.messagesEmptyCoach : l.messagesEmptyClient,
          actionLabel: asCoach ? l.messagesInviteForChat : null,
          onAction: asCoach ? () => InviteClientSheet.show(context) : null,
        ),
        Ready<List<ChatThread>>(:final data) => RefreshIndicator(
          onRefresh: () => c.load(quiet: true),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            itemCount: data.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (_, i) =>
                _ThreadCard(thread: data[i], onOpened: () => c.load(quiet: true)),
          ),
        ),
      },
    );
  }
}

/// The same list with its own bar, for the client, who reaches it from the You tab rather than
/// from a shell tab.
class ThreadsPage extends StatelessWidget {
  const ThreadsPage({super.key, this.asCoach = false});

  final bool asCoach;

  static Future<void>? open({bool asCoach = false}) =>
      Get.to<void>(() => ThreadsPage(asCoach: asCoach));

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.messagesTitle)),
      body: ThreadsView(asCoach: asCoach),
    );
  }
}

class _ThreadCard extends StatelessWidget {
  const _ThreadCard({required this.thread, required this.onOpened});

  final ChatThread thread;
  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return AppCard(
      onTap: () async {
        await ChatPage.open(otherUserId: thread.otherUserId, name: thread.name);
        onOpened();
      },
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(thread.name, style: theme.textTheme.titleMedium),
                if (thread.lastMessage case final last?) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(last, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                ],
              ],
            ),
          ),
          if (thread.unread > 0) ...[
            const SizedBox(width: AppSpacing.sm),
            Chip(
              label: Text(l.messagesUnread('${thread.unread}')),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }
}

/// One conversation (docs/02 FR-5.5).
///
/// Stateful so the controller dies with the screen: closing the thread cancels the live
/// subscription and drops the socket, which is the difference between a chat you left and a socket
/// nobody closed.
class ChatPage extends StatefulWidget {
  const ChatPage({required this.otherUserId, required this.name, super.key});

  final int otherUserId;
  final String name;

  static Future<void>? open({required int otherUserId, required String name}) =>
      Get.to<void>(() => ChatPage(otherUserId: otherUserId, name: name));

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final String _tag = '${widget.otherUserId}';
  late final ChatController c = Get.put(
    ChatController(chat: Get.find<ChatRepository>(), otherUserId: widget.otherUserId),
    tag: _tag,
  );

  @override
  void dispose() {
    Get.delete<ChatController>(tag: _tag);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: Column(
        children: [
          Expanded(
            child: Obx(
              () => switch (c.state.value) {
                Loading<List<ChatMessage>>() => const LoadingView(),
                Failed<List<ChatMessage>>(:final failure) => FailedView(
                  failure: failure,
                  onRetry: c.load,
                ),
                Empty<List<ChatMessage>>() => EmptyView(
                  title: l.messagesThreadEmpty,
                  body: l.messagesThreadEmptyBody,
                ),
                Ready<List<ChatMessage>>(:final data) => ListView.builder(
                  // Newest at the bottom, which is where a conversation belongs; the list is
                  // reversed rather than re-sorted so a new message never moves the whole screen.
                  reverse: true,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: data.length,
                  itemBuilder: (_, i) => _Bubble(message: data[i]),
                ),
              },
            ),
          ),
          Obx(() {
            final message = c.error.value;
            return message == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
                    ),
                  );
          }),
          _Composer(controller: c),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final at = message.createdAt;
    final times = DateFormat.jm(Localizations.localeOf(context).toLanguageTag());

    return Align(
      alignment: message.mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
        decoration: BoxDecoration(
          color: message.mine ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.cardLarge),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.body, style: theme.textTheme.bodyMedium),
            if (at != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                times.format(at),
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({required this.controller});

  final ChatController controller;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _text.text;
    if (body.trim().isEmpty) return;
    if (await widget.controller.send(body)) _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _text,
                maxLines: 4,
                minLines: 1,
                maxLength: 2000,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(labelText: l.messagesHint, counterText: ''),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Obx(
              () => IconButton.filled(
                tooltip: l.messagesSend,
                onPressed: widget.controller.sending.value ? null : _send,
                icon: const Icon(Icons.send),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

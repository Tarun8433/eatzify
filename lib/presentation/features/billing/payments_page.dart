import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/format/rupees.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/paid_order.dart';
import 'package:health_pro/domain/repositories/billing_repository.dart';
import 'package:health_pro/presentation/features/billing/payments_controller.dart';
import 'package:health_pro/presentation/features/billing/tier_palette.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// Payments and refunds (admin panel plan, Phase B), reached from "Your plan". Inside 7 days a
/// payment refunds straight away; after that the person asks, and finance decides.
class PaymentsPage extends StatelessWidget {
  const PaymentsPage({super.key});

  static Future<void>? open() => Get.to<void>(
    () => const PaymentsPage(),
    binding: BindingsBuilder<void>(() {
      Get.lazyPut(() => PaymentsController(billing: Get.find<BillingRepository>()));
    }),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = Get.find<PaymentsController>();

    return Scaffold(
      appBar: AppBar(title: Text(l.paymentsTitle)),
      body: Obx(
        () => switch (c.state.value) {
          Loading<List<PaidOrder>>() => const LoadingView(),
          Failed<List<PaidOrder>>(:final failure) => FailedView(failure: failure, onRetry: c.load),
          Empty<List<PaidOrder>>() => EmptyView(
            title: l.paymentsEmpty,
            body: l.paymentsEmptyBody,
            actionLabel: l.paymentsRefresh,
            onAction: c.load,
          ),
          Ready<List<PaidOrder>>(:final data) => _List(controller: c, orders: data),
        },
      ),
    );
  }
}

/// `PRO 3M` as "Pro for 3 months" — never the raw code (rule 4).
String planText(AppLocalizations l, String plan) {
  final parts = plan.split(' ');
  if (parts.length != 2) return plan;
  final months = int.tryParse(parts[1].replaceAll('M', '')) ?? 0;
  return l.subscriptionUpgradePrice(tierLabel(l, parts[0]), '$months');
}

class _List extends StatelessWidget {
  const _List({required this.controller, required this.orders});

  final PaymentsController controller;
  final List<PaidOrder> orders;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dates = DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag());

    return RefreshIndicator(
      onRefresh: controller.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: [
          Obx(
            () => controller.error.value == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      controller.error.value!,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
          ),
          for (final order in orders)
            Obx(
              () => ListTile(
                minVerticalPadding: AppSpacing.md,
                title: Text(planText(l, order.plan)),
                subtitle: Text(
                  [
                    Rupees.format(order.amountPaise ~/ 100),
                    if (order.paidAt != null) dates.format(order.paidAt!),
                    if (order.refunded) l.paymentsRefunded,
                  ].join(' · '),
                ),
                trailing: controller.busy.value == order.orderId
                    ? const SizedBox.square(
                        dimension: AppSpacing.lg,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : _Action(controller: controller, order: order),
              ),
            ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.controller, required this.order});

  final PaymentsController controller;
  final PaidOrder order;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return switch (order.refund) {
      RefundOption.selfServe => TextButton(
        onPressed: () => _refund(context),
        child: Text(l.paymentsRefund),
      ),
      RefundOption.request => TextButton(
        onPressed: () => _request(context),
        child: Text(l.paymentsRequestRefund),
      ),
      RefundOption.requested => Text(l.paymentsRequested),
      RefundOption.none => const SizedBox.shrink(),
    };
  }

  Future<void> _refund(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.paymentsRefundTitle(Rupees.format(order.amountPaise ~/ 100))),
        content: Text(l.paymentsRefundBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.paymentsCancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.paymentsRefund)),
        ],
      ),
    );
    if (sure != true) return;
    if (await controller.refund(order)) {
      messenger.showSnackBar(SnackBar(content: Text(l.paymentsRefundDone)));
    }
  }

  Future<void> _request(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => _ReasonDialog(l: l),
    );
    if (reason == null || reason.trim().isEmpty) return;
    if (await controller.request(order, reason)) {
      messenger.showSnackBar(SnackBar(content: Text(l.paymentsRequestDone)));
    }
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.l});

  final AppLocalizations l;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    return AlertDialog(
      title: Text(l.paymentsRequestTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.paymentsRequestBody),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _text,
            maxLength: 1000,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: l.paymentsReasonLabel),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.paymentsCancel)),
        FilledButton(
          onPressed: _text.text.trim().length < 3 ? null : () => Navigator.pop(context, _text.text),
          child: Text(l.paymentsSend),
        ),
      ],
    );
  }
}

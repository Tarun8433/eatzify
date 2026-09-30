import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:health_pro/core/format/rupees.dart';
import 'package:health_pro/core/theme/app_spacing.dart';
import 'package:health_pro/core/widgets/state_views.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/invoice.dart';
import 'package:health_pro/domain/repositories/billing_repository.dart';
import 'package:health_pro/presentation/features/billing/invoices_controller.dart';
import 'package:health_pro/presentation/l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

/// GST invoices and credit notes (D-255), reached from "Your plan". A tap fetches the PDF and hands
/// it to the share sheet, where it can be saved, printed or sent.
class InvoicesPage extends StatelessWidget {
  const InvoicesPage({super.key});

  static Future<void>? open() => Get.to<void>(
    () => const InvoicesPage(),
    binding: BindingsBuilder<void>(() {
      Get.lazyPut(() => InvoicesController(billing: Get.find<BillingRepository>()));
    }),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = Get.find<InvoicesController>();

    return Scaffold(
      appBar: AppBar(title: Text(l.invoicesTitle)),
      body: Obx(
        () => switch (c.state.value) {
          Loading<List<Invoice>>() => const LoadingView(),
          Failed<List<Invoice>>(:final failure) => FailedView(failure: failure, onRetry: c.load),
          Empty<List<Invoice>>() => EmptyView(
            title: l.invoicesEmpty,
            body: l.invoicesEmptyBody,
            actionLabel: l.invoicesRefresh,
            onAction: c.load,
          ),
          Ready<List<Invoice>>(:final data) => _List(controller: c, invoices: data),
        },
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.controller, required this.invoices});

  final InvoicesController controller;
  final List<Invoice> invoices;

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
          // Rule 7: a refused download is the server's words.
          Obx(
            () => controller.downloadError.value == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      controller.downloadError.value!,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
          ),
          for (final invoice in invoices)
            Obx(
              () => ListTile(
                minVerticalPadding: AppSpacing.md,
                title: Text(invoice.isCreditNote ? l.invoiceCreditNote : invoice.description),
                subtitle: Text('${invoice.number} · ${dates.format(invoice.issuedAt)}'),
                trailing: controller.downloading.value == invoice.id
                    ? const SizedBox.square(
                        dimension: AppSpacing.lg,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(Rupees.format(invoice.totalPaise ~/ 100)),
                          const SizedBox(width: AppSpacing.sm),
                          Icon(
                            Icons.download_outlined,
                            semanticLabel: l.invoiceDownload(invoice.number),
                          ),
                        ],
                      ),
                onTap: () => _share(controller, invoice),
              ),
            ),
        ],
      ),
    );
  }

  static Future<void> _share(InvoicesController controller, Invoice invoice) async {
    final bytes = await controller.pdf(invoice);
    if (bytes == null) return;
    await Share.shareXFiles([
      XFile.fromData(
        Uint8List.fromList(bytes),
        mimeType: 'application/pdf',
        name: '${invoice.number}.pdf',
      ),
    ]);
  }
}

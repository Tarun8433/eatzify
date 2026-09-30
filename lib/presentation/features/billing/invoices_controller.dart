import 'package:get/get.dart';
import 'package:health_pro/core/widgets/view_state.dart';
import 'package:health_pro/domain/entities/invoice.dart';
import 'package:health_pro/domain/repositories/billing_repository.dart';

/// The account's GST invoices and credit notes (D-255). The server issues and numbers them; this
/// lists them and fetches a PDF to share.
class InvoicesController extends GetxController {
  InvoicesController({required this.billing});

  final BillingRepository billing;

  final state = Rx<ViewState<List<Invoice>>>(const Loading());

  /// The invoice whose PDF is being fetched, so its row shows progress and a second tap waits.
  final downloading = RxnString();

  /// Whatever the server refused a download with, verbatim (rule 7).
  final downloadError = RxnString();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    state.value = const Loading();
    final result = await billing.invoices();
    state.value = result.fold(Failed.new, (rows) => rows.isEmpty ? const Empty() : Ready(rows));
  }

  /// The PDF's bytes, or null when it could not be fetched (and [downloadError] says why).
  Future<List<int>?> pdf(Invoice invoice) async {
    if (downloading.value != null) return null;
    downloading.value = invoice.id;
    downloadError.value = null;
    final result = await billing.invoicePdf(invoice.id);
    downloading.value = null;
    return result.fold((f) {
      downloadError.value = f.userMessage;
      return null;
    }, (bytes) => bytes);
  }
}

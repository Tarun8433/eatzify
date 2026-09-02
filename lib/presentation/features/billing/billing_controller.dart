import 'package:get/get.dart';
import 'package:health_pro/domain/entities/billing.dart';
import 'package:health_pro/domain/repositories/billing_repository.dart';

/// What the server says this account may use, for the screens that sell the rest.
///
/// The default while loading — and on any failure — is NO premium surfaces: docs/11 §10 names
/// "upgrade CTA rendered while subscribed" as a shipped defect of the old build, and a network
/// blip must not flash a sales banner at a paying customer.
class BillingController extends GetxController {
  BillingController({required this.billing});

  final BillingRepository billing;

  final entitlements = Rxn<Entitlements>();
  final prices = <TierPrice>[].obs;

  /// True only once the server has SAID so.
  bool get showPremium => entitlements.value?.isFree ?? false;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    final result = await billing.entitlements();
    result.fold((_) => entitlements.value = null, (e) => entitlements.value = e);
  }

  /// Fetched when the paywall opens, not before — the tab needs the tier, not the price matrix.
  Future<void> loadPrices() async {
    if (prices.isNotEmpty) return;
    final result = await billing.prices();
    result.fold((_) {}, prices.assignAll);
  }
}

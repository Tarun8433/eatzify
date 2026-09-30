import 'package:get/get.dart';
import 'package:health_pro/domain/entities/payout_kyc.dart';
import 'package:health_pro/domain/repositories/coach_repository.dart';

/// Sends a partner's payout details (D-255). Only reached once the server has said a payout is due.
class PayoutKycController extends GetxController {
  PayoutKycController({required this.coach});

  final CoachRepository coach;

  /// The shapes the server also checks. Here only so a typo is caught before a round trip; the
  /// server's answer is the one that counts.
  static final pan = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');
  static final account = RegExp(r'^[0-9]{9,18}$');
  static final ifsc = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
  static final gstin = RegExp(r'^[0-9]{2}[A-Z0-9]{13}$');
  static const nameMin = 2;
  static const nameMax = 100;

  final saving = false.obs;

  /// Whatever the server refused with, verbatim (rule 7).
  final error = RxnString();

  /// True once the details are with the server for review.
  Future<bool> submit(PayoutKycSubmission details) async {
    if (saving.value) return false;
    saving.value = true;
    error.value = null;
    final result = await coach.submitPayoutKyc(details);
    saving.value = false;
    return result.fold((f) {
      error.value = f.userMessage;
      return false;
    }, (_) => true);
  }
}

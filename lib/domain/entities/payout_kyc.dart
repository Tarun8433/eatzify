/// `GET /coach/payouts/kyc` (D-255): whether payout details are needed yet, and what is on file.
///
/// The server decides [required] — it is true only once money is waiting (₹1,000 or more) and no
/// verified details exist. The app never works that out itself (rule 2).
class PayoutKyc {
  const PayoutKyc({
    required this.required,
    required this.status,
    required this.duePaise,
    this.bankLast4,
  });

  PayoutKyc.fromJson(Map<String, dynamic> json)
    : this(
        required: json['required'] == true,
        status: json['status']?.toString() ?? 'none',
        duePaise: int.tryParse(json['due_paise']?.toString() ?? '') ?? 0,
        bankLast4: json['bank_last4']?.toString(),
      );

  final bool required;

  /// `none` · `pending` · `verified` · `rejected`.
  final String status;
  final int duePaise;

  /// Only the last four digits ever reach the phone.
  final String? bankLast4;

  bool get isPending => status == 'pending';
  bool get isRejected => status == 'rejected';
}

/// What the partner sends. Formats are checked again by the server, which is the one that counts.
class PayoutKycSubmission {
  const PayoutKycSubmission({
    required this.holderName,
    required this.pan,
    required this.accountNumber,
    required this.ifsc,
    this.gstin,
  });

  final String holderName;
  final String pan;
  final String accountNumber;
  final String ifsc;
  final String? gstin;

  Map<String, dynamic> toJson() => {
    'holder_name': holderName,
    'pan': pan,
    'account_number': accountNumber,
    'ifsc': ifsc,
    if (gstin != null && gstin!.isNotEmpty) 'gstin': gstin,
  };
}

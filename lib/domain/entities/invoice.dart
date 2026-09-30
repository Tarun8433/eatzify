/// A GST tax invoice or credit note, as `GET /billing/invoices` lists it (D-255). The server issues
/// and numbers it; the app only lists and downloads.
class Invoice {
  const Invoice({
    required this.id,
    required this.number,
    required this.isCreditNote,
    required this.issuedAt,
    required this.description,
    required this.totalPaise,
  });

  Invoice.fromJson(Map<String, dynamic> json)
    : this(
        id: json['id']?.toString() ?? '',
        number: json['number']?.toString() ?? '',
        isCreditNote: json['kind'] == 'credit_note',
        issuedAt: DateTime.tryParse(json['issued_at']?.toString() ?? '')?.toLocal() ?? DateTime(0),
        description: json['description']?.toString() ?? '',
        totalPaise: int.tryParse(json['total_paise']?.toString() ?? '') ?? 0,
      );

  final String id;
  final String number;

  /// A refund's credit note rather than a sale's invoice.
  final bool isCreditNote;
  final DateTime issuedAt;

  /// Server-written (`Eatzify Pro plan, 3 months`). Shown as the invoice itself says it.
  final String description;
  final int totalPaise;
}

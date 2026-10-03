import 'package:cloud_firestore/cloud_firestore.dart';

enum TransactionType { expense, income, transfer, adjustment }

class TransactionRecord {
  const TransactionRecord({
    required this.id,
    required this.type,
    required this.amountMinor,
    required this.currencyCode,
    required this.accountId,
    required this.description,
    required this.occurredAt,
    this.categoryId,
    this.destinationAccountId,
    this.syncPending = false,
  });

  final String id;
  final TransactionType type;
  final int amountMinor;
  final String currencyCode;
  final String accountId;
  final String? destinationAccountId;
  final String? categoryId;
  final String description;
  final DateTime occurredAt;
  final bool syncPending;

  factory TransactionRecord.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final typeName = data['type'] as String? ?? 'expense';
    return TransactionRecord(
      id: doc.id,
      type: TransactionType.values.firstWhere(
        (type) => type.name == typeName,
        orElse: () => TransactionType.expense,
      ),
      amountMinor: (data['amountMinor'] as num?)?.toInt() ?? 0,
      currencyCode: data['currencyCode'] as String? ?? 'PEN',
      accountId: data['accountId'] as String? ?? '',
      destinationAccountId: data['destinationAccountId'] as String?,
      categoryId: data['categoryId'] as String?,
      description: data['description'] as String? ?? '',
      occurredAt:
          (data['occurredAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      syncPending: doc.metadata.hasPendingWrites,
    );
  }
}

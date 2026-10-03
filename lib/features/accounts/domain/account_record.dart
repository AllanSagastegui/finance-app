import 'package:cloud_firestore/cloud_firestore.dart';

enum AccountType { cash, debit, credit, savings, wallet, other }

class AccountRecord {
  const AccountRecord({
    required this.id,
    required this.name,
    required this.type,
    required this.currencyCode,
    required this.initialBalanceMinor,
    required this.currentBalanceMinor,
    required this.archived,
  });

  final String id;
  final String name;
  final AccountType type;
  final String currencyCode;
  final int initialBalanceMinor;
  final int currentBalanceMinor;
  final bool archived;

  factory AccountRecord.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return AccountRecord(
      id: document.id,
      name: data['name'] as String? ?? 'Cuenta',
      type: AccountType.values.firstWhere(
        (type) => type.name == data['type'],
        orElse: () => AccountType.other,
      ),
      currencyCode: data['currencyCode'] as String? ?? 'PEN',
      initialBalanceMinor: (data['initialBalanceMinor'] as num?)?.toInt() ?? 0,
      currentBalanceMinor:
          (data['currentBalanceMinor'] as num?)?.toInt() ??
          (data['initialBalanceMinor'] as num?)?.toInt() ??
          0,
      archived: data['archived'] as bool? ?? false,
    );
  }
}

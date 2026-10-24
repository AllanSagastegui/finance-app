import 'package:cloud_firestore/cloud_firestore.dart';

class BudgetRecord {
  const BudgetRecord({
    required this.id,
    required this.name,
    required this.limitMinor,
    required this.spentMinor,
    required this.currencyCode,
  });

  final String id;
  final String name;
  final int limitMinor;
  final int spentMinor;
  final String currencyCode;

  factory BudgetRecord.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document, {
    int? spentOverride,
  }
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final now = DateTime.now();
    final currentPeriod =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}';
    final spentPeriodKey = data['spentPeriodKey'] as String?;
    return BudgetRecord(
      id: document.id,
      name: data['name'] as String? ?? 'Presupuesto',
      limitMinor: (data['limitMinor'] as num?)?.toInt() ?? 0,
      spentMinor: spentOverride ??
          (spentPeriodKey == null || spentPeriodKey == currentPeriod
          ? (data['spentMinor'] as num?)?.toInt() ?? 0
          : 0),
      currencyCode: data['currencyCode'] as String? ?? 'PEN',
    );
  }
}

class GoalRecord {
  const GoalRecord({
    required this.id,
    required this.name,
    required this.targetAmountMinor,
    required this.savedAmountMinor,
    required this.currencyCode,
  });

  final String id;
  final String name;
  final int targetAmountMinor;
  final int savedAmountMinor;
  final String currencyCode;

  factory GoalRecord.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return GoalRecord(
      id: document.id,
      name: data['name'] as String? ?? 'Meta',
      targetAmountMinor: (data['targetAmountMinor'] as num?)?.toInt() ?? 0,
      savedAmountMinor: (data['savedAmountMinor'] as num?)?.toInt() ?? 0,
      currencyCode: data['currencyCode'] as String? ?? 'PEN',
    );
  }
}

class RecurringRecord {
  const RecurringRecord({
    required this.id,
    required this.name,
    required this.amountMinor,
    required this.currencyCode,
    required this.frequency,
    required this.nextRunAt,
    required this.active,
  });

  final String id;
  final String name;
  final int amountMinor;
  final String currencyCode;
  final String frequency;
  final DateTime nextRunAt;
  final bool active;

  factory RecurringRecord.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return RecurringRecord(
      id: document.id,
      name: data['description'] as String? ?? 'Recurrente',
      amountMinor: (data['amountMinor'] as num?)?.toInt() ?? 0,
      currencyCode: data['currencyCode'] as String? ?? 'PEN',
      frequency: data['frequency'] as String? ?? 'monthly',
      nextRunAt: (data['nextRunAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      active: data['active'] as bool? ?? true,
    );
  }
}

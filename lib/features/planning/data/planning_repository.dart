import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../domain/planning_records.dart';
import '../../transactions/domain/transaction_record.dart';

final planningRepositoryProvider = Provider<PlanningRepository>((ref) {
  return PlanningRepository(FirebaseFirestore.instance, FirebaseAuth.instance);
});

final budgetsProvider = StreamProvider<List<BudgetRecord>>((ref) {
  return ref.watch(planningRepositoryProvider).watchBudgets();
});
final goalsProvider = StreamProvider<List<GoalRecord>>((ref) {
  return ref.watch(planningRepositoryProvider).watchGoals();
});
final recurringProvider = StreamProvider<List<RecurringRecord>>((ref) {
  return ref.watch(planningRepositoryProvider).watchRecurring();
});

class PlanningRepository {
  PlanningRepository(this._firestore, this._auth);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  static const _uuid = Uuid();

  String get _uid {
    final value = _auth.currentUser?.uid;
    if (value == null) throw StateError('Authentication required');
    return value;
  }

  CollectionReference<Map<String, dynamic>> _collection(String name) =>
      _firestore.collection('users/$_uid/$name');

  Stream<List<BudgetRecord>> watchBudgets() {
    late StreamController<List<BudgetRecord>> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? budgetsSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? transactionsSub;
    QuerySnapshot<Map<String, dynamic>>? latestBudgets;
    QuerySnapshot<Map<String, dynamic>>? latestTransactions;

    void emit() {
      if (latestBudgets == null || latestTransactions == null) return;
      final totals = <String, int>{};
      for (final document in latestTransactions!.docs) {
        final data = document.data();
        if (data['type'] != 'expense') continue;
        final category = data['categoryId'] as String? ?? 'other';
        final currency = data['currencyCode'] as String? ?? 'PEN';
        final amount = (data['amountMinor'] as num?)?.toInt() ?? 0;
        totals['all|$currency'] = (totals['all|$currency'] ?? 0) + amount;
        totals['$category|$currency'] =
            (totals['$category|$currency'] ?? 0) + amount;
      }
      controller.add(
        latestBudgets!.docs.map((document) {
          final data = document.data();
          final category = data['categoryId'] as String? ?? 'all';
          final currency = data['currencyCode'] as String? ?? 'PEN';
          return BudgetRecord.fromFirestore(
            document,
            spentOverride:
                totals['$category|$currency'] ?? totals['all|$currency'] ?? 0,
          );
        }).toList(),
      );
    }

    controller = StreamController<List<BudgetRecord>>(
      onListen: () {
        final now = DateTime.now();
        final start = DateTime(now.year, now.month);
        final end = DateTime(now.year, now.month + 1);
        budgetsSub = _collection('budgets')
            .where('active', isEqualTo: true)
            .snapshots()
            .listen((snapshot) {
              latestBudgets = snapshot;
              emit();
            }, onError: controller.addError);
        transactionsSub = _collection('transactions')
            .where(
              'occurredAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(start.toUtc()),
            )
            .where('occurredAt', isLessThan: Timestamp.fromDate(end.toUtc()))
            .snapshots()
            .listen((snapshot) {
              latestTransactions = snapshot;
              emit();
            }, onError: controller.addError);
      },
      onCancel: () async {
        await budgetsSub?.cancel();
        await transactionsSub?.cancel();
      },
    );
    return controller.stream;
  }

  Stream<List<GoalRecord>> watchGoals() => _collection('goals')
      .where('archived', isEqualTo: false)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(GoalRecord.fromFirestore).toList());

  Stream<List<RecurringRecord>> watchRecurring() =>
      _collection('recurringRules')
          .where('active', isEqualTo: true)
          .snapshots()
          .map(
            (snapshot) =>
                snapshot.docs.map(RecurringRecord.fromFirestore).toList(),
          );

  Future<void> reconcileCurrentMonthBudgets() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month).toUtc();
    final end = DateTime(now.year, now.month + 1).toUtc();
    final budgets = await _collection('budgets')
        .where('active', isEqualTo: true)
        .get();
    final transactions = await _collection('transactions')
        .where('occurredAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('occurredAt', isLessThan: Timestamp.fromDate(end))
        .get();
    final totals = <String, int>{};
    for (final document in transactions.docs) {
      final data = document.data();
      if (data['type'] != 'expense') continue;
      final category = data['categoryId'] as String? ?? 'other';
      final amount = (data['amountMinor'] as num?)?.toInt() ?? 0;
      totals['all'] = (totals['all'] ?? 0) + amount;
      totals[category] = (totals[category] ?? 0) + amount;
    }
    final periodKey =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}';
    final batch = _firestore.batch();
    for (final budget in budgets.docs) {
      final category = budget.data()['categoryId'] as String? ?? 'all';
      batch.update(budget.reference, {
        'spentMinor': totals[category] ?? 0,
        'spentPeriodKey': periodKey,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    if (budgets.docs.isNotEmpty) await batch.commit();
  }

  Future<void> createBudget({
    required String name,
    required int limitMinor,
  }) async {
    await _collection('budgets').doc(_uuid.v7()).set({
      'name': name.trim(),
      'categoryId': 'all',
      'period': 'monthly',
      'limitMinor': limitMinor,
      'spentMinor': 0,
      'currencyCode': 'PEN',
      'alertAt80': true,
      'alertAt100': true,
      'active': true,
      'schemaVersion': 1,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> createGoal({
    required String name,
    required int targetAmountMinor,
  }) async {
    await _collection('goals').doc(_uuid.v7()).set({
      'name': name.trim(),
      'targetAmountMinor': targetAmountMinor,
      'savedAmountMinor': 0,
      'currencyCode': 'PEN',
      'archived': false,
      'schemaVersion': 1,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> createRecurring({
    required String description,
    required int amountMinor,
    required String accountId,
    required DateTime nextRunAt,
    String frequency = 'monthly',
  }) async {
    await _collection('recurringRules').doc(_uuid.v7()).set({
      'type': 'expense',
      'description': description.trim(),
      'amountMinor': amountMinor,
      'currencyCode': 'PEN',
      'accountId': accountId,
      'categoryId': 'other',
      'frequency': frequency,
      'nextRunAt': Timestamp.fromDate(nextRunAt.toUtc()),
      'active': true,
      'schemaVersion': 1,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> materializeDueRecurring() async {
    final now = DateTime.now().toUtc();
    final due = await _collection('recurringRules')
        .where('active', isEqualTo: true)
        .where('nextRunAt', isLessThanOrEqualTo: Timestamp.fromDate(now))
        .limit(25)
        .get();
    for (final rule in due.docs) {
      await _materializeRule(rule.reference);
    }
  }

  Future<void> _materializeRule(
    DocumentReference<Map<String, dynamic>> ruleRef,
  ) async {
    await _firestore.runTransaction((tx) async {
      final ruleSnapshot = await tx.get(ruleRef);
      final data = ruleSnapshot.data();
      if (!ruleSnapshot.exists ||
          data == null ||
          data['active'] != true ||
          data['nextRunAt'] is! Timestamp) {
        return;
      }
      final dueAt = (data['nextRunAt'] as Timestamp).toDate();
      if (dueAt.isAfter(DateTime.now().toUtc())) return;
      final ruleId = ruleRef.id;
      final movementId =
          '${ruleId}_${dueAt.toIso8601String().substring(0, 10)}';
      final movementRef = _firestore.doc(
        'users/$_uid/transactions/$movementId',
      );
      final existingMovement = await tx.get(movementRef);
      final accountRef = _firestore.doc(
        'users/$_uid/accounts/${data['accountId']}',
      );
      final account = await tx.get(accountRef);
      final accountData = account.data();
      if (!account.exists ||
          accountData == null ||
          accountData['archived'] == true) {
        return;
      }
      final amount = (data['amountMinor'] as num?)?.toInt() ?? 0;
      final activeBudgets = await _collection('budgets')
          .where('active', isEqualTo: true)
          .get();
      final type = data['type'] == 'income'
          ? TransactionType.income
          : TransactionType.expense;
      if (!existingMovement.exists) {
        tx.set(movementRef, {
          'type': type.name,
          'amountMinor': amount,
          'currencyCode': data['currencyCode'] ?? 'PEN',
          'accountId': data['accountId'],
          'destinationAccountId': null,
          'goalId': null,
          'categoryId': data['categoryId'] ?? 'other',
          'description': data['description'] ?? '',
          'occurredAt': Timestamp.fromDate(dueAt.toUtc()),
          'status': 'posted',
          'schemaVersion': 1,
          'recurringRuleId': ruleId,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.update(accountRef, {
          'currentBalanceMinor': FieldValue.increment(
            type == TransactionType.income ? amount : -amount,
          ),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (type == TransactionType.expense) {
          final categoryId = data['categoryId'] as String? ?? 'other';
          final periodKey =
              '${dueAt.toUtc().year.toString().padLeft(4, '0')}-'
              '${dueAt.toUtc().month.toString().padLeft(2, '0')}';
          for (final budget in activeBudgets.docs) {
            final budgetCategory =
                budget.data()['categoryId'] as String? ?? 'all';
            if (budgetCategory == 'all' || budgetCategory == categoryId) {
              final previousPeriod = budget.data()['spentPeriodKey'] as String?;
              tx.update(budget.reference, {
                'spentMinor': previousPeriod == periodKey
                    ? FieldValue.increment(amount)
                    : amount,
                'spentPeriodKey': periodKey,
                'updatedAt': FieldValue.serverTimestamp(),
              });
            }
          }
        }
      }
      final next = switch (data['frequency']) {
        'weekly' => dueAt.add(const Duration(days: 7)),
        'yearly' => DateTime(dueAt.year + 1, dueAt.month, dueAt.day),
        _ => DateTime(dueAt.year, dueAt.month + 1, dueAt.day),
      };
      tx.update(ruleRef, {
        'nextRunAt': Timestamp.fromDate(next.toUtc()),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}

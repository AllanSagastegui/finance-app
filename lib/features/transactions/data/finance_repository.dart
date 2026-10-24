import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../domain/transaction_record.dart';

final financeRepositoryProvider = Provider<FinanceRepository>((ref) {
  return FinanceRepository(FirebaseFirestore.instance, FirebaseAuth.instance);
});

final recentTransactionsProvider = StreamProvider<List<TransactionRecord>>((
  ref,
) {
  return ref
      .watch(financeRepositoryProvider)
      .watchRecentTransactions(limit: 20);
});

final dashboardSummaryProvider = StreamProvider<DashboardSummary>((ref) {
  return ref.watch(financeRepositoryProvider).watchCurrentMonthSummary();
});

class DashboardSummary {
  const DashboardSummary({
    this.incomeMinor = 0,
    this.expenseMinor = 0,
    this.goalAllocationMinor = 0,
    this.netMinor = 0,
    this.currencyCode = 'PEN',
  });

  final int incomeMinor;
  final int expenseMinor;
  final int goalAllocationMinor;
  final int netMinor;
  final String currencyCode;
}

class ImportedTransactionDraft {
  const ImportedTransactionDraft({
    required this.type,
    required this.amountMinor,
    required this.currencyCode,
    required this.accountId,
    required this.description,
    required this.occurredAt,
  });

  final TransactionType type;
  final int amountMinor;
  final String currencyCode;
  final String accountId;
  final String description;
  final DateTime occurredAt;
}

class FinanceRepository {
  FinanceRepository(this._firestore, this._auth);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  static const _uuid = Uuid();

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Authentication required');
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _transactions =>
      _firestore.collection('users/$_uid/transactions');

  Stream<List<TransactionRecord>> watchRecentTransactions({int limit = 20}) {
    return _transactions
        .orderBy('occurredAt', descending: true)
        .limit(limit)
        .snapshots(includeMetadataChanges: true)
        .map(
          (snapshot) =>
              snapshot.docs.map(TransactionRecord.fromFirestore).toList(),
        );
  }

  Stream<DashboardSummary> watchCurrentMonthSummary() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month);
    final end = DateTime(now.year, now.month + 1);
    return _transactions
        .where(
          'occurredAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(start.toUtc()),
        )
        .where('occurredAt', isLessThan: Timestamp.fromDate(end.toUtc()))
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
          var income = 0;
          var expense = 0;
          var goalAllocation = 0;
          var currency = 'PEN';
          for (final document in snapshot.docs) {
            final record = TransactionRecord.fromFirestore(document);
            currency = record.currencyCode;
            if (record.type == TransactionType.income) {
              income += record.amountMinor;
              goalAllocation +=
                  (document.data()['goalAllocationMinor'] as num?)?.toInt() ??
                  0;
            } else if (record.type == TransactionType.expense) {
              expense += record.amountMinor;
            }
          }
          return DashboardSummary(
            incomeMinor: income,
            expenseMinor: expense,
            goalAllocationMinor: goalAllocation,
            netMinor: income - expense - goalAllocation,
            currencyCode: currency,
          );
        });
  }

  Future<String> createTransaction({
    required TransactionType type,
    required int amountMinor,
    required String currencyCode,
    required String accountId,
    required DateTime occurredAt,
    String? destinationAccountId,
    String? goalId,
    String? categoryId,
    String description = '',
    String? transactionId,
    int goalAllocationMinor = 0,
  }) async {
    if (amountMinor <= 0) throw ArgumentError.value(amountMinor, 'amountMinor');
    if (goalAllocationMinor < 0 || goalAllocationMinor > amountMinor) {
      throw ArgumentError.value(
        goalAllocationMinor,
        'goalAllocationMinor',
        'Goal allocation must be between zero and the transaction amount',
      );
    }
    if (goalAllocationMinor > 0 && type != TransactionType.income) {
      throw ArgumentError('Goal allocations are only supported for income');
    }
    if (type == TransactionType.transfer) {
      if (destinationAccountId == null && goalId == null) {
        throw ArgumentError('Transfers require a destination account or goal');
      }
      if (destinationAccountId == accountId) {
        throw ArgumentError(
          'Transfers require different source and destination accounts',
        );
      }
    }
    final id = transactionId ?? _uuid.v7();
    final transactionRef = _transactions.doc(id);
    final activeBudgets = await _firestore
        .collection('users/$_uid/budgets')
        .where('active', isEqualTo: true)
        .get();
    await _firestore.runTransaction((tx) async {
      if (transactionId != null && (await tx.get(transactionRef)).exists) {
        return;
      }
      final sourceRef = _firestore.doc('users/$_uid/accounts/$accountId');
      final source = await tx.get(sourceRef);
      final sourceData = source.data();
      if (!source.exists || sourceData == null) {
        throw StateError('The source account does not exist');
      }
      if (sourceData['archived'] == true) {
        throw StateError('The source account is archived');
      }
      if (sourceData['currencyCode'] != currencyCode) {
        throw StateError('The transaction currency does not match the account');
      }

      DocumentReference<Map<String, dynamic>>? destinationRef;
      DocumentReference<Map<String, dynamic>>? goalRef;
      if (type == TransactionType.transfer ||
          (type == TransactionType.income && goalAllocationMinor > 0)) {
        if (destinationAccountId != null) {
          destinationRef = _firestore.doc(
            'users/$_uid/accounts/$destinationAccountId',
          );
          final destination = await tx.get(destinationRef);
          final destinationData = destination.data();
          if (!destination.exists || destinationData == null) {
            throw StateError('The destination account does not exist');
          }
          if (destinationData['archived'] == true) {
            throw StateError('The destination account is archived');
          }
          if (destinationData['currencyCode'] != currencyCode) {
            throw StateError(
              'Transfers require accounts with the same currency',
            );
          }
        } else if (goalId != null) {
          goalRef = _firestore.doc('users/$_uid/goals/$goalId');
          final goal = await tx.get(goalRef);
          final goalData = goal.data();
          if (!goal.exists ||
              goalData == null ||
              goalData['archived'] == true) {
            throw StateError('The destination goal does not exist');
          }
          if (goalData['currencyCode'] != currencyCode) {
            throw StateError('The goal currency does not match the account');
          }
        } else if (type == TransactionType.transfer) {
          throw ArgumentError('Transfers require a destination goal');
        }
      }

      tx.set(transactionRef, {
        'type': type.name,
        'amountMinor': amountMinor,
        'currencyCode': currencyCode,
        'accountId': accountId,
        'destinationAccountId': destinationAccountId,
        'goalId': goalId,
        'goalAllocationMinor': goalAllocationMinor,
        'categoryId': categoryId,
        'description': description.trim(),
        'occurredAt': Timestamp.fromDate(occurredAt.toUtc()),
        'status': 'posted',
        'schemaVersion': 1,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final accountDelta = switch (type) {
        TransactionType.income => amountMinor - goalAllocationMinor,
        TransactionType.expense => -amountMinor,
        TransactionType.adjustment => amountMinor,
        TransactionType.transfer => -amountMinor,
      };
      tx.update(sourceRef, {
        'currentBalanceMinor': FieldValue.increment(accountDelta),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (destinationRef != null) {
        tx.update(destinationRef, {
          'currentBalanceMinor': FieldValue.increment(amountMinor),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (goalRef != null) {
        tx.update(goalRef, {
          'savedAmountMinor': FieldValue.increment(
            type == TransactionType.transfer
                ? amountMinor
                : goalAllocationMinor,
          ),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (type == TransactionType.expense) {
        final periodKey = _periodKey(occurredAt);
        for (final budget in activeBudgets.docs) {
          final data = budget.data();
          final category = data['categoryId'] as String? ?? 'all';
          if (category == 'all' || category == (categoryId ?? 'other')) {
            final previousPeriod = data['spentPeriodKey'] as String?;
            tx.update(budget.reference, {
              'spentMinor': previousPeriod == periodKey
                  ? FieldValue.increment(amountMinor)
                  : amountMinor,
              'spentPeriodKey': periodKey,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
      }
    });
    return id;
  }

  String _periodKey(DateTime date) =>
      '${date.toUtc().year.toString().padLeft(4, '0')}-'
      '${date.toUtc().month.toString().padLeft(2, '0')}';

  Future<int> importTransactions(List<ImportedTransactionDraft> drafts) async {
    var imported = 0;
    for (final draft in drafts) {
      final fingerprint = sha256
          .convert(
            utf8.encode(
              '${draft.type.name}|${draft.amountMinor}|${draft.currencyCode}|'
              '${draft.accountId}|${draft.occurredAt.toUtc().toIso8601String()}|'
              '${draft.description.trim()}',
            ),
          )
          .toString();
      final reference = _transactions.doc('import_$fingerprint');
      if ((await reference.get()).exists) continue;
      await createTransaction(
        type: draft.type,
        amountMinor: draft.amountMinor,
        currencyCode: draft.currencyCode,
        accountId: draft.accountId,
        occurredAt: draft.occurredAt,
        categoryId: 'other',
        description: draft.description,
        transactionId: reference.id,
      );
      imported++;
    }
    return imported;
  }
}

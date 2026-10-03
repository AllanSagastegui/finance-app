import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../domain/planning_records.dart';

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

  Stream<List<BudgetRecord>> watchBudgets() => _collection('budgets')
      .where('active', isEqualTo: true)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.map(BudgetRecord.fromFirestore).toList(),
      );

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

  Future<void> createBudget({
    required String name,
    required int limitMinor,
  }) async {
    await _collection('budgets').doc(_uuid.v7()).set({
      'name': name.trim(),
      'categoryId': 'other',
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
  }) async {
    await _collection('recurringRules').doc(_uuid.v7()).set({
      'type': 'expense',
      'description': description.trim(),
      'amountMinor': amountMinor,
      'currencyCode': 'PEN',
      'accountId': accountId,
      'categoryId': 'other',
      'frequency': 'monthly',
      'nextRunAt': Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 30)),
      ),
      'active': true,
      'schemaVersion': 1,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

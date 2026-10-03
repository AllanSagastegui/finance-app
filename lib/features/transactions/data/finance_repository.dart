import 'dart:typed_data';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../domain/transaction_record.dart';

final financeRepositoryProvider = Provider<FinanceRepository>((ref) {
  return FinanceRepository(
    FirebaseFirestore.instance,
    FirebaseStorage.instance,
    FirebaseAuth.instance,
  );
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
    this.netMinor = 0,
    this.currencyCode = 'PEN',
  });

  final int incomeMinor;
  final int expenseMinor;
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
  FinanceRepository(this._firestore, this._storage, this._auth);

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
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
    final now = DateTime.now().toUtc();
    final period = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    return _firestore
        .doc('users/$_uid/monthlySummaries/$period')
        .snapshots()
        .map((document) {
          final data = document.data();
          if (data == null) return const DashboardSummary();
          return DashboardSummary(
            incomeMinor: (data['incomeMinor'] as num?)?.toInt() ?? 0,
            expenseMinor: (data['expenseMinor'] as num?)?.toInt() ?? 0,
            netMinor: (data['netMinor'] as num?)?.toInt() ?? 0,
            currencyCode: data['currencyCode'] as String? ?? 'PEN',
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
    String? categoryId,
    String description = '',
  }) async {
    if (amountMinor <= 0) throw ArgumentError.value(amountMinor, 'amountMinor');
    if (type == TransactionType.transfer && destinationAccountId == null) {
      throw ArgumentError('Transfers require a destination account');
    }
    final id = _uuid.v7();
    await _transactions.doc(id).set({
      'type': type.name,
      'amountMinor': amountMinor,
      'currencyCode': currencyCode,
      'accountId': accountId,
      'destinationAccountId': destinationAccountId,
      'categoryId': categoryId,
      'description': description.trim(),
      'occurredAt': Timestamp.fromDate(occurredAt.toUtc()),
      'status': 'posted',
      'schemaVersion': 1,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return id;
  }

  Future<int> importTransactions(List<ImportedTransactionDraft> drafts) async {
    var imported = 0;
    for (var offset = 0; offset < drafts.length; offset += 400) {
      final batch = _firestore.batch();
      for (final draft in drafts.skip(offset).take(400)) {
        final fingerprint = sha256
            .convert(
              utf8.encode(
                '${draft.type.name}|${draft.amountMinor}|${draft.currencyCode}|'
                '${draft.accountId}|${draft.occurredAt.toUtc().toIso8601String()}|'
                '${draft.description.trim()}',
              ),
            )
            .toString();
        batch.set(_transactions.doc('import_$fingerprint'), {
          'type': draft.type.name,
          'amountMinor': draft.amountMinor,
          'currencyCode': draft.currencyCode,
          'accountId': draft.accountId,
          'destinationAccountId': null,
          'categoryId': 'other',
          'description': draft.description.trim(),
          'occurredAt': Timestamp.fromDate(draft.occurredAt.toUtc()),
          'status': 'posted',
          'schemaVersion': 1,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        imported++;
      }
      await batch.commit();
    }
    return imported;
  }

  Future<String> uploadReceipt({
    required String transactionId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final path = 'users/$_uid/receipts/$transactionId/${_uuid.v7()}';
    final task = await _storage
        .ref(path)
        .putData(
          bytes,
          SettableMetadata(
            contentType: contentType,
            customMetadata: {'ownerUid': _uid},
          ),
        );
    return task.ref.fullPath;
  }
}

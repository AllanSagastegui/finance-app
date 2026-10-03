import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../domain/account_record.dart';

final accountsRepositoryProvider = Provider<AccountsRepository>((ref) {
  return AccountsRepository(FirebaseFirestore.instance, FirebaseAuth.instance);
});

final accountsProvider = StreamProvider<List<AccountRecord>>((ref) {
  return ref.watch(accountsRepositoryProvider).watchAccounts();
});

class AccountsRepository {
  AccountsRepository(this._firestore, this._auth);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  static const _uuid = Uuid();

  String get _uid {
    final value = _auth.currentUser?.uid;
    if (value == null) throw StateError('Authentication required');
    return value;
  }

  CollectionReference<Map<String, dynamic>> get _accounts =>
      _firestore.collection('users/$_uid/accounts');

  Stream<List<AccountRecord>> watchAccounts() => _accounts
      .where('archived', isEqualTo: false)
      .snapshots(includeMetadataChanges: true)
      .map((snapshot) {
        final accounts = snapshot.docs
            .map(AccountRecord.fromFirestore)
            .toList();
        accounts.sort((a, b) => a.name.compareTo(b.name));
        return accounts;
      });

  Future<String> createAccount({
    required String name,
    required AccountType type,
    required String currencyCode,
    required int initialBalanceMinor,
  }) async {
    final id = _uuid.v7();
    await _accounts.doc(id).set({
      'name': name.trim(),
      'type': type.name,
      'currencyCode': currencyCode,
      'initialBalanceMinor': initialBalanceMinor,
      'currentBalanceMinor': initialBalanceMinor,
      'archived': false,
      'schemaVersion': 1,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return id;
  }

  Future<void> updateAccount({
    required String accountId,
    required String name,
    required AccountType type,
  }) {
    return _accounts.doc(accountId).update({
      'name': name.trim(),
      'type': type.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> archiveAccount(String accountId) {
    return _accounts.doc(accountId).update({
      'archived': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../domain/auth_strategy.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(firebaseAuthProvider),
    FirebaseFirestore.instance,
  ),
);
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

class AuthRepository {
  AuthRepository(this._auth, this._firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Stream<User?> authStateChanges() => _auth.userChanges();
  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signInWith(AuthStrategy strategy) async {
    final result = await strategy.signIn(_auth);
    await _ensureProfile(result.user);
    return result;
  }

  Future<void> _ensureProfile(User? user) async {
    if (user == null) return;
    final profile = _firestore.doc('users/${user.uid}/profile/main');
    await profile.set({
      'displayName': user.displayName,
      'email': user.email,
      'photoUrl': user.photoURL,
      'baseCurrencyCode': 'PEN',
      'timezone': 'America/Lima',
      'schemaVersion': 1,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) await user.sendEmailVerification();
  }

  Future<void> signOut() async {
    await _auth.signOut();
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }
}

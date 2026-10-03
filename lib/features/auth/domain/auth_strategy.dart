import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

abstract interface class AuthStrategy {
  String get id;
  Future<UserCredential> signIn(FirebaseAuth auth);
}

class EmailPasswordAuthStrategy implements AuthStrategy {
  const EmailPasswordAuthStrategy({
    required this.email,
    required this.password,
    this.createAccount = false,
  });

  final String email;
  final String password;
  final bool createAccount;

  @override
  String get id => 'email';

  @override
  Future<UserCredential> signIn(FirebaseAuth auth) {
    if (createAccount) {
      return auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    }
    return auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }
}

class GoogleAuthStrategy implements AuthStrategy {
  const GoogleAuthStrategy();
  static Future<void>? _initialization;

  @override
  String get id => 'google';

  @override
  Future<UserCredential> signIn(FirebaseAuth auth) async {
    final google = GoogleSignIn.instance;
    await (_initialization ??= google.initialize());
    final account = await google.authenticate();
    final tokens = account.authentication;
    final credential = GoogleAuthProvider.credential(idToken: tokens.idToken);
    return auth.signInWithCredential(credential);
  }
}

class AppleAuthStrategy implements AuthStrategy {
  const AppleAuthStrategy();

  @override
  String get id => 'apple';

  @override
  Future<UserCredential> signIn(FirebaseAuth auth) async {
    final rawNonce = _nonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
    final apple = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );
    final credential = OAuthProvider('apple.com').credential(
      idToken: apple.identityToken,
      rawNonce: rawNonce,
      accessToken: apple.authorizationCode,
    );
    return auth.signInWithCredential(credential);
  }

  static String _nonce([int length = 32]) {
    const chars =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }
}

import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/firebase/firebase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bootstrap = await FirebaseBootstrap.initialize();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (bootstrap.isReady && !kIsWeb) {
      unawaited(FirebaseCrashlytics.instance.recordFlutterFatalError(details));
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    if (bootstrap.isReady && !kIsWeb) {
      unawaited(
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true),
      );
    }
    return true;
  };

  ErrorWidget.builder = (_) => const Material(
    color: Color(0xFFF6F7FA),
    child: SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 42,
                color: Color(0xFF5B5CE2),
              ),
              SizedBox(height: 16),
              Text(
                'Esta vista necesita un momento',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF10131A),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Tus datos están seguros. Vuelve a la pantalla anterior e inténtalo nuevamente.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF5F6572), height: 1.4),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  runApp(
    ProviderScope(
      overrides: [firebaseBootstrapProvider.overrideWithValue(bootstrap)],
      child: const AureaApp(),
    ),
  );
}

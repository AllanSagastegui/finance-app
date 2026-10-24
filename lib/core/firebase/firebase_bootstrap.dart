import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences/app_preferences.dart';

class FirebaseBootstrapState {
  const FirebaseBootstrapState({required this.isReady, this.error});
  final bool isReady;
  final Object? error;
}

final firebaseBootstrapProvider = Provider<FirebaseBootstrapState>(
  (ref) => const FirebaseBootstrapState(isReady: false),
);

abstract final class RemoteKeys {
  static const maintenanceMode = 'maintenance_mode';
  static const receiptsEnabled = 'receipts_enabled';
  static const biometricsEnabled = 'biometrics_enabled';
  static const csvImportEnabled = 'csv_import_enabled';
  static const minimumSupportedBuild = 'minimum_supported_build';
}

class FirebaseBootstrap {
  const FirebaseBootstrap._();

  static Future<FirebaseBootstrapState> initialize() async {
    try {
      await Firebase.initializeApp();
      if (!kIsWeb) {
        await FirebaseAppCheck.instance.activate(
          providerAndroid: kDebugMode
              ? const AndroidDebugProvider()
              : const AndroidPlayIntegrityProvider(),
          providerApple: kDebugMode
              ? const AppleDebugProvider()
              : const AppleAppAttestWithDeviceCheckFallbackProvider(),
        );
        await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
          !kDebugMode,
        );
      }
      // Collection is opt-in. Financial values/text never go to Analytics.
      final analyticsEnabled = await AppPreferences().isAnalyticsEnabled();
      await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(
        analyticsEnabled,
      );

      final config = FirebaseRemoteConfig.instance;
      await config.setDefaults(const {
        RemoteKeys.maintenanceMode: false,
        RemoteKeys.receiptsEnabled: false,
        RemoteKeys.biometricsEnabled: true,
        RemoteKeys.csvImportEnabled: false,
        RemoteKeys.minimumSupportedBuild: 1,
      });
      await config.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 8),
          minimumFetchInterval: kDebugMode
              ? Duration.zero
              : const Duration(hours: 4),
        ),
      );
      try {
        await config.fetchAndActivate();
      } catch (_) {
        // Defaults keep the app usable offline.
      }
      return const FirebaseBootstrapState(isReady: true);
    } catch (error) {
      return FirebaseBootstrapState(isReady: false, error: error);
    }
  }
}

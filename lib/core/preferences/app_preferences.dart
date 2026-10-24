import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppPreferences {
  AppPreferences({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _themeModeKey = 'aurea.appearance.theme_mode';
  static const _onboardingKey = 'aurea.onboarding.completed';
  static const _appTutorialKey = 'aurea.app_tutorial.completed';
  static const _analyticsKey = 'aurea.privacy.analytics';
  static const _notificationsKey = 'aurea.privacy.notifications';

  final FlutterSecureStorage _storage;

  Future<ThemeMode> readThemeMode() async {
    final value = await _storage.read(key: _themeModeKey);
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> writeThemeMode(ThemeMode value) =>
      _storage.write(key: _themeModeKey, value: value.name);

  Future<bool> hasCompletedOnboarding() async =>
      await _storage.read(key: _onboardingKey) == 'true';

  Future<void> completeOnboarding() =>
      _storage.write(key: _onboardingKey, value: 'true');

  Future<bool> hasCompletedAppTutorial() async =>
      await _storage.read(key: _appTutorialKey) == 'true';

  Future<void> completeAppTutorial() =>
      _storage.write(key: _appTutorialKey, value: 'true');

  Future<bool> isAnalyticsEnabled() async =>
      await _storage.read(key: _analyticsKey) == 'true';

  Future<void> setAnalyticsEnabled(bool value) =>
      _storage.write(key: _analyticsKey, value: value.toString());

  Future<bool> areNotificationsEnabled() async =>
      await _storage.read(key: _notificationsKey) == 'true';

  Future<void> setNotificationsEnabled(bool value) =>
      _storage.write(key: _notificationsKey, value: value.toString());
}

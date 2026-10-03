import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppPreferences {
  AppPreferences({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _themeModeKey = 'aurea.appearance.theme_mode';
  static const _onboardingKey = 'aurea.onboarding.completed';

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
}

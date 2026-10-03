import 'package:finance_app/core/security/biometric_reentry_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BiometricReentryPolicy', () {
    final start = DateTime(2026, 10, 2, 9);

    test('does not lock after a brief background transition', () {
      final policy = BiometricReentryPolicy();
      policy.enteredBackground(start);

      expect(policy.resumed(start.add(const Duration(seconds: 20))), isFalse);
    });

    test('locks after the configured grace period', () {
      final policy = BiometricReentryPolicy();
      policy.enteredBackground(start);

      expect(policy.resumed(start.add(const Duration(minutes: 1))), isTrue);
    });

    test('consumes a background transition only once', () {
      final policy = BiometricReentryPolicy();
      policy.enteredBackground(start);

      expect(policy.resumed(start.add(const Duration(minutes: 2))), isTrue);
      expect(policy.resumed(start.add(const Duration(minutes: 3))), isFalse);
    });
  });
}

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class BiometricLockService {
  BiometricLockService({
    LocalAuthentication? auth,
    FlutterSecureStorage? storage,
  }) : _auth = auth ?? LocalAuthentication(),
       _storage = storage ?? const FlutterSecureStorage();

  static const _enabledKey = 'aurea.biometric_lock.enabled';
  final LocalAuthentication _auth;
  final FlutterSecureStorage _storage;

  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isEnabled() async =>
      (await _storage.read(key: _enabledKey)) == 'true';

  Future<void> setEnabled(bool value) async {
    if (value) {
      final ok = await authenticate(
        reason: 'Confirma tu identidad para activar el bloqueo',
      );
      if (!ok) throw StateError('No se pudo verificar la identidad.');
    }
    await _storage.write(key: _enabledKey, value: value.toString());
  }

  Future<bool> authenticate({
    String reason = 'Desbloquea Aurea para continuar',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}

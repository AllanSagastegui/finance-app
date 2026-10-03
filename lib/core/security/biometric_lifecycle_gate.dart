import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';

import '../firebase/firebase_bootstrap.dart';
import 'biometric_lock_service.dart';
import 'biometric_reentry_policy.dart';

class BiometricLifecycleGate extends StatefulWidget {
  const BiometricLifecycleGate({super.key, required this.child});

  final Widget child;

  @override
  State<BiometricLifecycleGate> createState() => _BiometricLifecycleGateState();
}

class _BiometricLifecycleGateState extends State<BiometricLifecycleGate>
    with WidgetsBindingObserver {
  final _service = BiometricLockService();
  final _reentryPolicy = BiometricReentryPolicy();
  bool _locked = false;
  bool _enabled = false;
  bool _authenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _restore() async {
    final allowed = FirebaseRemoteConfig.instance.getBool(
      RemoteKeys.biometricsEnabled,
    );
    final enabled = allowed && await _service.isEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _locked = enabled;
    });
    if (enabled) await _unlock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_enabled || _authenticating) return;

    // iOS reports `inactive` while presenting Face ID, system sheets and some
    // permission prompts. Treating it as background caused an authentication
    // loop. Only a real background transition starts the lock timer.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _reentryPolicy.enteredBackground(DateTime.now());
      return;
    }

    if (state == AppLifecycleState.resumed) {
      if (!_reentryPolicy.resumed(DateTime.now())) return;
      if (mounted) setState(() => _locked = true);
      _unlock();
    }
  }

  Future<void> _unlock() async {
    if (_authenticating || !mounted) return;
    setState(() => _authenticating = true);
    final success = await _service.authenticate();
    if (!mounted) return;
    setState(() {
      _authenticating = false;
      _locked = !success;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_locked) return widget.child;
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.surface, scheme.primary.withValues(alpha: .08)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.face_rounded,
                          size: 44,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'Aurea está protegida',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Usa Face ID para volver a tus finanzas. Solo lo pediremos al abrir la app o después de un minuto fuera.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _authenticating ? null : _unlock,
                        icon: _authenticating
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.lock_open_rounded),
                        label: Text(
                          _authenticating ? 'Verificando…' : 'Desbloquear',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

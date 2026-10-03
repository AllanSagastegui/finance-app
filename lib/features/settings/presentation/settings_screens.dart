import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app.dart';
import '../../../core/firebase/firebase_bootstrap.dart';
import '../../../core/security/biometric_lock_service.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});
  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  final _biometrics = BiometricLockService();
  bool _available = false;
  bool _enabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final remoteEnabled = FirebaseRemoteConfig.instance.getBool(
      RemoteKeys.biometricsEnabled,
    );
    final values = await Future.wait([
      _biometrics.isAvailable(),
      _biometrics.isEnabled(),
    ]);
    if (!mounted) return;
    setState(() {
      _available = remoteEnabled && values[0];
      _enabled = values[1];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Seguridad')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Protección local',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile.adaptive(
              secondary: const Icon(Icons.face_rounded),
              title: const Text('Bloqueo biométrico'),
              subtitle: Text(
                _available
                    ? 'Face ID se solicita al abrir Aurea o después de un minuto fuera de la app.'
                    : 'No está disponible en este dispositivo.',
              ),
              value: _enabled,
              onChanged: _loading || !_available ? null : _setBiometric,
            ),
          ),
          if (_enabled) ...[
            const SizedBox(height: 10),
            const Card(
              child: ListTile(
                leading: Icon(Icons.timer_outlined),
                title: Text('Bloqueo inteligente'),
                subtitle: Text(
                  'Los permisos, selectores y ventanas del sistema ya no vuelven a activar Face ID.',
                ),
                trailing: Chip(label: Text('1 min')),
              ),
            ),
          ],
          const SizedBox(height: 14),
          const Card(
            child: ListTile(
              leading: Icon(Icons.verified_user_outlined),
              title: Text('Firebase Authentication'),
              subtitle: Text(
                'La biometría protege el acceso local; tu identidad remota sigue protegida por Firebase Auth.',
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Sesión', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          const Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.email_outlined),
                  title: Text('Verificación de correo'),
                  subtitle: Text(
                    'Recomendada para recuperar y proteger tu cuenta.',
                  ),
                ),
                Divider(),
                ListTile(
                  leading: Icon(Icons.devices_outlined),
                  title: Text('Sesiones activas'),
                  subtitle: Text(
                    'Gestión ampliada disponible con Identity Platform.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setBiometric(bool value) async {
    try {
      await _biometrics.setEnabled(value);
      if (mounted) {
        setState(() => _enabled = value);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se cambió el bloqueo biométrico.')),
        );
      }
    }
  }
}

class DataPrivacyScreen extends StatefulWidget {
  const DataPrivacyScreen({super.key});
  @override
  State<DataPrivacyScreen> createState() => _DataPrivacyScreenState();
}

class _DataPrivacyScreenState extends State<DataPrivacyScreen> {
  bool _analytics = false;
  bool _notifications = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Datos y privacidad')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Tú decides', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text(
          'Aurea no envía importes, saldos, descripciones, comercios ni nombres de cuentas a Analytics.',
        ),
        const SizedBox(height: 20),
        Card(
          child: Column(
            children: [
              SwitchListTile.adaptive(
                secondary: const Icon(Icons.analytics_outlined),
                title: const Text('Analytics de producto'),
                subtitle: const Text(
                  'Solo eventos genéricos para mejorar funciones.',
                ),
                value: _analytics,
                onChanged: (value) async {
                  await FirebaseAnalytics.instance
                      .setAnalyticsCollectionEnabled(value);
                  if (mounted) {
                    setState(() => _analytics = value);
                  }
                },
              ),
              const Divider(),
              SwitchListTile.adaptive(
                secondary: const Icon(Icons.notifications_active_outlined),
                title: const Text('Recordatorios'),
                subtitle: const Text(
                  'Las vistas previas no muestran cifras sensibles.',
                ),
                value: _notifications,
                onChanged: (value) async {
                  if (value) {
                    final result = await FirebaseMessaging.instance
                        .requestPermission();
                    value =
                        result.authorizationStatus ==
                            AuthorizationStatus.authorized ||
                        result.authorizationStatus ==
                            AuthorizationStatus.provisional;
                  }
                  if (mounted) {
                    setState(() => _notifications = value);
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.tonalIcon(
          onPressed: _busy ? null : _requestExport,
          icon: const Icon(Icons.download_outlined),
          label: const Text('Solicitar exportación'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _busy ? null : _requestDeletion,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Eliminar mi cuenta y datos'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
        ),
      ],
    ),
  );

  Future<void> _requestExport() async {
    setState(() => _busy = true);
    try {
      await FirebaseFunctions.instance.httpsCallable('createExport').call({
        'format': 'csv',
      });
      if (mounted) {
        _notice('Prepararemos el archivo y te avisaremos cuando esté listo.');
      }
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        _notice('No se pudo solicitar la exportación (${error.code}).');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _requestDeletion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar cuenta y datos'),
        content: const Text(
          'Esta acción inicia un borrado permanente por etapas. No se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await FirebaseFunctions.instance
          .httpsCallable('deleteAccountData')
          .call();
      if (mounted) {
        _notice('El borrado se inició. Recibirás el estado dentro de la app.');
      }
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        _notice('No se pudo iniciar el borrado (${error.code}).');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _notice(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
}

class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(themeModeProvider).value ?? ThemeMode.system;
    return Scaffold(
      appBar: AppBar(title: const Text('Apariencia')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Tema', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Card(
            child: RadioGroup<ThemeMode>(
              groupValue: selected,
              onChanged: (value) {
                if (value != null) {
                  ref.read(themeModeProvider.notifier).setMode(value);
                }
              },
              child: Column(
                children: ThemeMode.values.map((mode) {
                  final label = switch (mode) {
                    ThemeMode.system => 'Usar configuración del sistema',
                    ThemeMode.light => 'Claro',
                    ThemeMode.dark => 'Oscuro',
                  };
                  return RadioListTile<ThemeMode>(
                    value: mode,
                    title: Text(label),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Card(
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  value: false,
                  onChanged: null,
                  title: Text('Reducir movimiento'),
                  subtitle: Text(
                    'Aurea también respeta la preferencia del sistema.',
                  ),
                ),
                Divider(),
                SwitchListTile.adaptive(
                  value: true,
                  onChanged: null,
                  title: Text('Feedback háptico'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

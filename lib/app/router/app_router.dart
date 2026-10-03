import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/firebase/firebase_bootstrap.dart';
import '../../features/accounts/presentation/accounts_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/home/presentation/home_shell.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/settings/presentation/settings_screens.dart';
import '../../features/transactions/presentation/import_csv_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final bootstrap = ref.watch(firebaseBootstrapProvider);
  final maintenance =
      bootstrap.isReady &&
      FirebaseRemoteConfig.instance.getBool(RemoteKeys.maintenanceMode);
  return GoRouter(
    initialLocation: !bootstrap.isReady
        ? '/setup-required'
        : maintenance
        ? '/maintenance'
        : '/welcome',
    routes: [
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const LoginScreen(registerMode: true),
      ),
      GoRoute(path: '/home', builder: (context, state) => const HomeShell()),
      GoRoute(
        path: '/accounts',
        builder: (context, state) => const AccountsScreen(),
      ),
      GoRoute(
        path: '/security',
        builder: (context, state) => const SecurityScreen(),
      ),
      GoRoute(
        path: '/privacy',
        builder: (context, state) => const DataPrivacyScreen(),
      ),
      GoRoute(
        path: '/appearance',
        builder: (context, state) => const AppearanceScreen(),
      ),
      GoRoute(
        path: '/import-csv',
        builder: (context, state) => const ImportCsvScreen(),
      ),
      GoRoute(
        path: '/setup-required',
        builder: (context, state) =>
            SetupRequiredScreen(error: bootstrap.error),
      ),
      GoRoute(
        path: '/maintenance',
        builder: (context, state) => const MaintenanceScreen(),
      ),
    ],
  );
});

class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.construction_rounded,
                size: 52,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 18),
              Text(
                'Aurea está en mantenimiento',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Tus datos siguen protegidos. Vuelve a intentarlo en unos minutos.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class SetupRequiredScreen extends StatelessWidget {
  const SetupRequiredScreen({super.key, this.error});
  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 44,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 20),
              Text(
                'Falta conectar Firebase',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'Aurea necesita una configuración Firebase válida para este flavor. '
                'Verifica google-services.json o GoogleService-Info.plist y vuelve a abrir la app.',
              ),
              if (error != null) ...[
                const SizedBox(height: 20),
                Text(
                  'Detalle técnico: ${error.runtimeType}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

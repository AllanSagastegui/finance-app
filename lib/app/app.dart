import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/firebase/firebase_bootstrap.dart';
import '../core/preferences/app_preferences.dart';
import '../core/security/biometric_lifecycle_gate.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class ThemeModeController extends AsyncNotifier<ThemeMode> {
  final _preferences = AppPreferences();

  @override
  Future<ThemeMode> build() => _preferences.readThemeMode();

  Future<void> setMode(ThemeMode value) async {
    state = AsyncData(value);
    await _preferences.writeThemeMode(value);
  }
}

final themeModeProvider = AsyncNotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

class AureaApp extends ConsumerWidget {
  const AureaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firebaseReady = ref.watch(firebaseBootstrapProvider).isReady;
    return MaterialApp.router(
      title: 'Aurea',
      debugShowCheckedModeBanner: false,
      theme: AureaTheme.light(),
      darkTheme: AureaTheme.dark(),
      themeMode: ref.watch(themeModeProvider).value ?? ThemeMode.system,
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();
        final secured = firebaseReady
            ? BiometricLifecycleGate(child: content)
            : content;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: secured,
        );
      },
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es', 'PE'), Locale('en', 'US')],
    );
  }
}

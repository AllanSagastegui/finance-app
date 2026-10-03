import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/aurea_components.dart';
import '../../../core/preferences/app_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  final _preferences = AppPreferences();
  int _page = 0;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreDestination();
    });
  }

  Future<void> _restoreDestination() async {
    if (FirebaseAuth.instance.currentUser != null) {
      if (mounted) context.go('/home');
      return;
    }
    if (await _preferences.hasCompletedOnboarding()) {
      if (mounted) context.go('/login');
      return;
    }
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _finish() async {
    await _preferences.completeOnboarding();
    if (mounted) context.go('/login');
  }

  static const _items = [
    (
      'assets/images/onboarding_clarity_v2.jpg',
      'Entiende tu dinero sin fricción',
      'Balance, gastos y objetivos en una vista que se entiende en segundos.',
    ),
    (
      'assets/images/onboarding_privacy_v2.jpg',
      'Privacidad desde el diseño',
      'Tus importes, saldos y descripciones no se envían a Analytics ni aparecen en notificaciones.',
    ),
    (
      'assets/images/onboarding_planning_v2.jpg',
      'Planifica con calma',
      'Presupuestos, metas y recurrentes convierten tus datos en decisiones concretas.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
              child: Row(
                children: [
                  const AureaBrandLockup(compact: true),
                  const Spacer(),
                  TextButton(onPressed: _finish, child: const Text('Omitir')),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _items.length,
                onPageChanged: (value) => setState(() => _page = value),
                itemBuilder: (context, index) => LayoutBuilder(
                  builder: (context, constraints) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Semantics(
                            label: switch (index) {
                              0 =>
                                'Información financiera ordenada con claridad',
                              1 =>
                                'Datos financieros protegidos de forma privada',
                              _ =>
                                'Objetivos financieros conectados con un plan',
                            },
                            image: true,
                            child: Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(
                                  AureaRadius.lg,
                                ),
                                border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AureaColors.indigo.withValues(
                                      alpha: .1,
                                    ),
                                    blurRadius: 28,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Image.asset(
                                _items[index].$1,
                                fit: BoxFit.cover,
                                alignment: Alignment.center,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          '0${index + 1}  ·  LO ESENCIAL',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _items[index].$2,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                height: 1.08,
                                letterSpacing: -0.5,
                              ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _items[index].$3,
                          maxLines: constraints.maxHeight < 600 ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                children: [
                  ...List.generate(
                    _items.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: index == _page ? 24 : 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: index == _page
                            ? AureaColors.indigo
                            : Theme.of(context).colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      if (_page == _items.length - 1) {
                        _finish();
                      } else {
                        _controller.nextPage(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                        );
                      }
                    },
                    child: Text(
                      _page == _items.length - 1 ? 'Comenzar' : 'Continuar',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

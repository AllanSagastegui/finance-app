import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/aurea_components.dart';
import '../data/auth_repository.dart';
import '../domain/auth_strategy.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.registerMode = false});
  final bool registerMode;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(AuthStrategy strategy) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref.read(authRepositoryProvider).signInWith(strategy);
      if (widget.registerMode) {
        await ref.read(authRepositoryProvider).sendEmailVerification();
      }
      if (mounted) context.go('/home');
    } on FirebaseAuthException catch (error) {
      setState(() => _message = _firebaseMessage(error.code));
    } catch (_) {
      setState(
        () => _message = 'No pudimos completar el acceso. Inténtalo otra vez.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitEmail() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await _run(
      EmailPasswordAuthStrategy(
        email: _email.text,
        password: _password.text,
        createAccount: widget.registerMode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isApple =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const AureaBrandLockup(compact: true),
      ),
      body: AureaPageBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: AutofillGroup(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _AuthHero(registerMode: widget.registerMode),
                        const SizedBox(height: 24),
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _run(const GoogleAuthStrategy()),
                          icon: Image.asset(
                            'assets/images/google_g_official.png',
                            width: 20,
                            height: 20,
                            fit: BoxFit.contain,
                          ),
                          label: const Text('Continuar con Google'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(48, 52),
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF1F1F1F),
                            side: const BorderSide(color: Color(0xFF747775)),
                          ),
                        ),
                        if (isApple) ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _run(const AppleAuthStrategy()),
                            icon: const Icon(Icons.apple_rounded),
                            label: const Text('Continuar con Apple'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(48, 52),
                            ),
                          ),
                        ],
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Row(
                            children: [
                              Expanded(child: Divider()),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Text('o con correo'),
                              ),
                              Expanded(child: Divider()),
                            ],
                          ),
                        ),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Correo electrónico',
                          ),
                          validator: (value) =>
                              value != null && value.contains('@')
                              ? null
                              : 'Ingresa un correo válido',
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          autofillHints: widget.registerMode
                              ? const [AutofillHints.newPassword]
                              : const [AutofillHints.password],
                          onFieldSubmitted: (_) => _submitEmail(),
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            helperText: widget.registerMode
                                ? 'Mínimo 8 caracteres'
                                : null,
                            suffixIcon: IconButton(
                              tooltip: _obscure
                                  ? 'Mostrar contraseña'
                                  : 'Ocultar contraseña',
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) => (value?.length ?? 0) >= 8
                              ? null
                              : 'Usa al menos 8 caracteres',
                        ),
                        if (_message != null) ...[
                          const SizedBox(height: 12),
                          Semantics(
                            liveRegion: true,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .errorContainer,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onErrorContainer,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _message!,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onErrorContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _busy ? null : _submitEmail,
                          child: _busy
                              ? const SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  widget.registerMode
                                      ? 'Crear cuenta'
                                      : 'Iniciar sesión',
                                ),
                        ),
                        if (!widget.registerMode)
                          TextButton(
                            onPressed: _busy ? null : _resetPassword,
                            child: const Text('Olvidé mi contraseña'),
                          ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => context.go(
                                  widget.registerMode ? '/login' : '/register',
                                ),
                          child: Text(
                            widget.registerMode
                                ? 'Ya tengo una cuenta'
                                : 'Crear una cuenta nueva',
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
      ),
    );
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _message = 'Escribe tu correo para enviarte el enlace.');
      return;
    }
    await ref.read(authRepositoryProvider).sendPasswordReset(email);
    setState(
      () => _message = 'Revisa tu correo. Enviamos un enlace de recuperación.',
    );
  }

  String _firebaseMessage(String code) => switch (code) {
    'invalid-credential' => 'El correo o la contraseña no coinciden.',
    'email-already-in-use' => 'Ese correo ya está registrado.',
    'weak-password' => 'La contraseña necesita ser más segura.',
    'network-request-failed' =>
      'Sin conexión. Revisa tu red e inténtalo de nuevo.',
    _ => 'No pudimos completar el acceso ($code).',
  };
}

class _AuthHero extends StatelessWidget {
  const _AuthHero({required this.registerMode});

  final bool registerMode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 178,
      padding: const EdgeInsets.fromLTRB(20, 18, 8, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primaryContainer.withValues(alpha: .72),
            scheme.secondaryContainer.withValues(alpha: .58),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AureaRadius.lg),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  registerMode
                      ? 'Crea tu espacio financiero'
                      : 'Bienvenido de nuevo',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                    letterSpacing: -.5,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  registerMode
                      ? 'Privado, claro y siempre contigo.'
                      : 'Tu dinero, claro y protegido.',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Image.asset(
            'assets/images/auth_orbit_v2.png',
            width: 145,
            height: 145,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          ),
        ],
      ),
    );
  }
}

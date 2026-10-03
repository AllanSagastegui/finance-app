import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/aurea_components.dart';
import '../../../core/money/money.dart';
import '../data/accounts_repository.dart';
import '../domain/account_record.dart';

class CreateFirstAccountScreen extends ConsumerStatefulWidget {
  const CreateFirstAccountScreen({super.key});

  @override
  ConsumerState<CreateFirstAccountScreen> createState() =>
      _CreateFirstAccountScreenState();
}

class _CreateFirstAccountScreenState
    extends ConsumerState<CreateFirstAccountScreen> {
  final _name = TextEditingController(text: 'Efectivo');
  final _balance = TextEditingController(text: '0.00');
  AccountType _type = AccountType.cash;
  String _currency = 'PEN';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Primera cuenta')),
    body: AureaPageBackground(
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: Image.asset(
                      'assets/images/auth_orbit_v2.png',
                      width: 148,
                      height: 148,
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '¿Dónde está tu dinero?',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Crea una cuenta para que cada movimiento tenga un origen claro.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 60,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de la cuenta',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<AccountType>(
                    initialValue: _type,
                    decoration: const InputDecoration(labelText: 'Tipo'),
                    items: const [
                      DropdownMenuItem(
                        value: AccountType.cash,
                        child: Text('Efectivo'),
                      ),
                      DropdownMenuItem(
                        value: AccountType.debit,
                        child: Text('Débito'),
                      ),
                      DropdownMenuItem(
                        value: AccountType.credit,
                        child: Text('Crédito'),
                      ),
                      DropdownMenuItem(
                        value: AccountType.savings,
                        child: Text('Ahorro'),
                      ),
                      DropdownMenuItem(
                        value: AccountType.wallet,
                        child: Text('Billetera'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _type = value ?? AccountType.cash),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          initialValue: _currency,
                          decoration: const InputDecoration(
                            labelText: 'Moneda',
                          ),
                          items: const [
                            DropdownMenuItem(value: 'PEN', child: Text('PEN')),
                            DropdownMenuItem(value: 'USD', child: Text('USD')),
                          ],
                          onChanged: (value) =>
                              setState(() => _currency = value ?? 'PEN'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _balance,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => FocusScope.of(context).unfocus(),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Saldo inicial',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Crear cuenta y continuar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _save() async {
    final balance = Money.tryParseMinor(_balance.text);
    if (_name.text.trim().isEmpty || balance == null) {
      setState(() => _error = 'Revisa el nombre y el saldo inicial.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(accountsRepositoryProvider)
          .createAccount(
            name: _name.text,
            type: _type,
            currencyCode: _currency,
            initialBalanceMinor: balance,
          );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No pudimos crear la cuenta. Reintenta.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../accounts/data/accounts_repository.dart';
import '../data/finance_repository.dart';
import '../domain/transaction_record.dart';

class QuickAddSheet extends ConsumerStatefulWidget {
  const QuickAddSheet({super.key, this.initialType = TransactionType.expense});

  final TransactionType initialType;

  @override
  ConsumerState<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<QuickAddSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late TransactionType _type;
  String? _accountId;
  String? _destinationAccountId;
  String _categoryId = 'other';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final accounts = ref.watch(accountsProvider).value ?? const [];
    if (accounts.isNotEmpty) {
      _accountId ??= accounts.first.id;
      final destinations = accounts
          .where((account) => account.id != _accountId)
          .toList();
      if (destinations.isNotEmpty &&
          !destinations.any((account) => account.id == _destinationAccountId)) {
        _destinationAccountId = destinations.first.id;
      }
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + keyboard),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Nuevo movimiento',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Regístralo ahora. Puedes ajustar los detalles después.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<TransactionType>(
              segments: [
                const ButtonSegment(
                  value: TransactionType.expense,
                  label: Text('Gasto'),
                  icon: Icon(Icons.south_east_rounded),
                ),
                const ButtonSegment(
                  value: TransactionType.income,
                  label: Text('Ingreso'),
                  icon: Icon(Icons.north_east_rounded),
                ),
                ButtonSegment(
                  value: TransactionType.transfer,
                  label: Text('Mover'),
                  icon: Icon(Icons.swap_horiz_rounded),
                  enabled: accounts.length > 1,
                ),
              ],
              selected: {_type},
              onSelectionChanged: (value) =>
                  setState(() => _type = value.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: 22),
            TextField(
              controller: _amount,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^\d{0,9}([.,]\d{0,2})?'),
                ),
              ],
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displaySmall,
              decoration: const InputDecoration(
                prefixText: 'S/ ',
                hintText: '0.00',
                labelText: 'Importe',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _accountId,
              decoration: const InputDecoration(
                labelText: 'Cuenta',
                prefixIcon: Icon(Icons.account_balance_wallet_outlined),
              ),
              items: accounts
                  .map(
                    (account) => DropdownMenuItem(
                      value: account.id,
                      child: Text(account.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() {
                _accountId = value;
                _destinationAccountId = accounts
                    .where((account) => account.id != value)
                    .firstOrNull
                    ?.id;
              }),
            ),
            if (_type == TransactionType.transfer) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _destinationAccountId,
                decoration: const InputDecoration(
                  labelText: 'Cuenta de destino',
                  prefixIcon: Icon(Icons.move_down_rounded),
                ),
                items: accounts
                    .where((account) => account.id != _accountId)
                    .map(
                      (account) => DropdownMenuItem(
                        value: account.id,
                        child: Text(account.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _destinationAccountId = value),
              ),
            ],
            if (_type != TransactionType.transfer) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _categoryId,
                decoration: const InputDecoration(
                  labelText: 'Categoría',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 'food', child: Text('Alimentación')),
                  DropdownMenuItem(
                    value: 'transport',
                    child: Text('Transporte'),
                  ),
                  DropdownMenuItem(value: 'housing', child: Text('Vivienda')),
                  DropdownMenuItem(value: 'services', child: Text('Servicios')),
                  DropdownMenuItem(value: 'health', child: Text('Salud')),
                  DropdownMenuItem(
                    value: 'education',
                    child: Text('Educación'),
                  ),
                  DropdownMenuItem(
                    value: 'entertainment',
                    child: Text('Entretenimiento'),
                  ),
                  DropdownMenuItem(value: 'other', child: Text('Otros')),
                ],
                onChanged: (value) =>
                    setState(() => _categoryId = value ?? 'other'),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Nota opcional',
                counterText: '',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Guardar movimiento'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final minor = Money.tryParseMinor(_amount.text);
    if (minor == null || minor <= 0 || _accountId == null) {
      setState(() => _error = 'Ingresa un importe mayor que cero.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final accounts = ref.read(accountsProvider).value ?? const [];
      final currencyCode = accounts
          .where((account) => account.id == _accountId)
          .firstOrNull
          ?.currencyCode;
      await ref
          .read(financeRepositoryProvider)
          .createTransaction(
            type: _type,
            amountMinor: minor,
            currencyCode: currencyCode ?? 'PEN',
            accountId: _accountId!,
            destinationAccountId: _type == TransactionType.transfer
                ? _destinationAccountId
                : null,
            categoryId: _type == TransactionType.transfer ? null : _categoryId,
            occurredAt: DateTime.now(),
            description: _note.text,
          );
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      setState(
        () => _error =
            'No pudimos guardar. Tu formulario sigue aquí para reintentar.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/aurea_components.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/money/money.dart';
import '../data/accounts_repository.dart';
import '../domain/account_record.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Cuentas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva cuenta'),
      ),
      body: accounts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            _AccountsError(onRetry: () => ref.invalidate(accountsProvider)),
        data: (items) => items.isEmpty
            ? _NoAccounts(onCreate: () => _showEditor(context))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final account = items[index];
                  return _AccountCard(
                    account: account,
                    canArchive: items.length > 1,
                    onEdit: () => _showEditor(context, account: account),
                    onArchive: () => _archive(context, ref, account),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _showEditor(BuildContext context, {AccountRecord? account}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AccountEditor(account: account),
    );
  }

  Future<void> _archive(
    BuildContext context,
    WidgetRef ref,
    AccountRecord account,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.archive_outlined),
        title: Text('Archivar ${account.name}'),
        content: const Text(
          'La cuenta dejará de aparecer al crear movimientos. Su historial se conserva.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archivar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(accountsRepositoryProvider).archiveAccount(account.id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No pudimos archivar la cuenta.')),
        );
      }
    }
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.canArchive,
    required this.onEdit,
    required this.onArchive,
  });

  final AccountRecord account;
  final bool canArchive;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AureaRadius.lg),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              AureaIconBadge(icon: _accountIcon(account.type), size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _accountTypeLabel(account.type),
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Saldo disponible',
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Money(
                        account.currentBalanceMinor,
                        currencyCode: account.currencyCode,
                      ).format(),
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Opciones de ${account.name}',
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'archive') onArchive();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Editar'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'archive',
                    enabled: canArchive,
                    child: const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.archive_outlined),
                      title: Text('Archivar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountEditor extends ConsumerStatefulWidget {
  const _AccountEditor({this.account});

  final AccountRecord? account;

  @override
  ConsumerState<_AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends ConsumerState<_AccountEditor> {
  late final TextEditingController _name;
  late final TextEditingController _balance;
  late AccountType _type;
  late String _currency;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.account != null;

  @override
  void initState() {
    super.initState();
    final account = widget.account;
    _name = TextEditingController(text: account?.name ?? '');
    _balance = TextEditingController();
    _type = account?.type ?? AccountType.cash;
    _currency = account?.currencyCode ?? 'PEN';
  }

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _editing ? 'Editar cuenta' : 'Nueva cuenta',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<AccountType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: AccountType.values
                  .where((type) => type != AccountType.other)
                  .map(
                    (type) => DropdownMenuItem(
                      value: type,
                      child: Text(_accountTypeLabel(type)),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _type = value ?? _type),
            ),
            if (!_editing) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _currency,
                      decoration: const InputDecoration(labelText: 'Moneda'),
                      items: const [
                        DropdownMenuItem(value: 'PEN', child: Text('PEN')),
                        DropdownMenuItem(value: 'USD', child: Text('USD')),
                      ],
                      onChanged: (value) =>
                          setState(() => _currency = value ?? _currency),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _balance,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Saldo inicial',
                        hintText: '0.00',
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (_editing) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AureaRadius.md),
                ),
                child: const Text(
                  'El saldo se actualiza automáticamente con tus movimientos.',
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_editing ? 'Guardar cambios' : 'Crear cuenta'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final initialBalance = Money.tryParseMinor(
      _balance.text.trim().isEmpty ? '0' : _balance.text,
    );
    if (name.isEmpty || (!_editing && initialBalance == null)) {
      setState(() => _error = 'Completa un nombre y un saldo válido.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repository = ref.read(accountsRepositoryProvider);
      if (_editing) {
        await repository.updateAccount(
          accountId: widget.account!.id,
          name: name,
          type: _type,
        );
      } else {
        await repository.createAccount(
          name: name,
          type: _type,
          currencyCode: _currency,
          initialBalanceMinor: initialBalance!,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No pudimos guardar la cuenta. Reintenta.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _AccountsError extends StatelessWidget {
  const _AccountsError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 44),
          const SizedBox(height: 12),
          const Text('No pudimos cargar tus cuentas.'),
          TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    ),
  );
}

class _NoAccounts extends StatelessWidget {
  const _NoAccounts({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: AureaEmptyState(
        asset: 'assets/images/auth_orbit_v2.png',
        title: 'Tu dinero necesita un hogar',
        message:
            'Crea una cuenta para organizar saldos y registrar movimientos.',
        actionLabel: 'Crear cuenta',
        onAction: onCreate,
      ),
    ),
  );
}

String _accountTypeLabel(AccountType type) => switch (type) {
  AccountType.cash => 'Efectivo',
  AccountType.debit => 'Débito',
  AccountType.credit => 'Crédito',
  AccountType.savings => 'Ahorro',
  AccountType.wallet => 'Billetera',
  AccountType.other => 'Otra',
};

IconData _accountIcon(AccountType type) => switch (type) {
  AccountType.cash => Icons.payments_outlined,
  AccountType.debit => Icons.credit_card_outlined,
  AccountType.credit => Icons.credit_score_outlined,
  AccountType.savings => Icons.savings_outlined,
  AccountType.wallet => Icons.account_balance_wallet_outlined,
  AccountType.other => Icons.account_balance_outlined,
};

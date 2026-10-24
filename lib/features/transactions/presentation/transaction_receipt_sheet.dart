import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/aurea_components.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/money/money.dart';
import '../domain/transaction_record.dart';

Future<void> showTransactionReceipt(
  BuildContext context, {
  required TransactionRecord record,
  bool hideValues = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) =>
        TransactionReceiptSheet(record: record, hideValues: hideValues),
  );
}

class TransactionReceiptSheet extends StatelessWidget {
  const TransactionReceiptSheet({
    super.key,
    required this.record,
    this.hideValues = false,
  });

  final TransactionRecord record;
  final bool hideValues;

  @override
  Widget build(BuildContext context) {
    final isExpense = record.type == TransactionType.expense;
    final isTransfer = record.type == TransactionType.transfer;
    final accent = isTransfer
        ? AureaColors.indigo
        : isExpense
        ? AureaColors.negative
        : AureaColors.positive;
    final title = isTransfer
        ? 'Transferencia'
        : isExpense
        ? 'Gasto'
        : 'Ingreso';
    final amount = Money(
      record.amountMinor,
      currencyCode: record.currencyCode,
    ).format(hidden: hideValues);
    final allocation = record.goalAllocationMinor > 0
        ? Money(
            record.goalAllocationMinor,
            currencyCode: record.currencyCode,
          ).format(hidden: hideValues)
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      child: AureaEntrance(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Detalle del movimiento',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Información registrada en Aurea',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accent.withValues(alpha: .22),
                    Theme.of(context).colorScheme.surface,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AureaRadius.lg),
                border: Border.all(color: accent.withValues(alpha: .28)),
              ),
              child: Column(
                children: [
                  AureaIconBadge(
                    icon: isTransfer
                        ? Icons.swap_horiz_rounded
                        : isExpense
                        ? Icons.south_east_rounded
                        : Icons.north_east_rounded,
                    color: accent,
                    size: 62,
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(AureaRadius.pill),
                    ),
                    child: Text(
                      title,
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    amount,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.2,
                    ),
                  ),
                  if (record.description.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      record.description,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text('Información', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                child: Column(
                  children: [
                    _DetailRow(
                      icon: Icons.event_outlined,
                      label: 'Fecha',
                      value: DateFormat(
                        'd MMMM yyyy, HH:mm',
                        'es_PE',
                      ).format(record.occurredAt),
                    ),
                    _DetailRow(
                      icon: Icons.category_outlined,
                      label: 'Categoría',
                      value: _categoryLabel(record.categoryId),
                    ),
                    if (allocation != null)
                      _DetailRow(
                        icon: Icons.savings_outlined,
                        label: 'Asignado a meta',
                        value: allocation,
                        valueColor: AureaColors.teal,
                      ),
                    _DetailRow(
                      icon: Icons.fingerprint_rounded,
                      label: 'Código',
                      value: record.id,
                      compact: true,
                    ),
                    if (record.syncPending)
                      const _DetailRow(
                        icon: Icons.cloud_upload_outlined,
                        label: 'Estado',
                        value: 'Pendiente de sincronizar',
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest
                    .withValues(alpha: .45),
                borderRadius: BorderRadius.circular(AureaRadius.md),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.verified_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Este movimiento forma parte de tu historial financiero.',
                      style: Theme.of(context).textTheme.bodySmall,
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

  String _categoryLabel(String? id) => switch (id) {
    'food' => 'Alimentación',
    'transport' => 'Transporte',
    'housing' => 'Vivienda',
    'services' => 'Servicios',
    'health' => 'Salud',
    'education' => 'Educación',
    'entertainment' => 'Entretenimiento',
    'other' || null => 'General',
    _ => id,
  };
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 21, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 11 : null,
            ),
          ),
        ),
      ],
    ),
  );
}

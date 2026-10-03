import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/firebase/firebase_bootstrap.dart';
import '../../../core/money/money.dart';
import '../../accounts/data/accounts_repository.dart';
import '../data/finance_repository.dart';
import '../domain/transaction_record.dart';

class ImportCsvScreen extends ConsumerStatefulWidget {
  const ImportCsvScreen({super.key});

  @override
  ConsumerState<ImportCsvScreen> createState() => _ImportCsvScreenState();
}

class _ImportCsvScreenState extends ConsumerState<ImportCsvScreen> {
  List<ImportedTransactionDraft> _drafts = const [];
  List<String> _errors = const [];
  String? _filename;
  bool _busy = false;

  bool get _enabled =>
      FirebaseRemoteConfig.instance.getBool(RemoteKeys.csvImportEnabled);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Importar CSV')),
    body: !_enabled
        ? const _ImportDisabled()
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Trae tu historial',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Usa columnas: fecha, tipo, importe y descripción. La fecha puede ser ISO o dd/MM/yyyy; tipo acepta gasto o ingreso.',
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(_filename ?? 'Elegir archivo CSV'),
              ),
              if (_drafts.isNotEmpty) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Vista previa',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Chip(label: Text('${_drafts.length} válidos')),
                  ],
                ),
                const SizedBox(height: 10),
                Card(
                  child: Column(
                    children: _drafts.take(5).map((draft) {
                      final expense = draft.type == TransactionType.expense;
                      return ListTile(
                        leading: Icon(
                          expense
                              ? Icons.south_east_rounded
                              : Icons.north_east_rounded,
                        ),
                        title: Text(
                          draft.description.isEmpty
                              ? 'Movimiento'
                              : draft.description,
                        ),
                        subtitle: Text(
                          DateFormat.yMMMd('es_PE').format(draft.occurredAt),
                        ),
                        trailing: Text(
                          Money(draft.amountMinor).format(),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
              if (_errors.isNotEmpty) ...[
                const SizedBox(height: 14),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber_rounded),
                    title: Text('${_errors.length} filas necesitan revisión'),
                    subtitle: Text(_errors.take(3).join('\n')),
                  ),
                ),
              ],
              if (_drafts.isNotEmpty) ...[
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _import,
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text('Importar ${_drafts.length} movimientos'),
                ),
              ],
            ],
          ),
  );

  Future<void> _pick() async {
    final account = ref.read(accountsProvider).value?.firstOrNull;
    if (account == null) return;
    final file = await FilePicker.pickFile(
      dialogTitle: 'Selecciona un CSV',
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      setState(() => _errors = const ['El archivo supera el límite de 5 MB.']);
      return;
    }
    final rows = Csv().decode(utf8.decode(bytes, allowMalformed: false));
    final drafts = <ImportedTransactionDraft>[];
    final errors = <String>[];
    if (rows.isEmpty) return;
    final headers = rows.first
        .map((value) => value.toString().trim().toLowerCase())
        .toList();
    int column(String name) => headers.indexOf(name);
    final dateIndex = column('fecha');
    final typeIndex = column('tipo');
    final amountIndex = column('importe');
    final descriptionIndex = column('descripción') >= 0
        ? column('descripción')
        : column('descripcion');
    if ([dateIndex, typeIndex, amountIndex].contains(-1)) {
      setState(() {
        _drafts = const [];
        _errors = const ['Faltan columnas requeridas: fecha, tipo e importe.'];
        _filename = file.name;
      });
      return;
    }
    for (var index = 1; index < rows.length && index <= 5000; index++) {
      final row = rows[index];
      try {
        String valueAt(int position) => position >= 0 && position < row.length
            ? row[position].toString().trim()
            : '';
        final dateText = valueAt(dateIndex);
        final occurredAt =
            DateTime.tryParse(dateText) ??
            DateFormat('dd/MM/yyyy').parseStrict(dateText);
        final typeText = valueAt(typeIndex).toLowerCase();
        final type = switch (typeText) {
          'gasto' || 'expense' => TransactionType.expense,
          'ingreso' || 'income' => TransactionType.income,
          _ => throw const FormatException('tipo'),
        };
        final amountMinor = Money.tryParseMinor(valueAt(amountIndex));
        if (amountMinor == null || amountMinor <= 0) {
          throw const FormatException('importe');
        }
        drafts.add(
          ImportedTransactionDraft(
            type: type,
            amountMinor: amountMinor,
            currencyCode: account.currencyCode,
            accountId: account.id,
            description: valueAt(descriptionIndex),
            occurredAt: occurredAt,
          ),
        );
      } catch (_) {
        errors.add('Fila ${index + 1}: fecha, tipo o importe inválido.');
      }
    }
    setState(() {
      _drafts = drafts;
      _errors = errors;
      _filename = file.name;
    });
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final count = await ref
          .read(financeRepositoryProvider)
          .importTransactions(_drafts);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count movimientos importados.')),
        );
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errors = [..._errors, 'La importación no se completó. Reintenta.'];
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ImportDisabled extends StatelessWidget {
  const _ImportDisabled();
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hourglass_top_rounded, size: 48),
          SizedBox(height: 16),
          Text(
            'La importación CSV todavía no está habilitada para este entorno.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

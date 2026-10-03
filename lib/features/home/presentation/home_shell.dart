import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/aurea_components.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/money/money.dart';
import '../../accounts/data/accounts_repository.dart';
import '../../accounts/domain/account_record.dart';
import '../../accounts/presentation/create_first_account_screen.dart';
import '../../auth/data/auth_repository.dart';
import '../../planning/data/planning_repository.dart';
import '../../transactions/data/finance_repository.dart';
import '../../transactions/domain/transaction_record.dart';
import '../../transactions/presentation/quick_add_sheet.dart';

final connectivityProvider = StreamProvider<List<ConnectivityResult>>((ref) {
  return Connectivity().onConnectivityChanged;
});

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  bool _hideValues = false;

  static const _labels = [
    'Inicio',
    'Movimientos',
    'Plan',
    'Insights',
    'Perfil',
  ];
  static const _icons = [
    Icons.home_outlined,
    Icons.swap_vert_circle_outlined,
    Icons.flag_outlined,
    Icons.insights_outlined,
    Icons.person_outline_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsProvider);
    if (accountsAsync case AsyncLoading()) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (accountsAsync case AsyncError()) {
      return Scaffold(
        body: Center(
          child: _InlineError(onRetry: () => ref.invalidate(accountsProvider)),
        ),
      );
    }
    final accounts = accountsAsync.value ?? const <AccountRecord>[];
    if (accounts.isEmpty) return const CreateFirstAccountScreen();

    final offline =
        ref
            .watch(connectivityProvider)
            .value
            ?.contains(ConnectivityResult.none) ??
        false;
    final pages = [
      DashboardScreen(
        accounts: accounts,
        hideValues: _hideValues,
        onToggleValues: () => setState(() => _hideValues = !_hideValues),
        onOpenTab: (index) => setState(() => _index = index),
        onQuickAdd: (type) => _openQuickAdd(type),
      ),
      TransactionsScreen(hideValues: _hideValues),
      const PlanScreen(),
      InsightsScreen(hideValues: _hideValues),
      const ProfileScreen(),
    ];

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: _index == 0
            ? const AureaBrandLockup(compact: true)
            : Text(_labels[_index]),
        backgroundColor: Colors.transparent,
        actions: [
          if (offline)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Chip(
                avatar: Icon(Icons.cloud_off_outlined, size: 16),
                label: Text('Sin conexión'),
              ),
            ),
          IconButton(
            tooltip: 'Notificaciones',
            onPressed: () => _showSimplePage(
              context,
              'Notificaciones',
              'Aquí verás recordatorios seguros de presupuestos y recurrentes.',
            ),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AureaPageBackground(
        child: IndexedStack(index: _index, children: pages),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'quick-add',
        tooltip: 'Registrar movimiento',
        onPressed: () => _openQuickAdd(TransactionType.expense),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Movimiento'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          if (value == _index) return;
          HapticFeedback.selectionClick();
          setState(() => _index = value);
        },
        destinations: List.generate(
          _labels.length,
          (index) => NavigationDestination(
            icon: Icon(_icons[index]),
            label: _labels[index],
          ),
        ),
      ),
    );
  }

  void _openQuickAdd(TransactionType type) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => QuickAddSheet(initialType: type),
    );
  }

  void _showSimplePage(BuildContext context, String title, String message) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(message),
          ),
        ),
      ),
    );
  }
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({
    super.key,
    required this.accounts,
    required this.hideValues,
    required this.onToggleValues,
    required this.onOpenTab,
    required this.onQuickAdd,
  });

  final List<AccountRecord> accounts;
  final bool hideValues;
  final VoidCallback onToggleValues;
  final ValueChanged<int> onOpenTab;
  final ValueChanged<TransactionType> onQuickAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactions = ref.watch(recentTransactionsProvider);
    final summary =
        ref.watch(dashboardSummaryProvider).value ?? const DashboardSummary();
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(recentTransactionsProvider),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 160),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      toBeginningOfSentenceCase(
                        DateFormat.yMMMM('es_PE').format(DateTime.now()),
                      ),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tu panorama',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: hideValues ? 'Mostrar cifras' : 'Ocultar cifras',
                onPressed: onToggleValues,
                icon: Icon(
                  hideValues
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _BalanceHero(
            accounts: accounts,
            summary: summary,
            hideValues: hideValues,
          ),
          const SizedBox(height: 14),
          _QuickActions(
            canTransfer: accounts.length > 1,
            onSelected: onQuickAdd,
          ),
          const SizedBox(height: 24),
          const AureaSectionHeader(
            title: 'Pulso del mes',
            subtitle: 'Tu presupuesto más activo',
          ),
          const SizedBox(height: 12),
          _BudgetPulse(onOpenPlan: () => onOpenTab(2)),
          const SizedBox(height: 24),
          AureaSectionHeader(
            title: 'Flujo de caja',
            subtitle: 'Balance neto de los últimos 6 meses',
            actionLabel: 'Ver insights',
            onAction: () => onOpenTab(3),
          ),
          const SizedBox(height: 8),
          _CashFlowChart(records: transactions.value ?? const []),
          const SizedBox(height: 24),
          AureaSectionHeader(
            title: 'Movimientos recientes',
            subtitle: 'Lo último que pasó en tus cuentas',
            actionLabel: 'Ver todos',
            onAction: () => onOpenTab(1),
          ),
          const SizedBox(height: 8),
          transactions.when(
            loading: () => const _LoadingTransactions(),
            error: (error, _) => _InlineError(
              onRetry: () => ref.invalidate(recentTransactionsProvider),
            ),
            data: (items) => items.isEmpty
                ? const _EmptyTransactions()
                : Card(
                    child: Column(
                      children: items.take(5).map((item) {
                        return TransactionTile(
                          record: item,
                          hideValues: hideValues,
                        );
                      }).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.canTransfer, required this.onSelected});

  final bool canTransfer;
  final ValueChanged<TransactionType> onSelected;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _QuickAction(
          icon: Icons.south_east_rounded,
          label: 'Gasto',
          color: AureaColors.negative,
          onTap: () => onSelected(TransactionType.expense),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _QuickAction(
          icon: Icons.north_east_rounded,
          label: 'Ingreso',
          color: AureaColors.positive,
          onTap: () => onSelected(TransactionType.income),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _QuickAction(
          icon: Icons.swap_horiz_rounded,
          label: 'Mover',
          color: AureaColors.indigo,
          onTap: canTransfer
              ? () => onSelected(TransactionType.transfer)
              : null,
        ),
      ),
    ],
  );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).cardTheme.color,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AureaRadius.md),
      side: BorderSide(
        color: Theme.of(context).colorScheme.outlineVariant
            .withValues(alpha: .45),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Column(
          children: [
            AureaIconBadge(icon: icon, color: color, size: 38),
            const SizedBox(height: 7),
            Text(
              label,
              maxLines: 1,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: onTap == null ? Theme.of(context).disabledColor : null,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({
    required this.accounts,
    required this.summary,
    required this.hideValues,
  });
  final List<AccountRecord> accounts;
  final DashboardSummary summary;
  final bool hideValues;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = accounts
        .where((account) => account.currencyCode == 'PEN')
        .fold<int>(0, (sum, account) => sum + account.currentBalanceMinor);
    return Semantics(
      label: hideValues ? 'Balance oculto' : 'Balance total en soles',
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              AureaColors.indigo,
              AureaColors.violet,
              AureaColors.indigoDark,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AureaRadius.lg),
          border: Border.all(color: Colors.white.withValues(alpha: .14)),
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: .22),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Patrimonio total',
                    style: TextStyle(
                      color: scheme.onPrimary.withValues(alpha: .78),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(AureaRadius.pill),
                  ),
                  child: Text(
                    '${accounts.length} cuenta${accounts.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: scheme.onPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              Money(total).format(hidden: hideValues),
              style: Theme.of(context).textTheme.displaySmall
                  ?.copyWith(color: scheme.onPrimary),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                _Metric(
                  label: 'Ingresos',
                  value: Money(summary.incomeMinor).format(hidden: hideValues),
                ),
                const SizedBox(width: 8),
                _Metric(
                  label: 'Gastos',
                  value: Money(summary.expenseMinor).format(hidden: hideValues),
                ),
                const SizedBox(width: 8),
                _Metric(
                  label: 'Ahorro',
                  value: Money(summary.netMinor).format(hidden: hideValues),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .72),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    ),
  );
}

class _BudgetPulse extends ConsumerWidget {
  const _BudgetPulse({required this.onOpenPlan});

  final VoidCallback onOpenPlan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(budgetsProvider);
    return budgets.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: LinearProgressIndicator(minHeight: 7),
        ),
      ),
      error: (_, _) => Card(
        child: ListTile(
          leading: const AureaIconBadge(icon: Icons.sync_problem_outlined),
          title: const Text('No pudimos cargar tus presupuestos'),
          trailing: const Icon(Icons.refresh_rounded),
          onTap: () => ref.invalidate(budgetsProvider),
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 10,
              ),
              leading: const AureaIconBadge(
                icon: Icons.pie_chart_outline_rounded,
              ),
              title: const Text('Crea tu primer presupuesto'),
              subtitle: const Text('Define un límite y sigue tu avance.'),
              trailing: const Icon(Icons.arrow_forward_rounded),
              onTap: onOpenPlan,
            ),
          );
        }
        final budget = items.first;
        final progress = budget.limitMinor <= 0
            ? 0.0
            : (budget.spentMinor / budget.limitMinor).clamp(0.0, 1.0);
        final available = (budget.limitMinor - budget.spentMinor)
            .clamp(0, budget.limitMinor)
            .toInt();
        final accent = progress >= 1
            ? AureaColors.negative
            : progress >= .8
            ? AureaColors.warning
            : AureaColors.indigo;
        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(AureaRadius.lg),
            onTap: onOpenPlan,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Row(
                    children: [
                      AureaIconBadge(
                        icon: Icons.pie_chart_outline_rounded,
                        color: accent,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              budget.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              '${(progress * 100).round()}% utilizado',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: progress,
                    color: accent,
                    minHeight: 9,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        '${Money(budget.spentMinor, currencyCode: budget.currencyCode).format()} usados',
                      ),
                      const Spacer(),
                      Text(
                        '${Money(available, currencyCode: budget.currencyCode).format()} libres',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CashFlowChart extends StatelessWidget {
  const _CashFlowChart({required this.records});

  final List<TransactionRecord> records;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final months = List.generate(
      6,
      (index) => DateTime(now.year, now.month - 5 + index),
    );
    String key(DateTime date) => '${date.year}-${date.month}';
    final values = {for (final month in months) key(month): 0};
    for (final record in records) {
      final monthKey = key(record.occurredAt);
      if (!values.containsKey(monthKey)) continue;
      final signed = switch (record.type) {
        TransactionType.income => record.amountMinor,
        TransactionType.expense => -record.amountMinor,
        _ => 0,
      };
      values[monthKey] = values[monthKey]! + signed;
    }
    final monthly = months.map((month) => values[key(month)]!).toList();
    if (monthly.every((value) => value == 0)) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: AureaIconBadge(icon: Icons.show_chart_rounded),
            title: Text('Tu tendencia aparecerá aquí'),
            subtitle: Text('Registra movimientos para construirla.'),
          ),
        ),
      );
    }
    final amounts = monthly.map((value) => value / 100).toList();
    final lowest = amounts.reduce((a, b) => a < b ? a : b);
    final highest = amounts.reduce((a, b) => a > b ? a : b);
    final padding = ((highest - lowest).abs() * .2).clamp(50.0, 1000000.0);
    final minY = lowest < 0 ? lowest - padding : 0.0;
    final maxY = highest > 0 ? highest + padding : padding;
    return Card(
      child: SizedBox(
        height: 220,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 20, 14),
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: 5,
              minY: minY,
              maxY: maxY,
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: (maxY - minY) / 3,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: Theme.of(context).colorScheme.outlineVariant
                      .withValues(alpha: .45),
                  strokeWidth: 1,
                  dashArray: [5, 5],
                ),
              ),
              extraLinesData: minY < 0 && maxY > 0
                  ? ExtraLinesData(
                      horizontalLines: [
                        HorizontalLine(
                          y: 0,
                          color: Theme.of(context).colorScheme.outline,
                          strokeWidth: 1,
                        ),
                      ],
                    )
                  : null,
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    getTitlesWidget: (value, meta) => Padding(
                      padding: const EdgeInsets.only(top: 9),
                      child: Text(
                        toBeginningOfSentenceCase(
                          DateFormat.MMM('es_PE')
                              .format(months[value.toInt().clamp(0, 5)]),
                        ),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: List.generate(
                    amounts.length,
                    (index) => FlSpot(index.toDouble(), amounts[index]),
                  ),
                  isCurved: true,
                  curveSmoothness: .25,
                  color: AureaColors.indigo,
                  barWidth: 4,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                      radius: 3,
                      color: AureaColors.indigo,
                      strokeWidth: 2,
                      strokeColor: Theme.of(context).colorScheme.surface,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AureaColors.indigo.withValues(alpha: .18),
                        AureaColors.indigo.withValues(alpha: .01),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
          ),
        ),
      ),
    );
  }
}

enum _TransactionFilter { all, expense, income, transfer }

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key, required this.hideValues});
  final bool hideValues;

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _search = TextEditingController();
  _TransactionFilter _filter = _TransactionFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(recentTransactionsProvider);
    return value.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(20),
        child: _LoadingTransactions(),
      ),
      error: (error, stackTrace) => Center(
        child: _InlineError(
          onRetry: () => ref.invalidate(recentTransactionsProvider),
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: _EmptyTransactions(),
            ),
          );
        }
        final query = _search.text.trim().toLowerCase();
        final filtered = items.where((item) {
          final matchesQuery =
              query.isEmpty ||
              item.description.toLowerCase().contains(query) ||
              _categoryLabel(item.categoryId).toLowerCase().contains(query) ||
              Money(
                item.amountMinor,
                currencyCode: item.currencyCode,
              ).format().toLowerCase().contains(query);
          final matchesType = switch (_filter) {
            _TransactionFilter.all => true,
            _TransactionFilter.expense => item.type == TransactionType.expense,
            _TransactionFilter.income => item.type == TransactionType.income,
            _TransactionFilter.transfer =>
              item.type == TransactionType.transfer,
          };
          return matchesQuery && matchesType;
        }).toList();
        return ListView.builder(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 160),
          itemCount: filtered.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SearchBar(
                    controller: _search,
                    hintText: 'Buscar movimientos',
                    leading: const Icon(Icons.search_rounded),
                    onChanged: (_) => setState(() {}),
                    trailing: [
                      if (_search.text.isNotEmpty)
                        IconButton(
                          tooltip: 'Limpiar búsqueda',
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children:
                          [
                            (_TransactionFilter.all, 'Todos'),
                            (_TransactionFilter.expense, 'Gastos'),
                            (_TransactionFilter.income, 'Ingresos'),
                            (_TransactionFilter.transfer, 'Transferencias'),
                          ].map((item) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(item.$2),
                                selected: _filter == item.$1,
                                onSelected: (_) =>
                                    setState(() => _filter = item.$1),
                              ),
                            );
                          }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (filtered.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(Icons.search_off_rounded, size: 38),
                            SizedBox(height: 10),
                            Text(
                              'No encontramos movimientos con estos filtros.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: TransactionTile(
                  record: filtered[index - 1],
                  hideValues: widget.hideValues,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.record,
    required this.hideValues,
  });
  final TransactionRecord record;
  final bool hideValues;
  @override
  Widget build(BuildContext context) {
    final expense = record.type == TransactionType.expense;
    final transfer = record.type == TransactionType.transfer;
    final color = transfer
        ? Theme.of(context).colorScheme.primary
        : expense
        ? AureaColors.negative
        : AureaColors.positive;
    final iconColor = transfer
        ? AureaColors.indigo
        : expense
        ? _categoryColor(record.categoryId)
        : AureaColors.positive;
    return ListTile(
      minTileHeight: 68,
      leading: CircleAvatar(
        backgroundColor: iconColor.withValues(alpha: .12),
        child: Icon(
          transfer
              ? Icons.swap_horiz_rounded
              : expense
              ? _categoryIcon(record.categoryId)
              : Icons.north_east_rounded,
          color: iconColor,
        ),
      ),
      title: Text(
        record.description.isEmpty ? 'Movimiento' : record.description,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${_categoryLabel(record.categoryId)} · ${DateFormat.MMMd('es_PE').format(record.occurredAt)}${record.syncPending ? ' · Pendiente de sincronizar' : ''}',
      ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 116),
        child: Text(
          '${transfer
              ? ''
              : expense
              ? '−'
              : '+'}${Money(record.amountMinor, currencyCode: record.currencyCode).format(hidden: hideValues)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
          style: TextStyle(fontWeight: FontWeight.w800, color: color),
        ),
      ),
    );
  }
}

class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(budgetsProvider).value ?? const [];
    final goals = ref.watch(goalsProvider).value ?? const [];
    final recurring = ref.watch(recurringProvider).value ?? const [];
    final isEmpty = budgets.isEmpty && goals.isEmpty && recurring.isEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 160),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Tus próximos pasos',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Crear plan',
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                showDragHandle: true,
                builder: (_) =>
                    const _PlanComposer(initialKind: _PlanKind.budget),
              ),
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (isEmpty) ...[const _PlanEmptyHero(), const SizedBox(height: 18)],
        if (budgets.isEmpty)
          const _PlanCard(
            icon: Icons.pie_chart_outline_rounded,
            title: 'Crea tu primer presupuesto',
            subtitle:
                'Define un límite mensual y recibe alertas al 80% y 100%.',
            progress: 0,
            emptyKind: _PlanKind.budget,
          )
        else
          ...budgets.map(
            (budget) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PlanCard(
                icon: Icons.pie_chart_outline_rounded,
                title: budget.name,
                subtitle:
                    '${Money(budget.spentMinor).format()} de ${Money(budget.limitMinor).format()}',
                progress: budget.limitMinor == 0
                    ? 0
                    : (budget.spentMinor / budget.limitMinor).clamp(0, 1),
              ),
            ),
          ),
        const SizedBox(height: 12),
        if (goals.isEmpty)
          const _PlanCard(
            icon: Icons.flag_outlined,
            title: 'Añade una meta',
            subtitle: 'Separa un objetivo de ahorro y registra sus aportes.',
            progress: 0,
            emptyKind: _PlanKind.goal,
          )
        else
          ...goals.map(
            (goal) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PlanCard(
                icon: Icons.flag_outlined,
                title: goal.name,
                subtitle:
                    '${Money(goal.savedAmountMinor).format()} de ${Money(goal.targetAmountMinor).format()}',
                progress: goal.targetAmountMinor == 0
                    ? 0
                    : (goal.savedAmountMinor / goal.targetAmountMinor).clamp(
                        0,
                        1,
                      ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        _PlanCard(
          icon: Icons.repeat_rounded,
          title: recurring.isEmpty
              ? 'Configura un recurrente'
              : '${recurring.length} recurrente${recurring.length == 1 ? '' : 's'} activo${recurring.length == 1 ? '' : 's'}',
          subtitle: recurring.isEmpty
              ? 'Anticipa suscripciones, servicios e ingresos periódicos.'
              : recurring.take(2).map((item) => item.name).join(' · '),
          progress: 0,
          emptyKind: recurring.isEmpty ? _PlanKind.recurring : null,
          showProgress: false,
          statusLabel: recurring.isEmpty ? null : 'Activo',
        ),
      ],
    );
  }
}

class _PlanEmptyHero extends StatelessWidget {
  const _PlanEmptyHero();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primaryContainer.withValues(alpha: .64),
            scheme.secondaryContainer.withValues(alpha: .5),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AureaRadius.lg),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .45)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Convierte intención en progreso',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900, height: 1.08),
                ),
                const SizedBox(height: 8),
                Text(
                  'Empieza con un presupuesto, una meta o un recurrente.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Image.asset(
            'assets/images/empty_plan_v2.png',
            width: 132,
            height: 132,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.progress,
    this.emptyKind,
    this.showProgress = true,
    this.statusLabel,
  });
  final IconData icon;
  final String title, subtitle;
  final double progress;
  final _PlanKind? emptyKind;
  final bool showProgress;
  final String? statusLabel;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: emptyKind == null
          ? null
          : () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => _PlanComposer(initialKind: emptyKind!),
            ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                AureaIconBadge(icon: icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (statusLabel != null)
                  Chip(
                    label: Text(statusLabel!),
                    visualDensity: VisualDensity.compact,
                  )
                else if (emptyKind != null)
                  const Icon(Icons.chevron_right),
              ],
            ),
            if (emptyKind == null && showProgress) ...[
              const SizedBox(height: 14),
              LinearProgressIndicator(value: progress, minHeight: 8),
              const SizedBox(height: 9),
            ] else
              const SizedBox(height: 8),
            Align(alignment: Alignment.centerLeft, child: Text(subtitle)),
          ],
        ),
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
  null => 'Transferencia',
  _ => 'Otros',
};

IconData _categoryIcon(String? id) => switch (id) {
  'food' => Icons.restaurant_rounded,
  'transport' => Icons.directions_car_filled_outlined,
  'housing' => Icons.home_work_outlined,
  'services' => Icons.bolt_outlined,
  'health' => Icons.favorite_outline_rounded,
  'education' => Icons.school_outlined,
  'entertainment' => Icons.movie_outlined,
  _ => Icons.shopping_bag_outlined,
};

Color _categoryColor(String? id) => switch (id) {
  'food' => const Color(0xFFF08A4B),
  'transport' => const Color(0xFF3E8ED0),
  'housing' => const Color(0xFF7B61FF),
  'services' => const Color(0xFFD79A32),
  'health' => const Color(0xFFE2647A),
  'education' => const Color(0xFF4D75D9),
  'entertainment' => const Color(0xFF9B5BC7),
  _ => AureaColors.teal,
};

enum _PlanKind { budget, goal, recurring }

class _PlanComposer extends ConsumerStatefulWidget {
  const _PlanComposer({required this.initialKind});
  final _PlanKind initialKind;
  @override
  ConsumerState<_PlanComposer> createState() => _PlanComposerState();
}

class _PlanComposerState extends ConsumerState<_PlanComposer> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  late _PlanKind _kind;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      0,
      20,
      20 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Crear plan', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                [
                  (_PlanKind.budget, 'Presupuesto', Icons.pie_chart_outline),
                  (_PlanKind.goal, 'Meta', Icons.flag_outlined),
                  (_PlanKind.recurring, 'Recurrente', Icons.repeat_rounded),
                ].map((item) {
                  return ChoiceChip(
                    avatar: Icon(item.$3, size: 18),
                    label: Text(item.$2),
                    selected: _kind == item.$1,
                    onSelected: (_) => setState(() => _kind = item.$1),
                  );
                }).toList(),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 60,
            decoration: InputDecoration(
              labelText: _kind == _PlanKind.recurring
                  ? 'Descripción'
                  : 'Nombre',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              prefixText: 'S/ ',
              labelText: _kind == _PlanKind.budget
                  ? 'Límite mensual'
                  : _kind == _PlanKind.goal
                  ? 'Monto objetivo'
                  : 'Importe periódico',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Guardar'),
          ),
        ],
      ),
    ),
  );

  Future<void> _save() async {
    final amount = Money.tryParseMinor(_amount.text);
    final accounts = ref.read(accountsProvider).value ?? const [];
    if (_name.text.trim().isEmpty ||
        amount == null ||
        amount <= 0 ||
        (_kind == _PlanKind.recurring && accounts.isEmpty)) {
      setState(() => _error = 'Completa un nombre y un importe válido.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repository = ref.read(planningRepositoryProvider);
      switch (_kind) {
        case _PlanKind.budget:
          await repository.createBudget(name: _name.text, limitMinor: amount);
        case _PlanKind.goal:
          await repository.createGoal(
            name: _name.text,
            targetAmountMinor: amount,
          );
        case _PlanKind.recurring:
          await repository.createRecurring(
            description: _name.text,
            amountMinor: amount,
            accountId: accounts.first.id,
          );
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No pudimos guardar este plan. Reintenta.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key, required this.hideValues});
  final bool hideValues;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(dashboardSummaryProvider);
    final summary = summaryAsync.value ?? const DashboardSummary();
    final rate = summary.incomeMinor <= 0
        ? 0.0
        : (summary.netMinor / summary.incomeMinor).clamp(0.0, 1.0);
    final reading = summary.incomeMinor == 0 && summary.expenseMinor == 0
        ? 'Registra movimientos para comenzar a ver patrones del mes.'
        : summary.netMinor >= 0
        ? 'Estás conservando ${(rate * 100).round()}% de tus ingresos de este mes.'
        : 'Tus gastos superan tus ingresos. Revisa los movimientos más grandes antes de cerrar el mes.';
    final month = toBeginningOfSentenceCase(
      DateFormat.yMMMM('es_PE').format(DateTime.now()),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 160),
      children: [
        Text(month, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Lecturas construidas con tus movimientos reales.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AureaColors.indigo, AureaColors.indigoDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AureaRadius.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Balance del mes',
                style: TextStyle(color: Colors.white.withValues(alpha: .75)),
              ),
              const SizedBox(height: 8),
              Text(
                Money(
                  summary.netMinor,
                  currencyCode: summary.currencyCode,
                ).format(hidden: hideValues),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (summaryAsync.isLoading) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(minHeight: 2),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _InsightMetric(
                label: 'Ingresos',
                icon: Icons.north_east_rounded,
                color: AureaColors.positive,
                value: Money(
                  summary.incomeMinor,
                  currencyCode: summary.currencyCode,
                ).format(hidden: hideValues),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _InsightMetric(
                label: 'Gastos',
                icon: Icons.south_east_rounded,
                color: AureaColors.negative,
                value: Money(
                  summary.expenseMinor,
                  currencyCode: summary.currencyCode,
                ).format(hidden: hideValues),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Text('Tasa de ahorro', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.savings_outlined),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('Progreso mensual')),
                    Text('${(rate * 100).round()}%'),
                  ],
                ),
                const SizedBox(height: 14),
                LinearProgressIndicator(
                  value: rate,
                  minHeight: 9,
                  borderRadius: const BorderRadius.all(Radius.circular(99)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: ListTile(
            leading: const Icon(
              Icons.lightbulb_outline,
              color: AureaColors.warning,
            ),
            title: const Text('Lectura del mes'),
            subtitle: Text(reading),
          ),
        ),
      ],
    );
  }
}

class _InsightMetric extends StatelessWidget {
  const _InsightMetric({
    required this.label,
    required this.icon,
    required this.color,
    required this.value,
  });

  final String label;
  final IconData icon;
  final Color color;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 12),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    ),
  );
}

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 160),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: ListTile(
              leading: CircleAvatar(
                radius: 28,
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                child: Text(
                  (user?.displayName ?? user?.email ?? 'A')[0].toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              title: Text(
                user?.displayName ?? 'Tu cuenta',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              subtitle: Text(user?.email ?? ''),
              trailing: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AureaColors.positive.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(AureaRadius.pill),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      color: AureaColors.positive,
                      size: 16,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'Protegida',
                      style: TextStyle(
                        color: AureaColors.positive,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Column(
            children: [
              _SettingsTile(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Cuentas',
                onTap: () => context.push('/accounts'),
              ),
              _SettingsTile(
                icon: Icons.shield_outlined,
                title: 'Seguridad',
                onTap: () => context.push('/security'),
              ),
              _SettingsTile(
                icon: Icons.lock_outline,
                title: 'Datos y privacidad',
                onTap: () => context.push('/privacy'),
              ),
              _SettingsTile(
                icon: Icons.palette_outlined,
                title: 'Apariencia',
                onTap: () => context.push('/appearance'),
              ),
              _SettingsTile(
                icon: Icons.upload_file_outlined,
                title: 'Importar CSV',
                onTap: () => context.push('/import-csv'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () async {
            await ref.read(authRepositoryProvider).signOut();
            if (context.mounted) context.go('/login');
          },
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Cerrar sesión'),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: AureaIconBadge(icon: icon, size: 40),
    title: Text(title),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}

class _EmptyTransactions extends StatelessWidget {
  const _EmptyTransactions();
  @override
  Widget build(BuildContext context) => const AureaEmptyState(
    asset: 'assets/images/empty_transactions.png',
    title: 'Aún no hay movimientos',
    message: 'Usa “Movimiento” para registrar tu primer gasto, ingreso o transferencia.',
    imageSize: 172,
  );
}

class _LoadingTransactions extends StatelessWidget {
  const _LoadingTransactions();
  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      children: List.generate(
        3,
        (_) => const ListTile(
          leading: CircleAvatar(),
          title: LinearProgressIndicator(),
          subtitle: LinearProgressIndicator(),
        ),
      ),
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AureaIconBadge(icon: Icons.sync_problem_outlined),
          const SizedBox(height: 8),
          const Text('No pudimos actualizar tus movimientos.'),
          TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    ),
  );
}

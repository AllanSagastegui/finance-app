import 'dart:async';

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
import '../../../core/preferences/app_preferences.dart';
import '../../accounts/data/accounts_repository.dart';
import '../../accounts/domain/account_record.dart';
import '../../accounts/presentation/create_first_account_screen.dart';
import '../../auth/data/auth_repository.dart';
import '../../planning/data/planning_repository.dart';
import '../../transactions/data/finance_repository.dart';
import '../../transactions/domain/transaction_record.dart';
import '../../transactions/presentation/quick_add_sheet.dart';
import '../../transactions/presentation/transaction_receipt_sheet.dart';

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
  bool _tutorialScheduled = false;
  final _balanceKey = GlobalKey();
  final _quickActionsKey = GlobalKey();
  final _transactionsTabKey = GlobalKey();
  final _planTabKey = GlobalKey();
  final _insightsTabKey = GlobalKey();
  final _profileTabKey = GlobalKey();
  final _quickAddKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final planning = ref.read(planningRepositoryProvider);
      await planning.materializeDueRecurring();
      await planning.reconcileCurrentMonthBudgets();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowTutorial());
  }

  Future<void> _maybeShowTutorial() async {
    if (_tutorialScheduled || !mounted) return;
    _tutorialScheduled = true;
    final preferences = AppPreferences();
    if (await preferences.hasCompletedAppTutorial() || !mounted) return;
    await showAureaTutorial(
      context,
      onTabChanged: (index) => setState(() => _index = index),
      targets: AureaTutorialTargets(
        balance: _balanceKey,
        quickActions: _quickActionsKey,
        transactionsTab: _transactionsTabKey,
        planTab: _planTabKey,
        insightsTab: _insightsTabKey,
        profileTab: _profileTabKey,
        quickAdd: _quickAddKey,
      ),
    );
  }

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
      return const Scaffold(body: _HomeShellSkeleton());
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
    if (offline) {
      return OfflineScreen(onRetry: () => ref.invalidate(connectivityProvider));
    }
    final pages = [
      DashboardScreen(
        accounts: accounts,
        balanceKey: _balanceKey,
        quickActionsKey: _quickActionsKey,
        hideValues: _hideValues,
        onToggleValues: () => setState(() => _hideValues = !_hideValues),
        onOpenTab: (index) => setState(() => _index = index),
        onQuickAdd: (type) => _openQuickAdd(type),
      ),
      TransactionsScreen(hideValues: _hideValues),
      const PlanScreen(),
      InsightsScreen(hideValues: _hideValues),
      ProfileScreen(
        onShowTutorial: () => showAureaTutorial(
          context,
          onTabChanged: (index) => setState(() => _index = index),
          targets: AureaTutorialTargets(
            balance: _balanceKey,
            quickActions: _quickActionsKey,
            transactionsTab: _transactionsTabKey,
            planTab: _planTabKey,
            insightsTab: _insightsTabKey,
            profileTab: _profileTabKey,
            quickAdd: _quickAddKey,
          ),
        ),
      ),
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
        key: _quickAddKey,
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
            key: switch (index) {
              1 => _transactionsTabKey,
              2 => _planTabKey,
              3 => _insightsTabKey,
              4 => _profileTabKey,
              _ => null,
            },
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
    required this.balanceKey,
    required this.quickActionsKey,
    required this.hideValues,
    required this.onToggleValues,
    required this.onOpenTab,
    required this.onQuickAdd,
  });

  final List<AccountRecord> accounts;
  final GlobalKey balanceKey;
  final GlobalKey quickActionsKey;
  final bool hideValues;
  final VoidCallback onToggleValues;
  final ValueChanged<int> onOpenTab;
  final ValueChanged<TransactionType> onQuickAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactions = ref.watch(recentTransactionsProvider);
    final summaryAsync = ref.watch(dashboardSummaryProvider);
    if (transactions.isLoading || summaryAsync.isLoading) {
      return const _DashboardSkeleton();
    }
    final summary = summaryAsync.value ?? const DashboardSummary();
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
          AureaEntrance(
            child: KeyedSubtree(
              key: balanceKey,
              child: _BalanceHero(
                accounts: accounts,
                summary: summary,
                hideValues: hideValues,
              ),
            ),
          ),
          const SizedBox(height: 14),
          AureaEntrance(
            delay: const Duration(milliseconds: 70),
            child: KeyedSubtree(
              key: quickActionsKey,
              child: _QuickActions(
                canTransfer: accounts.length > 1,
                onSelected: onQuickAdd,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const AureaSectionHeader(
            title: 'Pulso del mes',
            subtitle: 'Tu presupuesto más activo',
          ),
          const SizedBox(height: 12),
          AureaEntrance(
            delay: const Duration(milliseconds: 140),
            child: _BudgetPulse(onOpenPlan: () => onOpenTab(2)),
          ),
          const SizedBox(height: 24),
          AureaSectionHeader(
            title: 'Flujo de caja',
            subtitle: 'Balance neto de los últimos 6 meses',
            actionLabel: 'Ver insights',
            onAction: () => onOpenTab(3),
          ),
          const SizedBox(height: 8),
          AureaEntrance(
            delay: const Duration(milliseconds: 210),
            child: _CashFlowChart(records: transactions.value ?? const []),
          ),
          const SizedBox(height: 20),
          const AureaSectionHeader(
            title: 'En qué se va tu dinero',
            subtitle: 'Distribución de gastos recientes',
          ),
          const SizedBox(height: 8),
          AureaEntrance(
            delay: const Duration(milliseconds: 240),
            child: _ExpenseBreakdown(
              records: transactions.value ?? const [],
              hideValues: hideValues,
            ),
          ),
          const SizedBox(height: 24),
          AureaSectionHeader(
            title: 'Movimientos recientes',
            subtitle: 'Lo último que pasó en tus cuentas',
            actionLabel: 'Ver todos',
            onAction: () => onOpenTab(1),
          ),
          const SizedBox(height: 8),
          AureaEntrance(
            delay: const Duration(milliseconds: 280),
            child: transactions.when(
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

class _CashFlowChart extends StatefulWidget {
  const _CashFlowChart({required this.records});

  final List<TransactionRecord> records;

  @override
  State<_CashFlowChart> createState() => _CashFlowChartState();
}

class _CashFlowChartState extends State<_CashFlowChart> {
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final months = List.generate(
      6,
      (index) => DateTime(now.year, now.month - 5 + index),
    );
    String key(DateTime date) => '${date.year}-${date.month}';
    final values = {for (final month in months) key(month): 0};
    final incomeValues = {for (final month in months) key(month): 0};
    final expenseValues = {for (final month in months) key(month): 0};
    for (final record in widget.records) {
      final monthKey = key(record.occurredAt);
      if (!values.containsKey(monthKey)) continue;
      final signed = switch (record.type) {
        TransactionType.income => record.amountMinor,
        TransactionType.expense => -record.amountMinor,
        _ => 0,
      };
      values[monthKey] = values[monthKey]! + signed;
      if (record.type == TransactionType.income) {
        incomeValues[monthKey] = incomeValues[monthKey]! + record.amountMinor;
      } else if (record.type == TransactionType.expense) {
        expenseValues[monthKey] = expenseValues[monthKey]! + record.amountMinor;
      }
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
    final selected = _touchedIndex == null
        ? null
        : monthly[_touchedIndex!.clamp(0, monthly.length - 1)];
    final selectedMonthIndex = _touchedIndex?.clamp(0, monthly.length - 1);
    final selectedIncome = selectedMonthIndex == null
        ? 0
        : incomeValues[key(months[selectedMonthIndex])];
    final selectedExpense = selectedMonthIndex == null
        ? 0
        : expenseValues[key(months[selectedMonthIndex])];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: selected == null
                  ? Text(
                      'Toca un mes para ver el detalle',
                      key: const ValueKey('cash-flow-hint'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : Column(
                      key: ValueKey(_touchedIndex),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          toBeginningOfSentenceCase(
                            DateFormat.yMMMM('es_PE')
                                .format(months[selectedMonthIndex!]),
                          ),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Ingresos ${Money(selectedIncome ?? 0).format()}  ·  '
                          'Gastos ${Money(selectedExpense ?? 0).format()}  ·  '
                          'Neto ${Money((selected * 100).round()).format()}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 220,
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
                  lineTouchData: LineTouchData(
                    handleBuiltInTouches: true,
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => spots
                          .map(
                            (spot) => LineTooltipItem(
                              '${DateFormat.MMM('es_PE').format(months[spot.x.round()])}\n'
                              '${Money((spot.y * 100).round()).format()} netos',
                              TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    touchCallback: (event, response) {
                      if (!event.isInterestedForInteractions ||
                          response?.lineBarSpots == null) {
                        return;
                      }
                      setState(
                        () => _touchedIndex = response!.lineBarSpots!.first.x
                            .round(),
                      );
                    },
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
          ],
        ),
      ),
    );
  }
}

class _ExpenseBreakdown extends StatelessWidget {
  const _ExpenseBreakdown({required this.records, required this.hideValues});

  final List<TransactionRecord> records;
  final bool hideValues;

  @override
  Widget build(BuildContext context) {
    final totals = <String, int>{};
    for (final record in records) {
      if (record.type != TransactionType.expense) continue;
      final category = record.categoryId ?? 'other';
      totals[category] = (totals[category] ?? 0) + record.amountMinor;
    }
    if (totals.isEmpty) {
      return const Card(
        child: ListTile(
          leading: AureaIconBadge(icon: Icons.donut_large_rounded),
          title: Text('Aún no hay gastos para analizar'),
          subtitle: Text('Registra un gasto y verás su distribución aquí.'),
        ),
      );
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = sorted.fold<int>(0, (sum, item) => sum + item.value);
    final colors = [
      AureaColors.indigo,
      AureaColors.teal,
      AureaColors.warning,
      AureaColors.negative,
      AureaColors.violet,
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            SizedBox(
              width: 142,
              height: 142,
              child: PieChart(
                PieChartData(
                  centerSpaceRadius: 34,
                  sectionsSpace: 3,
                  sections: sorted.take(5).toList().asMap().entries.map((
                    entry,
                  ) {
                    final item = entry.value;
                    return PieChartSectionData(
                      value: item.value.toDouble(),
                      color: colors[entry.key % colors.length],
                      radius: 28,
                      title: '${(item.value / total * 100).round()}%',
                      titleStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: sorted.take(5).toList().asMap().entries.map((entry) {
                  final item = entry.value;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 5,
                          backgroundColor: colors[entry.key % colors.length],
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_categoryLabel(item.key))),
                        Text(
                          Money(item.value).format(hidden: hideValues),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
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
      onTap: () => showTransactionReceipt(
        context,
        record: record,
        hideValues: hideValues,
      ),
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
    final budgetsAsync = ref.watch(budgetsProvider);
    final goalsAsync = ref.watch(goalsProvider);
    final recurringAsync = ref.watch(recurringProvider);
    if (budgetsAsync.isLoading ||
        goalsAsync.isLoading ||
        recurringAsync.isLoading) {
      return const _PlanSkeleton();
    }
    final budgets = budgetsAsync.value ?? const [];
    final goals = goalsAsync.value ?? const [];
    final recurring = recurringAsync.value ?? const [];
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
                    '${Money(budget.spentMinor, currencyCode: budget.currencyCode).format()} de '
                    '${Money(budget.limitMinor, currencyCode: budget.currencyCode).format()}',
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
                    '${Money(goal.savedAmountMinor, currencyCode: goal.currencyCode).format()} de '
                    '${Money(goal.targetAmountMinor, currencyCode: goal.currencyCode).format()}',
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
              : recurring
                    .take(2)
                    .map(
                      (item) =>
                          '${item.name} · ${DateFormat.yMd('es_PE').format(item.nextRunAt)}',
                    )
                    .join(' · '),
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
  DateTime _nextRunAt = DateTime.now().add(const Duration(days: 1));
  String _frequency = 'monthly';
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
          if (_kind == _PlanKind.recurring) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _frequency,
              decoration: const InputDecoration(
                labelText: 'Frecuencia',
                prefixIcon: Icon(Icons.repeat_rounded),
              ),
              items: const [
                DropdownMenuItem(value: 'weekly', child: Text('Semanal')),
                DropdownMenuItem(value: 'monthly', child: Text('Mensual')),
                DropdownMenuItem(value: 'yearly', child: Text('Anual')),
              ],
              onChanged: (value) =>
                  setState(() => _frequency = value ?? 'monthly'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickNextRunDate,
              icon: const Icon(Icons.event_outlined),
              label: Text(
                'Primera fecha: ${DateFormat.yMMMMd('es_PE').format(_nextRunAt)}',
              ),
            ),
          ],
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
            nextRunAt: _nextRunAt,
            frequency: _frequency,
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

  Future<void> _pickNextRunDate() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: _nextRunAt,
      helpText: 'Elige cuándo se registrará por primera vez',
    );
    if (!mounted || date == null) return;
    setState(() {
      _nextRunAt = DateTime(
        date.year,
        date.month,
        date.day,
        _nextRunAt.hour,
        _nextRunAt.minute,
      );
    });
  }
}

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key, required this.hideValues});
  final bool hideValues;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(dashboardSummaryProvider);
    if (summaryAsync.isLoading) return const _InsightsSkeleton();
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
  const ProfileScreen({super.key, required this.onShowTutorial});

  final VoidCallback onShowTutorial;
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
          onPressed: onShowTutorial,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('Ver tutorial de Aurea'),
        ),
        const SizedBox(height: 10),
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const AureaSkeleton(height: 52, radius: 18),
      const SizedBox(height: 12),
      const Row(
        children: [
          AureaSkeleton(width: 68, height: 34, radius: 99),
          SizedBox(width: 8),
          AureaSkeleton(width: 68, height: 34, radius: 99),
          SizedBox(width: 8),
          AureaSkeleton(width: 68, height: 34, radius: 99),
        ],
      ),
      const SizedBox(height: 16),
      Card(
        child: Column(
          children: List.generate(
            4,
            (index) => const _TransactionSkeletonRow(),
          ),
        ),
      ),
    ],
  );
}

class _HomeShellSkeleton extends StatelessWidget {
  const _HomeShellSkeleton();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 14),
            child: Row(
              children: [
                AureaSkeleton(width: 104, height: 30, radius: 12),
                Spacer(),
                AureaSkeleton(width: 36, height: 36, radius: 99),
                SizedBox(width: 8),
                AureaSkeleton(width: 36, height: 36, radius: 99),
              ],
            ),
          ),
          const Expanded(child: _DashboardSkeleton()),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                AureaSkeleton(width: 42, height: 38, radius: 12),
                AureaSkeleton(width: 42, height: 38, radius: 12),
                AureaSkeleton(width: 42, height: 38, radius: 12),
                AureaSkeleton(width: 42, height: 38, radius: 12),
                AureaSkeleton(width: 42, height: 38, radius: 12),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 160),
    children: const [
      AureaSkeleton(width: 155, height: 18),
      SizedBox(height: 16),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: AureaSkeleton(width: 180, height: 30)),
          AureaSkeleton(width: 42, height: 42, radius: 14),
        ],
      ),
      SizedBox(height: 18),
      AureaSkeleton(height: 188, radius: 24),
      SizedBox(height: 14),
      Row(
        children: [
          Expanded(child: AureaSkeleton(height: 82, radius: 16)),
          SizedBox(width: 10),
          Expanded(child: AureaSkeleton(height: 82, radius: 16)),
          SizedBox(width: 10),
          Expanded(child: AureaSkeleton(height: 82, radius: 16)),
        ],
      ),
      SizedBox(height: 24),
      AureaSkeleton(width: 160, height: 20),
      SizedBox(height: 12),
      AureaSkeleton(height: 78, radius: 18),
      SizedBox(height: 24),
      AureaSkeleton(width: 150, height: 20),
      SizedBox(height: 10),
      AureaSkeleton(height: 220, radius: 18),
      SizedBox(height: 20),
      AureaSkeleton(width: 190, height: 20),
      SizedBox(height: 10),
      AureaSkeleton(height: 190, radius: 18),
      SizedBox(height: 20),
      AureaSkeleton(width: 190, height: 20),
      SizedBox(height: 10),
      _TransactionListSkeleton(),
    ],
  );
}

class _PlanSkeleton extends StatelessWidget {
  const _PlanSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 160),
    children: const [
      Row(
        children: [
          Expanded(child: AureaSkeleton(width: 210, height: 30)),
          AureaSkeleton(width: 42, height: 42, radius: 14),
        ],
      ),
      SizedBox(height: 12),
      AureaSkeleton(height: 150, radius: 20),
      SizedBox(height: 12),
      _PlanSkeletonCard(),
      SizedBox(height: 12),
      _PlanSkeletonCard(),
      SizedBox(height: 12),
      _PlanSkeletonCard(showProgress: false),
    ],
  );
}

class _InsightsSkeleton extends StatelessWidget {
  const _InsightsSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 160),
    children: const [
      AureaSkeleton(width: 190, height: 30),
      SizedBox(height: 6),
      AureaSkeleton(width: 285, height: 16),
      SizedBox(height: 18),
      AureaSkeleton(height: 170, radius: 24),
      SizedBox(height: 14),
      Row(
        children: [
          Expanded(child: _InsightMetricSkeleton()),
          SizedBox(width: 12),
          Expanded(child: _InsightMetricSkeleton()),
        ],
      ),
      SizedBox(height: 22),
      AureaSkeleton(width: 130, height: 22),
      SizedBox(height: 14),
      AureaSkeleton(height: 118, radius: 18),
      SizedBox(height: 14),
      AureaSkeleton(height: 96, radius: 18),
    ],
  );
}

class _TransactionSkeletonRow extends StatelessWidget {
  const _TransactionSkeletonRow();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      children: [
        AureaSkeleton(width: 44, height: 44, radius: 99),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AureaSkeleton(width: 150, height: 14),
              SizedBox(height: 8),
              AureaSkeleton(width: 105, height: 11),
            ],
          ),
        ),
        SizedBox(width: 12),
        AureaSkeleton(width: 72, height: 16),
      ],
    ),
  );
}

class _TransactionListSkeleton extends StatelessWidget {
  const _TransactionListSkeleton();

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      children: List.generate(4, (index) => const _TransactionSkeletonRow()),
    ),
  );
}

class _PlanSkeletonCard extends StatelessWidget {
  const _PlanSkeletonCard({this.showProgress = true});

  final bool showProgress;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              AureaSkeleton(width: 44, height: 44, radius: 15),
              SizedBox(width: 12),
              Expanded(child: AureaSkeleton(width: 160, height: 18)),
            ],
          ),
          const SizedBox(height: 16),
          if (showProgress) ...[
            const AureaSkeleton(height: 8, radius: 99),
            const SizedBox(height: 12),
          ],
          const AureaSkeleton(width: 220, height: 14),
        ],
      ),
    ),
  );
}

class _InsightMetricSkeleton extends StatelessWidget {
  const _InsightMetricSkeleton();

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          AureaSkeleton(width: 28, height: 28, radius: 9),
          SizedBox(height: 12),
          AureaSkeleton(width: 60, height: 14),
          SizedBox(height: 7),
          AureaSkeleton(width: 92, height: 18),
        ],
      ),
    ),
  );
}

class AureaTutorialTargets {
  const AureaTutorialTargets({
    required this.balance,
    required this.quickActions,
    required this.transactionsTab,
    required this.planTab,
    required this.insightsTab,
    required this.profileTab,
    required this.quickAdd,
  });

  final GlobalKey balance;
  final GlobalKey quickActions;
  final GlobalKey transactionsTab;
  final GlobalKey planTab;
  final GlobalKey insightsTab;
  final GlobalKey profileTab;
  final GlobalKey quickAdd;
}

Future<void> showAureaTutorial(
  BuildContext context, {
  required AureaTutorialTargets targets,
  ValueChanged<int>? onTabChanged,
}) async {
  // The tutorial always starts from Inicio, including when launched from Perfil.
  onTabChanged?.call(0);
  final overlay = Overlay.of(context, rootOverlay: true);
  await WidgetsBinding.instance.endOfFrame;
  final completer = Completer<void>();
  final entry = OverlayEntry(
    builder: (_) => _SpotlightTutorial(
      targets: targets,
      onTabChanged: onTabChanged,
      onFinished: completer.complete,
    ),
  );
  overlay.insert(entry);
  await completer.future;
  entry.remove();
}

class _SpotlightTutorial extends StatefulWidget {
  const _SpotlightTutorial({
    required this.targets,
    required this.onFinished,
    this.onTabChanged,
  });

  final AureaTutorialTargets targets;
  final ValueChanged<int>? onTabChanged;
  final VoidCallback onFinished;

  @override
  State<_SpotlightTutorial> createState() => _SpotlightTutorialState();
}

class _SpotlightTutorialState extends State<_SpotlightTutorial>
    with SingleTickerProviderStateMixin {
  int _step = 0;
  Rect? _targetRect;
  Rect? _previousTargetRect;
  late final AnimationController _transition;

  @override
  void initState() {
    super.initState();
    _transition =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 360),
          )
          ..value = 1
          ..addListener(_animate);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await WidgetsBinding.instance.endOfFrame;
      _refreshTarget();
    });
  }

  @override
  void dispose() {
    _transition.dispose();
    super.dispose();
  }

  void _animate() {
    if (mounted) setState(() {});
  }

  static const _steps = [
    (
      key: 'balance',
      title: 'Tu balance',
      message: 'Aquí ves cuánto dinero tienes disponible y el resumen del mes.',
      tab: 0,
    ),
    (
      key: 'quickActions',
      title: 'Acciones rápidas',
      message: 'Registra un gasto, un ingreso o mueve dinero desde aquí.',
      tab: 0,
    ),
    (
      key: 'quickAdd',
      title: 'Registrar movimiento',
      message: 'Este botón está siempre disponible para guardar un movimiento.',
      tab: 0,
    ),
    (
      key: 'transactionsTab',
      title: 'Movimientos',
      message: 'Consulta, busca y filtra todos tus gastos, ingresos y transferencias.',
      tab: 1,
    ),
    (
      key: 'planTab',
      title: 'Plan',
      message:
          'Crea presupuestos, metas y recurrentes para organizar tu dinero.',
      tab: 2,
    ),
    (
      key: 'insightsTab',
      title: 'Insights',
      message: 'Revisa tus patrones de ingresos, gastos y ahorro.',
      tab: 3,
    ),
    (
      key: 'profileTab',
      title: 'Tu perfil',
      message:
          'Desde Perfil puedes configurar la app y volver a ver este tutorial.',
      tab: 4,
    ),
  ];

  GlobalKey get _currentKey => switch (_steps[_step].key) {
    'balance' => widget.targets.balance,
    'quickActions' => widget.targets.quickActions,
    'transactionsTab' => widget.targets.transactionsTab,
    'planTab' => widget.targets.planTab,
    'insightsTab' => widget.targets.insightsTab,
    'profileTab' => widget.targets.profileTab,
    _ => widget.targets.quickAdd,
  };

  void _refreshTarget([int attempt = 0]) {
    final context = _currentKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      if (attempt < 4 && mounted) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _refreshTarget(attempt + 1),
        );
      }
      return;
    }
    final origin = renderObject.localToGlobal(Offset.zero);
    final nextRect = origin & renderObject.size;
    if (!mounted) return;
    setState(() {
      _previousTargetRect = _targetRect;
      _targetRect = nextRect;
    });
    _transition.forward(from: 0);
  }

  void _next() {
    if (_step == _steps.length - 1) {
      _finish();
      return;
    }
    final nextStep = _step + 1;
    final tab = _steps[nextStep].tab;
    if (tab != _steps[_step].tab) {
      widget.onTabChanged?.call(tab);
    }
    setState(() {
      _step = nextStep;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await WidgetsBinding.instance.endOfFrame;
      _refreshTarget();
    });
  }

  Future<void> _finish() async {
    await AppPreferences().completeAppTutorial();
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final fallback = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: 120,
      height: 80,
    );
    final target = _targetRect ?? fallback;
    final animatedTarget = _previousTargetRect == null
        ? target
        : Rect.lerp(
                _previousTargetRect,
                target,
                Curves.easeOutCubic.transform(_transition.value),
              ) ??
              target;
    final cardTop = animatedTarget.center.dy < size.height * .52
        ? animatedTarget.bottom + 22
        : null;
    final cardBottom = cardTop == null
        ? size.height - animatedTarget.top + 22
        : null;
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _SpotlightPainter(animatedTarget)),
          ),
          Positioned.fromRect(
            rect: animatedTarget.inflate(10),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _next,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            top: cardTop,
            bottom: cardBottom,
            child: Align(
              alignment: cardTop != null
                  ? Alignment.topCenter
                  : Alignment.bottomCenter,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, .04),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: _SpotlightCard(
                  key: ValueKey(_step),
                  step: _step + 1,
                  total: _steps.length,
                  title: _steps[_step].title,
                  message: _steps[_step].message,
                  onNext: _next,
                  onSkip: _finish,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotlightCard extends StatelessWidget {
  const _SpotlightCard({
    super.key,
    required this.step,
    required this.total,
    required this.title,
    required this.message,
    required this.onNext,
    required this.onSkip,
  });

  final int step;
  final int total;
  final String title;
  final String message;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 12,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PASO $step DE $total',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 5),
          Text(message),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(onPressed: onSkip, child: const Text('Omitir')),
              const Spacer(),
              FilledButton(
                onPressed: onNext,
                child: Text(step == total ? 'Listo' : 'Siguiente'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter(this.target);

  final Rect target;

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    final hole = RRect.fromRectAndRadius(
      target.inflate(10),
      const Radius.circular(18),
    );
    overlay.addRRect(hole);
    canvas.drawPath(
      overlay,
      Paint()
        ..color = Colors.black.withValues(alpha: .78)
        ..blendMode = BlendMode.srcOver,
    );
    canvas.drawRRect(
      hole,
      Paint()
        ..color = Colors.white.withValues(alpha: .95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) =>
      oldDelegate.target != target;
}

class _AureaTutorialPage extends StatefulWidget {
  const _AureaTutorialPage();

  @override
  State<_AureaTutorialPage> createState() => _AureaTutorialPageState();
}

class _AureaTutorialPageState extends State<_AureaTutorialPage> {
  final _controller = PageController();
  int _page = 0;

  static const _items = [
    (
      Icons.space_dashboard_outlined,
      'Tu panorama, de un vistazo',
      'Inicio reúne tu saldo, flujo de caja y movimientos recientes para que sepas dónde estás.',
    ),
    (
      Icons.swap_horiz_rounded,
      'Registra cada movimiento',
      'Usa Movimiento para agregar gastos, ingresos o transferencias sin salir de la pantalla.',
    ),
    (
      Icons.flag_outlined,
      'Convierte tus planes en progreso',
      'En Plan puedes crear presupuestos, metas y recurrentes con fechas claras.',
    ),
    (
      Icons.insights_outlined,
      'Toma mejores decisiones',
      'Insights resume tus ingresos, gastos y ahorro para ayudarte a elegir tu próximo paso.',
    ),
  ];

  Future<void> _finish() async {
    await AppPreferences().completeAppTutorial();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const AureaBrandLockup(compact: true),
      actions: [
        TextButton(onPressed: _finish, child: const Text('Omitir')),
        const SizedBox(width: 8),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: _items.length,
              onPageChanged: (value) => setState(() => _page = value),
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 360),
                      transitionBuilder: (child, animation) =>
                          ScaleTransition(scale: animation, child: child),
                      child: AureaIconBadge(
                        key: ValueKey(_items[index].$1),
                        icon: _items[index].$1,
                        size: 112,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'PASO ${index + 1} DE ${_items.length}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _items[index].$2,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displaySmall
                          ?.copyWith(fontWeight: FontWeight.w900, height: 1.05),
                    ),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 500),
                      child: Text(
                        _items[index].$3,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _items.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: index == _page ? 30 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: index == _page
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      if (_page == _items.length - 1) {
                        _finish();
                      } else {
                        _controller.nextPage(
                          duration: const Duration(milliseconds: 360),
                          curve: Curves.easeOutCubic,
                        );
                      }
                    },
                    child: Text(
                      _page == _items.length - 1
                          ? 'Empezar con Aurea'
                          : 'Continuar',
                    ),
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

class OfflineScreen extends StatelessWidget {
  const OfflineScreen({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: AureaPageBackground(
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AureaIconBadge(
                    icon: Icons.wifi_off_rounded,
                    size: 82,
                    color: AureaColors.indigo,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'No hay conexión a Internet',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Aurea necesita conexión para sincronizar tus cuentas y movimientos. '
                    'Revisa tu Wi-Fi o datos móviles y vuelve a intentarlo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Comprobar conexión'),
                  ),
                ],
              ),
            ),
          ),
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

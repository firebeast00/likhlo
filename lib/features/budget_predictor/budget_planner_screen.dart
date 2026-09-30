import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/budget_provider.dart';
import '../../providers/settings_provider.dart';
import 'budget_prediction_models.dart';
import 'budget_predictor_provider.dart';

class BudgetPlannerScreen extends ConsumerStatefulWidget {
  const BudgetPlannerScreen({super.key});

  @override
  ConsumerState<BudgetPlannerScreen> createState() =>
      _BudgetPlannerScreenState();
}

class _BudgetPlannerScreenState extends ConsumerState<BudgetPlannerScreen> {
  DateTime _targetMonth =
      DateTime(DateTime.now().year, DateTime.now().month, 1);
  final Set<String> _selectedIds = {};
  final TextEditingController _bufferController = TextEditingController();
  String? _initializedMonthKey;
  bool _saving = false;

  @override
  void dispose() {
    _bufferController.dispose();
    super.dispose();
  }

  void _initializePlan(MonthlySmartPlan plan) {
    final key = DateFormat('yyyy-MM').format(plan.draft.targetMonth);
    if (_initializedMonthKey == key) return;
    _initializedMonthKey = key;
    _selectedIds
      ..clear()
      ..addAll(
        plan.draft.suggestions
            .where((item) => item.selectedByDefault)
            .map((item) => item.id),
      );
    _bufferController.text = plan.draft.surpriseBuffer.toStringAsFixed(0);
  }

  void _changeMonth(int delta) {
    FocusScope.of(context).unfocus();
    setState(() {
      _targetMonth = DateTime(
        _targetMonth.year,
        _targetMonth.month + delta,
        1,
      );
      _initializedMonthKey = null;
    });
  }

  double _bufferAmount() {
    final value = double.tryParse(_bufferController.text.trim());
    if (value == null || !value.isFinite || value < 0) return 0;
    return value;
  }

  double _selectedExpectedTotal(MonthlySmartPlan plan) {
    return plan.expectedItems
        .where((item) => _selectedIds.contains(item.suggestion.id))
        .fold<double>(0, (sum, item) => sum + item.suggestion.amount);
  }

  Future<void> _saveBudget(MonthlySmartPlan plan) async {
    if (_saving) return;
    final total = _selectedExpectedTotal(plan) + _bufferAmount();
    if (!total.isFinite || total < 0) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(budgetProvider.notifier)
          .setBudget(total, plan.draft.targetMonth);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              'Budget for ${DateFormat('MMMM yyyy').format(plan.draft.targetMonth)} saved: Rs. ${total.toStringAsFixed(0)}',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(monthlySmartPlanProvider(_targetMonth));
    final existingBudget = ref.watch(budgetProvider)[
        DateFormat('yyyy-MM').format(_targetMonth)];
    final primaryColor =
        Color(ref.watch(settingsProvider).profileColorValue);
    _initializePlan(plan);

    final selectedExpected = _selectedExpectedTotal(plan);
    final buffer = _bufferAmount();
    final suggestedBudget = selectedExpected + buffer;
    final allowance = plan.allowanceContext;
    final safeMargin =
        allowance > 0 ? allowance - suggestedBudget : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
      children: [
        _MonthHeader(
          month: plan.draft.targetMonth,
          sourceMonth: plan.draft.sourceMonth,
          handled: plan.handledCount,
          total: plan.expectedItems.length,
          onPrevious: () => _changeMonth(-1),
          onNext: () => _changeMonth(1),
        ),
        const SizedBox(height: 16),
        _SectionHeader(
          title: 'Expected this month',
          subtitle: plan.expectedItems.isEmpty
              ? 'No reliable recurring items yet.'
              : 'Likhlo matches these automatically as you log expenses.',
        ),
        const SizedBox(height: 8),
        if (plan.expectedItems.isEmpty)
          const _EmptyCard(
            icon: Icons.event_note_outlined,
            text:
                'Keep logging expenses. Regular bills and habits will appear here when a pattern becomes clear.',
          )
        else
          ...plan.expectedItems.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ExpectedItemCard(
                item: item,
                included: _selectedIds.contains(item.suggestion.id),
                color: primaryColor,
                onIncludedChanged: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedIds.add(item.suggestion.id);
                    } else {
                      _selectedIds.remove(item.suggestion.id);
                    }
                  });
                },
              ),
            ),
          ),
        const SizedBox(height: 16),
        _SectionHeader(
          title: 'New / unplanned this month',
          subtitle:
              'These were not part of this month’s expected plan.',
        ),
        const SizedBox(height: 8),
        if (plan.newExpenses.isEmpty)
          const _EmptyCard(
            icon: Icons.check_circle_outline_rounded,
            text: 'No new unplanned expense has appeared yet.',
          )
        else
          ...plan.newExpenses.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _NewExpenseCard(
                item: item,
                color: primaryColor,
                onRememberChanged: (remembered) {
                  ref
                      .read(monthlyPlanMemoryProvider.notifier)
                      .setRemembered(item.id, remembered);
                },
              ),
            ),
          ),
        const SizedBox(height: 18),
        _SafetyBufferCard(
          controller: _bufferController,
          suggestedAmount: plan.draft.surpriseBuffer,
          historyMonths: plan.draft.surpriseHistoryMonths,
          color: primaryColor,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 18),
        _MonthlyOverviewCard(
          allowance: allowance,
          expectedPlan: selectedExpected,
          spentSoFar: plan.currentMonthSpent,
          unplanned: plan.newExpenseTotal,
          safeMargin: safeMargin,
          existingBudget: existingBudget,
          color: primaryColor,
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _saving ? null : () => _saveBudget(plan),
            style: FilledButton.styleFrom(
              backgroundColor: primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.save_outlined),
            label: Text(
              _saving
                  ? 'Saving…'
                  : 'Save monthly budget · Rs. ${suggestedBudget.toStringAsFixed(0)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}

class _MonthHeader extends StatelessWidget {
  final DateTime month;
  final DateTime sourceMonth;
  final int handled;
  final int total;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const _MonthHeader({
    required this.month,
    required this.sourceMonth,
    required this.handled,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final progressText = total == 0
        ? 'Learning from your spending history'
        : '$handled of $total expected items handled';

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Previous month',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    'Monthly Smart Plan',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('MMMM yyyy').format(month),
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    progressText,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Based on ${DateFormat('MMMM').format(sourceMonth)} and recent patterns',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ExpectedItemCard extends StatelessWidget {
  final MonthlyPlanItem item;
  final bool included;
  final Color color;
  final ValueChanged<bool> onIncludedChanged;

  const _ExpectedItemCard({
    required this.item,
    required this.included,
    required this.color,
    required this.onIncludedChanged,
  });

  @override
  Widget build(BuildContext context) {
    final suggestion = item.suggestion;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tooltip(
              message: 'Include in monthly budget',
              child: Checkbox(
                value: included,
                activeColor: color,
                onChanged: (value) =>
                    onIncludedChanged(value ?? false),
              ),
            ),
            const SizedBox(width: 2),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Icon(_statusIcon(item.status), size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _statusText(item.status),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.status == MonthlyPlanItemStatus.upcoming
                        ? suggestion.reason
                        : _actualDetail(item),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '~Rs. ${suggestion.amount.toStringAsFixed(0)}',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusText(MonthlyPlanItemStatus status) {
    switch (status) {
      case MonthlyPlanItemStatus.upcoming:
        return 'Upcoming';
      case MonthlyPlanItemStatus.inProgress:
        return 'In progress';
      case MonthlyPlanItemStatus.handled:
        return 'Handled this month';
    }
  }

  IconData _statusIcon(MonthlyPlanItemStatus status) {
    switch (status) {
      case MonthlyPlanItemStatus.upcoming:
        return Icons.radio_button_unchecked_rounded;
      case MonthlyPlanItemStatus.inProgress:
        return Icons.timelapse_rounded;
      case MonthlyPlanItemStatus.handled:
        return Icons.check_circle_rounded;
    }
  }

  String _actualDetail(MonthlyPlanItem item) {
    final logs = item.actualFrequency == 1
        ? '1 log'
        : '${item.actualFrequency} logs';
    return '$logs · Rs. ${item.actualAmount.toStringAsFixed(0)} so far';
  }
}

class _NewExpenseCard extends StatelessWidget {
  final MonthlyNewExpense item;
  final Color color;
  final ValueChanged<bool> onRememberChanged;

  const _NewExpenseCard({
    required this.item,
    required this.color,
    required this.onRememberChanged,
  });

  @override
  Widget build(BuildContext context) {
    final logs =
        item.frequency == 1 ? '1 log' : '${item.frequency} logs';

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.new_releases_outlined, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${item.category} · $logs',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  'Rs. ${item.amount.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () =>
                    onRememberChanged(!item.rememberedForFuture),
                icon: Icon(
                  item.rememberedForFuture
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_add_outlined,
                  size: 18,
                ),
                label: Text(
                  item.rememberedForFuture
                      ? 'Remembered for next month'
                      : 'Remember next month',
                ),
                style: TextButton.styleFrom(
                  foregroundColor: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SafetyBufferCard extends StatelessWidget {
  final TextEditingController controller;
  final double suggestedAmount;
  final int historyMonths;
  final Color color;
  final VoidCallback onChanged;

  const _SafetyBufferCard({
    required this.controller,
    required this.suggestedAmount,
    required this.historyMonths,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: ExpansionTile(
        leading: const Icon(Icons.shield_outlined),
        title: const Text(
          'Safety buffer',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          suggestedAmount > 0
              ? 'Optional room for unexpected expenses'
              : 'Add a small reserve if you want one',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(
            suggestedAmount > 0
                ? 'Likhlo estimated this from unplanned spending in $historyMonths recent month${historyMonths == 1 ? '' : 's'}.'
                : 'There is not enough surprise-spending history yet.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                RegExp(r'^\d*\.?\d{0,2}'),
              ),
            ],
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              labelText: 'Safety buffer',
              prefixText: 'Rs. ',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: color, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyOverviewCard extends StatelessWidget {
  final double allowance;
  final double expectedPlan;
  final double spentSoFar;
  final double unplanned;
  final double? safeMargin;
  final double? existingBudget;
  final Color color;

  const _MonthlyOverviewCard({
    required this.allowance,
    required this.expectedPlan,
    required this.spentSoFar,
    required this.unplanned,
    required this.safeMargin,
    required this.existingBudget,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Monthly overview',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          if (allowance > 0) _line('Allowance / income context', allowance),
          if (allowance > 0) const SizedBox(height: 7),
          _line('Expected plan', expectedPlan),
          const SizedBox(height: 7),
          _line('Spent so far', spentSoFar),
          if (unplanned > 0) ...[
            const SizedBox(height: 7),
            _line('New / unplanned', unplanned),
          ],
          if (safeMargin != null) ...[
            const Divider(height: 22),
            _line('Safe margin after plan', safeMargin!, bold: true),
          ],
          if (existingBudget != null) ...[
            const SizedBox(height: 7),
            _line('Current saved budget', existingBudget!),
          ],
        ],
      ),
    );
  }

  Widget _line(String label, double amount, {bool bold = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ),
        Text(
          'Rs. ${amount.toStringAsFixed(0)}',
          style: TextStyle(
            fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String text;

  const _EmptyCard({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

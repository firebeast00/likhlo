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
  DateTime _targetMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  final Set<String> _selectedIds = {};
  final TextEditingController _bufferController = TextEditingController();
  String? _initializedMonthKey;
  bool _saving = false;

  @override
  void dispose() {
    _bufferController.dispose();
    super.dispose();
  }

  void _initializeDraft(BudgetDraft draft) {
    final key = DateFormat('yyyy-MM').format(draft.targetMonth);
    if (_initializedMonthKey == key) return;
    _initializedMonthKey = key;
    _selectedIds
      ..clear()
      ..addAll(
        draft.suggestions
            .where((item) => item.selectedByDefault)
            .map((item) => item.id),
      );
    _bufferController.text = draft.surpriseBuffer.toStringAsFixed(0);
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

  double _selectedTotal(BudgetDraft draft) {
    final suggestions = draft.suggestions
        .where((item) => _selectedIds.contains(item.id));
    return suggestions.fold<double>(0, (sum, item) => sum + item.amount);
  }

  Future<void> _saveBudget(BudgetDraft draft) async {
    if (_saving) return;
    final total = _selectedTotal(draft) + _bufferAmount();
    if (!total.isFinite || total < 0) return;

    setState(() => _saving = true);
    try {
      await ref.read(budgetProvider.notifier).setBudget(total, draft.targetMonth);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              'Budget for ${DateFormat('MMMM yyyy').format(draft.targetMonth)} saved: Rs. ${total.toStringAsFixed(0)}',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(budgetDraftProvider(_targetMonth));
    final existingBudget = ref
        .watch(budgetProvider)
        [DateFormat('yyyy-MM').format(_targetMonth)];
    final primaryColor = Color(ref.watch(settingsProvider).profileColorValue);
    _initializeDraft(draft);

    final selectedTotal = _selectedTotal(draft);
    final buffer = _bufferAmount();
    final suggestedTotal = selectedTotal + buffer;
    final remainingFromAllowance = draft.previousMonthIncome > 0
        ? draft.previousMonthIncome - suggestedTotal
        : null;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Budget Planner',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
        children: [
          _MonthHeader(
            month: draft.targetMonth,
            sourceMonth: draft.sourceMonth,
            onPrevious: () => _changeMonth(-1),
            onNext: () => _changeMonth(1),
          ),
          const SizedBox(height: 14),
          if (existingBudget != null)
            _InfoCard(
              icon: Icons.flag_outlined,
              title: 'Current saved budget',
              message: 'Rs. ${existingBudget.toStringAsFixed(0)}',
              color: primaryColor,
            ),
          if (existingBudget != null) const SizedBox(height: 12),
          if (draft.fixedObligations.isNotEmpty)
            _SuggestionSection(
              title: 'Upcoming Bills & Fees',
              subtitle: 'Likely fixed obligations from last month',
              items: draft.fixedObligations,
              selectedIds: _selectedIds,
              color: primaryColor,
              onChanged: (id, selected) {
                setState(() {
                  selected ? _selectedIds.add(id) : _selectedIds.remove(id);
                });
              },
            ),
          if (draft.fixedObligations.isNotEmpty) const SizedBox(height: 14),
          if (draft.routineHabits.isNotEmpty)
            _SuggestionSection(
              title: 'Routine Habits',
              subtitle:
                  'Frequent spending from ${DateFormat('MMMM').format(draft.sourceMonth)}',
              items: draft.routineHabits,
              selectedIds: _selectedIds,
              color: primaryColor,
              onChanged: (id, selected) {
                setState(() {
                  selected ? _selectedIds.add(id) : _selectedIds.remove(id);
                });
              },
            ),
          const SizedBox(height: 14),
          _SurpriseBufferCard(
            controller: _bufferController,
            suggestedAmount: draft.surpriseBuffer,
            historyMonths: draft.surpriseHistoryMonths,
            color: primaryColor,
            onChanged: () => setState(() {}),
          ),
          if (draft.fixedObligations.isEmpty &&
              draft.routineHabits.isEmpty) ...[
            const SizedBox(height: 14),
            _InfoCard(
              icon: Icons.history_rounded,
              title: 'Not enough repeat history yet',
              message:
                  'Keep logging expenses. Likhlo will suggest bills and habits when a clear pattern appears.',
              color: primaryColor,
            ),
          ],
          const SizedBox(height: 18),
          _SummaryCard(
            selectedExpenses: selectedTotal,
            surpriseBuffer: buffer,
            total: suggestedTotal,
            previousIncome: draft.previousMonthIncome,
            remainingFromAllowance: remainingFromAllowance,
            color: primaryColor,
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: _saving ? null : () => _saveBudget(draft),
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              icon: const Icon(Icons.check_rounded),
              label: Text(
                _saving
                    ? 'Saving…'
                    : 'Save Budget: Rs. ${suggestedTotal.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  final DateTime month;
  final DateTime sourceMonth;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const _MonthHeader({
    required this.month,
    required this.sourceMonth,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                    DateFormat('MMMM yyyy').format(month),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Smart draft based on ${DateFormat('MMMM').format(sourceMonth)} history',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
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

class _SuggestionSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<BudgetSuggestion> items;
  final Set<String> selectedIds;
  final Color color;
  final void Function(String id, bool selected) onChanged;

  const _SuggestionSection({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.selectedIds,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ),
            const SizedBox(height: 8),
            ...items.map(
              (item) => CheckboxListTile(
                value: selectedIds.contains(item.id),
                activeColor: color,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                onChanged: (value) => onChanged(item.id, value ?? false),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      'Rs. ${item.amount.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                subtitle: Text(
                  item.reason,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SurpriseBufferCard extends StatelessWidget {
  final TextEditingController controller;
  final double suggestedAmount;
  final int historyMonths;
  final Color color;
  final VoidCallback onChanged;

  const _SurpriseBufferCard({
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.shield_outlined, size: 20),
                SizedBox(width: 8),
                Text(
                  'Surprise Expense Buffer',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              suggestedAmount > 0
                  ? 'Estimated from unplanned non-shopping expenses across the last ${historyMonths} months.'
                  : 'No reliable surprise-spending pattern yet. You can still add your own safety buffer.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                labelText: 'Buffer amount',
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
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final double selectedExpenses;
  final double surpriseBuffer;
  final double total;
  final double previousIncome;
  final double? remainingFromAllowance;
  final Color color;

  const _SummaryCard({
    required this.selectedExpenses,
    required this.surpriseBuffer,
    required this.total,
    required this.previousIncome,
    required this.remainingFromAllowance,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Column(
        children: [
          _row('Selected expenses', selectedExpenses),
          const SizedBox(height: 8),
          _row('Surprise buffer', surpriseBuffer),
          const Divider(height: 22),
          _row('Suggested budget', total, bold: true),
          if (previousIncome > 0) ...[
            const SizedBox(height: 12),
            _row('Last month income / allowance', previousIncome),
            if (remainingFromAllowance != null) ...[
              const SizedBox(height: 6),
              _row(
                'Margin after this plan',
                remainingFromAllowance!,
                bold: true,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _row(String label, double amount, {bool bold = false}) {
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

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Color color;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

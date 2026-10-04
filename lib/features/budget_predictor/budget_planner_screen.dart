import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/budget_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/speech_recognition_provider.dart';
import '../../widgets/month_selector_control.dart';
import 'budget_coach_engine.dart';
import 'budget_intent_parser.dart';
import 'budget_plan_preferences.dart';
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
  final TextEditingController _commandController = TextEditingController();

  SpeechRecognitionProvider? _speech;
  bool _isListening = false;
  bool _processingCommand = false;
  bool _saving = false;
  String? _assistantMessage;

  @override
  void dispose() {
    _commandController.dispose();
    final speech = _speech;
    if (speech != null) unawaited(speech.cancel());
    super.dispose();
  }

  void _changeMonth(DateTime month) {
    FocusScope.of(context).unfocus();
    setState(() {
      _targetMonth = DateTime(month.year, month.month);
      _assistantMessage = null;
    });
  }

  double _effectiveAmount(
    BudgetSuggestion suggestion,
    BudgetPlanPreferences preferences,
  ) {
    return preferences.amountOverrideFor(
          _targetMonth,
          suggestion.id,
        ) ??
        suggestion.amount;
  }

  List<BudgetEffectiveItem> _includedItems(
    MonthlySmartPlan plan,
    BudgetPlanPreferences preferences,
  ) {
    return plan.expectedItems
        .where(
          (item) =>
              item.suggestion.isAutoIncluded &&
              preferences.isIncluded(_targetMonth, item.suggestion.id),
        )
        .map(
          (item) => BudgetEffectiveItem(
            item: item,
            plannedAmount: _effectiveAmount(item.suggestion, preferences),
          ),
        )
        .toList(growable: false);
  }

  double _bufferAmount(
    MonthlySmartPlan plan,
    BudgetPlanPreferences preferences,
  ) {
    return preferences.customBufferFor(_targetMonth) ??
        plan.draft.surpriseBuffer;
  }

  double _recommendedBudget(
    MonthlySmartPlan plan,
    BudgetPlanPreferences preferences,
  ) {
    final expected = _includedItems(plan, preferences).fold<double>(
      0,
      (sum, item) => sum + item.plannedAmount,
    );
    return expected + _bufferAmount(plan, preferences);
  }

  Future<void> _usePlan(
    MonthlySmartPlan plan,
    BudgetPlanPreferences preferences,
  ) async {
    if (_saving) return;
    final total = _recommendedBudget(plan, preferences);
    if (!total.isFinite || total < 0) return;

    setState(() => _saving = true);
    try {
      await ref.read(budgetProvider.notifier).setBudget(
            total,
            plan.draft.targetMonth,
          );
      if (!mounted) return;
      _showMessage(
        'Budget saved for ${DateFormat.yMMMM().format(plan.draft.targetMonth)} · Rs. ${total.toStringAsFixed(0)}',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _processBudgetCommand(String raw) async {
    final input = raw.trim();
    if (input.isEmpty || _processingCommand) return;

    setState(() => _processingCommand = true);
    try {
      final parser = ref.read(budgetIntentParserProvider);
      final intents = parser.parseMany(input);
      final replies = <String>[];

      for (final intent in intents) {
        final reply = await _applyBudgetIntent(intent);
        if (reply != null && reply.isNotEmpty) replies.add(reply);
      }

      if (!mounted) return;
      _commandController.clear();
      setState(() {
        _assistantMessage = replies.isEmpty
            ? 'Plan updated.'
            : replies.join(' ');
      });
    } finally {
      if (mounted) setState(() => _processingCommand = false);
    }
  }

  Future<String?> _applyBudgetIntent(BudgetIntent intent) async {
    final plan = ref.read(monthlySmartPlanProvider(_targetMonth));
    final preferences = ref.read(budgetPlanPreferencesProvider);
    final recommended = _recommendedBudget(plan, preferences);
    final savings = preferences.savingsGoalFor(_targetMonth);
    final allowance = plan.allowanceContext;

    switch (intent.action) {
      case BudgetIntentAction.setBudget:
        final amount = intent.amount;
        if (amount == null || amount <= 0) {
          return 'Tell me the monthly budget amount.';
        }
        await ref.read(budgetProvider.notifier).setBudget(amount, _targetMonth);
        return 'Monthly budget set to Rs. ${amount.toStringAsFixed(0)}.';

      case BudgetIntentAction.setSavingsGoal:
        final amount = intent.amount;
        if (amount == null || amount < 0) {
          return 'Tell me how much you want to save.';
        }
        await ref
            .read(budgetPlanPreferencesProvider.notifier)
            .setSavingsGoal(_targetMonth, amount);
        return amount == 0
            ? 'Savings target cleared.'
            : 'Rs. ${amount.toStringAsFixed(0)} is protected for savings.';

      case BudgetIntentAction.setBuffer:
        final amount = intent.amount;
        if (amount == null || amount < 0) {
          return 'Tell me the safety buffer amount.';
        }
        await ref
            .read(budgetPlanPreferencesProvider.notifier)
            .setCustomBuffer(_targetMonth, amount);
        return 'Safety buffer set to Rs. ${amount.toStringAsFixed(0)}.';

      case BudgetIntentAction.setItemAmount:
      case BudgetIntentAction.reduceItem:
      case BudgetIntentAction.increaseItem:
        final target = _resolveTarget(plan, intent.target);
        if (target == null) {
          return 'I could not match that to a planned item.';
        }

        var amount = intent.amount;
        if (intent.action == BudgetIntentAction.reduceItem) {
          amount = target.effectiveAmount * 0.8;
        } else if (intent.action == BudgetIntentAction.increaseItem) {
          amount = target.effectiveAmount * 1.2;
        }
        if (amount == null || amount < 0) {
          return 'Tell me the amount for ${target.title}.';
        }

        if (target.isNewExpense) {
          await ref
              .read(monthlyPlanMemoryProvider.notifier)
              .setRemembered(target.id, true);
          await ref
              .read(budgetPlanPreferencesProvider.notifier)
              .setOneTime(target.id, false);
        }
        await ref
            .read(budgetPlanPreferencesProvider.notifier)
            .setAmountOverride(_targetMonth, target.id, amount);
        return '${target.title} planned at Rs. ${amount.toStringAsFixed(0)}.';

      case BudgetIntentAction.rememberRecurring:
        final target = _resolveTarget(plan, intent.target);
        if (target == null) {
          return 'I could not match that recurring item.';
        }
        await ref
            .read(monthlyPlanMemoryProvider.notifier)
            .setRemembered(target.id, true);
        await ref
            .read(budgetPlanPreferencesProvider.notifier)
            .setOneTime(target.id, false);
        return '${target.title} will be treated as recurring.';

      case BudgetIntentAction.markOneTime:
        final target = _resolveTarget(plan, intent.target);
        if (target == null) {
          return 'I could not match that one-time item.';
        }
        if (target.isNewExpense) {
          await ref
              .read(monthlyPlanMemoryProvider.notifier)
              .setRemembered(target.id, false);
        }
        await ref
            .read(budgetPlanPreferencesProvider.notifier)
            .setOneTime(target.id, true);
        return '${target.title} marked as one-time.';

      case BudgetIntentAction.queryRecommended:
        return 'A safe plan is about Rs. ${recommended.toStringAsFixed(0)} before savings.';

      case BudgetIntentAction.queryDailySafe:
        if (allowance <= 0) {
          return 'Add income first so I can calculate a safe daily amount.';
        }
        final now = DateTime.now();
        final isCurrent = now.year == _targetMonth.year &&
            now.month == _targetMonth.month;
        final lastDay =
            DateTime(_targetMonth.year, _targetMonth.month + 1, 0).day;
        final days = isCurrent
            ? (lastDay - now.day + 1).clamp(1, lastDay)
            : lastDay;
        final remaining =
            (allowance - savings - plan.currentMonthSpent)
                .clamp(0, double.infinity)
                .toDouble();
        return 'Safe daily spending is about Rs. ${(remaining / days).toStringAsFixed(0)}.';

      case BudgetIntentAction.queryCanSpend:
        final amount = intent.amount;
        if (amount == null || amount <= 0) {
          return 'Tell me how much you want to spend.';
        }
        if (allowance <= 0) {
          return 'Add income first so I can judge that safely.';
        }
        final flexible =
            allowance - savings - plan.currentMonthSpent;
        if (flexible >= amount) {
          return 'Yes. After Rs. ${amount.toStringAsFixed(0)}, about Rs. ${(flexible - amount).toStringAsFixed(0)} remains outside your savings target.';
        }
        return 'That is about Rs. ${(amount - flexible).abs().toStringAsFixed(0)} above the money currently available outside savings.';

      case BudgetIntentAction.queryWhy:
        final included = _includedItems(plan, preferences);
        final expected = included.fold<double>(
          0,
          (sum, item) => sum + item.plannedAmount,
        );
        final buffer = _bufferAmount(plan, preferences);
        return 'The Rs. ${recommended.toStringAsFixed(0)} plan is Rs. ${expected.toStringAsFixed(0)} expected spending plus Rs. ${buffer.toStringAsFixed(0)} safety buffer.';

      case BudgetIntentAction.unknown:
        return 'Try “budget 40k”, “save 5k”, “petrol max 4k”, or “hostel har month”.';
    }
  }

  _BudgetTarget? _resolveTarget(
    MonthlySmartPlan plan,
    String? rawTarget,
  ) {
    if (rawTarget == null || rawTarget.trim().isEmpty) return null;
    final engine = ref.read(budgetSuggestionEngineProvider);
    final target = engine.canonicalizeTitle(rawTarget);
    if (target.isEmpty) return null;

    final candidates = <_BudgetTarget>[
      for (final item in plan.expectedItems)
        _BudgetTarget(
          id: item.suggestion.id,
          title: item.suggestion.title,
          category: item.suggestion.category,
          effectiveAmount: _effectiveAmount(
            item.suggestion,
            ref.read(budgetPlanPreferencesProvider),
          ),
          isNewExpense: false,
        ),
      for (final item in plan.newExpenses)
        _BudgetTarget(
          id: item.id,
          title: item.title,
          category: item.category,
          effectiveAmount: item.amount,
          isNewExpense: true,
        ),
    ];

    _BudgetTarget? best;
    var bestScore = 0.0;
    for (final candidate in candidates) {
      final title = engine.canonicalizeTitle(candidate.title);
      final category = candidate.category.toLowerCase().trim();
      var score = 0.0;
      if (title == target) {
        score = 1.0;
      } else if (title.contains(target) || target.contains(title)) {
        score = 0.9;
      } else if (category == target.toLowerCase()) {
        score = 0.82;
      } else {
        final targetWords = target.split(' ').toSet();
        final titleWords = title.split(' ').toSet();
        if (targetWords.isNotEmpty && titleWords.isNotEmpty) {
          final shared = targetWords.intersection(titleWords).length;
          score = shared / targetWords.length * 0.75;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    return bestScore >= 0.5 ? best : null;
  }

  Future<void> _toggleVoice() async {
    if (_isListening) {
      await _speech?.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    final speech = DeviceSpeechRecognitionProvider();
    final available = await speech.initialize(
      onStatus: (status) {
        if (!mounted) return;
        final normalized = status.toLowerCase();
        if (normalized.contains('done') ||
            normalized.contains('notlistening')) {
          setState(() => _isListening = false);
        }
      },
      onError: (error) {
        if (!mounted) return;
        setState(() => _isListening = false);
        _showMessage('Voice input could not start.');
      },
    );
    if (!available || !mounted) {
      _showMessage('Voice recognition is not available on this device.');
      return;
    }

    _speech = speech;
    final locale = await speech.systemLocale();
    if (!mounted) return;
    setState(() => _isListening = true);

    await speech.listen(
      options: SpeechRecognitionListenOptions(
        localeId: locale?.localeId,
        partialResults: true,
        pauseFor: const Duration(seconds: 2),
        listenFor: const Duration(seconds: 15),
      ),
      onResult: (result) async {
        if (!mounted || result.text.trim().isEmpty) return;
        _commandController.text = result.text;
        _commandController.selection = TextSelection.collapsed(
          offset: _commandController.text.length,
        );
        if (result.isFinal) {
          setState(() => _isListening = false);
          await _processBudgetCommand(result.text);
        }
      },
    );
  }

  Future<void> _editSavingsGoal(double current) async {
    final value = await _amountDialog(
      title: 'Savings goal',
      initialValue: current,
      allowZero: true,
    );
    if (value == null) return;
    await ref
        .read(budgetPlanPreferencesProvider.notifier)
        .setSavingsGoal(_targetMonth, value);
  }

  Future<void> _editBuffer(
    MonthlySmartPlan plan,
    BudgetPlanPreferences preferences,
  ) async {
    final suggested = plan.draft.surpriseBuffer;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final custom = preferences.customBufferFor(_targetMonth);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Safety buffer',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text('Extra room for unexpected expenses.'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use recommended'),
                  trailing: Text('Rs. ${suggested.toStringAsFixed(0)}'),
                  selected: custom == null,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await ref
                        .read(budgetPlanPreferencesProvider.notifier)
                        .setCustomBuffer(_targetMonth, null);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('No safety buffer'),
                  trailing: const Text('Rs. 0'),
                  selected: custom == 0,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await ref
                        .read(budgetPlanPreferencesProvider.notifier)
                        .setCustomBuffer(_targetMonth, 0);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Custom amount'),
                  trailing: custom != null && custom > 0
                      ? Text('Rs. ${custom.toStringAsFixed(0)}')
                      : null,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final value = await _amountDialog(
                      title: 'Custom safety buffer',
                      initialValue: custom ?? suggested,
                      allowZero: true,
                    );
                    if (value == null) return;
                    await ref
                        .read(budgetPlanPreferencesProvider.notifier)
                        .setCustomBuffer(_targetMonth, value);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<double?> _amountDialog({
    required String title,
    required double initialValue,
    bool allowZero = false,
  }) async {
    final controller = TextEditingController(
      text: initialValue.toStringAsFixed(0),
    );
    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            prefixText: 'Rs. ',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              final valid = value != null &&
                  value.isFinite &&
                  (allowZero ? value >= 0 : value > 0);
              if (valid) Navigator.pop(dialogContext, value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _showExpectedItemOptions(
    MonthlyPlanItem item,
    BudgetPlanPreferences preferences,
  ) async {
    final suggestion = item.suggestion;
    final included =
        preferences.isIncluded(_targetMonth, suggestion.id);
    final amount = _effectiveAmount(suggestion, preferences);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  suggestion.title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  '${suggestion.category} · Rs. ${amount.toStringAsFixed(0)}',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include in this month'),
                value: included,
                onChanged: (value) async {
                  await ref
                      .read(budgetPlanPreferencesProvider.notifier)
                      .setIncluded(_targetMonth, suggestion.id, value);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Change planned amount'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final value = await _amountDialog(
                    title: suggestion.title,
                    initialValue: amount,
                  );
                  if (value == null) return;
                  await ref
                      .read(budgetPlanPreferencesProvider.notifier)
                      .setAmountOverride(
                        _targetMonth,
                        suggestion.id,
                        value,
                      );
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.repeat_rounded),
                title: const Text('Treat as recurring'),
                onTap: () async {
                  await ref
                      .read(monthlyPlanMemoryProvider.notifier)
                      .setRemembered(suggestion.id, true);
                  await ref
                      .read(budgetPlanPreferencesProvider.notifier)
                      .setOneTime(suggestion.id, false);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.looks_one_outlined),
                title: const Text('Treat as one-time'),
                onTap: () async {
                  await ref
                      .read(budgetPlanPreferencesProvider.notifier)
                      .setOneTime(suggestion.id, true);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
              ),
              if (preferences.amountOverrideFor(
                    _targetMonth,
                    suggestion.id,
                  ) !=
                  null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.restart_alt_rounded),
                  title: const Text('Use learned amount again'),
                  onTap: () async {
                    await ref
                        .read(budgetPlanPreferencesProvider.notifier)
                        .setAmountOverride(
                          _targetMonth,
                          suggestion.id,
                          null,
                        );
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAllExpected(
    MonthlySmartPlan plan,
    BudgetPlanPreferences preferences,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.72,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: plan.expectedItems.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = plan.expectedItems[index];
              return _ExpectedRow(
                item: item,
                amount: _effectiveAmount(item.suggestion, preferences),
                included: preferences.isIncluded(
                  _targetMonth,
                  item.suggestion.id,
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showExpectedItemOptions(item, preferences);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _reviewUnplanned(MonthlySmartPlan plan) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.72,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: plan.newExpenses.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = plan.newExpenses[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 6,
                ),
                title: Text(
                  item.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${item.category} · ${item.frequency} log${item.frequency == 1 ? '' : 's'}',
                ),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Set future behavior',
                  onSelected: (value) async {
                    final recurring = value == 'recurring';
                    await ref
                        .read(monthlyPlanMemoryProvider.notifier)
                        .setRemembered(item.id, recurring);
                    await ref
                        .read(budgetPlanPreferencesProvider.notifier)
                        .setOneTime(item.id, !recurring);
                    if (sheetContext.mounted) {
                      Navigator.pop(sheetContext);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'one_time',
                      child: Text('One time'),
                    ),
                    PopupMenuItem(
                      value: 'recurring',
                      child: Text('Recurring'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(message),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(monthlySmartPlanProvider(_targetMonth));
    final preferences = ref.watch(budgetPlanPreferencesProvider);
    final savedBudget = ref.watch(budgetProvider)[budgetMonthKey(_targetMonth)];
    final primaryColor =
        Color(ref.watch(settingsProvider).profileColorValue);

    final included = _includedItems(plan, preferences);
    final expectedTotal = included.fold<double>(
      0,
      (sum, item) => sum + item.plannedAmount,
    );
    final buffer = _bufferAmount(plan, preferences);
    final recommended = expectedTotal + buffer;
    final savings = preferences.savingsGoalFor(_targetMonth);
    final allowance = plan.allowanceContext;
    final freeAfterPlan = allowance > 0
        ? allowance - savings - recommended
        : null;
    final insights = ref.read(budgetCoachEngineProvider).build(
          plan: plan,
          includedItems: included,
          recommendedBudget: recommended,
          savingsGoal: savings,
          allowance: allowance,
          targetMonth: _targetMonth,
        );
    final now = DateTime.now();
    final maxMonth = DateTime(now.year, now.month + 12);

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
      children: [
        Card(
          elevation: 0,
          child: MonthSelectorControl(
            selectedMonth: _targetMonth,
            maxMonth: maxMonth,
            onChanged: _changeMonth,
          ),
        ),
        const SizedBox(height: 14),
        _PlanHeroCard(
          recommendedBudget: recommended,
          expectedIncome: allowance,
          expectedSpending: expectedTotal,
          safetyBuffer: buffer,
          savingsGoal: savings,
          freeAfterPlan: freeAfterPlan,
          savedBudget: savedBudget,
          color: primaryColor,
          saving: _saving,
          onUsePlan: () => _usePlan(plan, preferences),
          onSavingsTap: () => _editSavingsGoal(savings),
        ),
        const SizedBox(height: 14),
        _SmartPlanCommandBar(
          controller: _commandController,
          color: primaryColor,
          listening: _isListening,
          processing: _processingCommand,
          assistantMessage: _assistantMessage,
          onSubmit: _processBudgetCommand,
          onVoiceTap: _toggleVoice,
        ),
        const SizedBox(height: 18),
        _CompactSectionHeader(
          title: 'Expected',
          trailing: plan.expectedItems.isEmpty
              ? null
              : Text(
                  '${plan.handledCount}/${plan.expectedItems.length} handled',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
        ),
        const SizedBox(height: 8),
        _ExpectedSummaryCard(
          items: plan.expectedItems.take(4).toList(growable: false),
          amountFor: (item) =>
              _effectiveAmount(item.suggestion, preferences),
          includedFor: (item) => preferences.isIncluded(
            _targetMonth,
            item.suggestion.id,
          ),
          onTap: (item) => _showExpectedItemOptions(item, preferences),
          onSeeAll: plan.expectedItems.length > 4
              ? () => _showAllExpected(plan, preferences)
              : null,
        ),
        const SizedBox(height: 14),
        _UnplannedSummaryCard(
          items: plan.newExpenses,
          onReview: plan.newExpenses.isEmpty
              ? null
              : () => _reviewUnplanned(plan),
        ),
        const SizedBox(height: 14),
        _BufferRow(
          amount: buffer,
          recommended: plan.draft.surpriseBuffer,
          isCustom:
              preferences.customBufferFor(_targetMonth) != null,
          onTap: () => _editBuffer(plan, preferences),
        ),
        const SizedBox(height: 18),
        const _CompactSectionHeader(title: 'Smart insight'),
        const SizedBox(height: 8),
        ...insights.map(
          (insight) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _InsightCard(insight: insight),
          ),
        ),
      ],
    );
  }
}

class _BudgetTarget {
  final String id;
  final String title;
  final String category;
  final double effectiveAmount;
  final bool isNewExpense;

  const _BudgetTarget({
    required this.id,
    required this.title,
    required this.category,
    required this.effectiveAmount,
    required this.isNewExpense,
  });
}

class _PlanHeroCard extends StatelessWidget {
  final double recommendedBudget;
  final double expectedIncome;
  final double expectedSpending;
  final double safetyBuffer;
  final double savingsGoal;
  final double? freeAfterPlan;
  final double? savedBudget;
  final Color color;
  final bool saving;
  final VoidCallback onUsePlan;
  final VoidCallback onSavingsTap;

  const _PlanHeroCard({
    required this.recommendedBudget,
    required this.expectedIncome,
    required this.expectedSpending,
    required this.safetyBuffer,
    required this.savingsGoal,
    required this.freeAfterPlan,
    required this.savedBudget,
    required this.color,
    required this.saving,
    required this.onUsePlan,
    required this.onSavingsTap,
  });

  @override
  Widget build(BuildContext context) {
    final negative = freeAfterPlan != null && freeAfterPlan! < 0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Recommended budget',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (savedBudget != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surface
                        .withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Saved Rs. ${savedBudget!.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Rs. ${recommendedBudget.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 31,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Built from recent recurring spending and your corrections.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricChip(
                label: 'Income',
                value: expectedIncome > 0
                    ? 'Rs. ${expectedIncome.toStringAsFixed(0)}'
                    : 'Unknown',
              ),
              _MetricChip(
                label: 'Expected',
                value: 'Rs. ${expectedSpending.toStringAsFixed(0)}',
              ),
              _MetricChip(
                label: 'Safety',
                value: 'Rs. ${safetyBuffer.toStringAsFixed(0)}',
              ),
              _MetricChip(
                label: 'Savings',
                value: 'Rs. ${savingsGoal.toStringAsFixed(0)}',
                onTap: onSavingsTap,
              ),
              if (freeAfterPlan != null)
                _MetricChip(
                  label: negative ? 'Short' : 'Free',
                  value:
                      'Rs. ${freeAfterPlan!.abs().toStringAsFixed(0)}',
                  emphasis: negative,
                ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: saving ? null : onUsePlan,
              style: FilledButton.styleFrom(
                backgroundColor: color,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              icon: const Icon(Icons.auto_awesome_rounded, size: 19),
              label: Text(
                saving ? 'Saving…' : 'Use this plan',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool emphasis;

  const _MetricChip({
    required this.label,
    required this.value,
    this.onTap,
    this.emphasis = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: emphasis
              ? colors.errorContainer.withValues(alpha: 0.65)
              : colors.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$label  ',
                style: TextStyle(
                  color: emphasis
                      ? colors.onErrorContainer
                      : colors.onSurfaceVariant,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextSpan(
                text: value,
                style: TextStyle(
                  color: emphasis
                      ? colors.onErrorContainer
                      : colors.onSurface,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmartPlanCommandBar extends StatelessWidget {
  final TextEditingController controller;
  final Color color;
  final bool listening;
  final bool processing;
  final String? assistantMessage;
  final ValueChanged<String> onSubmit;
  final VoidCallback onVoiceTap;

  const _SmartPlanCommandBar({
    required this.controller,
    required this.color,
    required this.listening,
    required this.processing,
    required this.assistantMessage,
    required this.onSubmit,
    required this.onVoiceTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 10, 10),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: processing ? null : onSubmit,
                    decoration: const InputDecoration(
                      hintText: 'e.g. save 5k · petrol max 4k',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: listening ? 'Stop listening' : 'Speak',
                  onPressed: processing ? null : onVoiceTap,
                  icon: Icon(
                    listening
                        ? Icons.stop_circle_outlined
                        : Icons.mic_none_rounded,
                    color: listening ? Colors.red : color,
                  ),
                ),
                IconButton(
                  tooltip: 'Apply',
                  onPressed: processing
                      ? null
                      : () => onSubmit(controller.text),
                  icon: processing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.arrow_upward_rounded, color: color),
                ),
              ],
            ),
            if (assistantMessage != null && assistantMessage!.isNotEmpty) ...[
              const Divider(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  assistantMessage!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CompactSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const _CompactSectionHeader({
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _ExpectedSummaryCard extends StatelessWidget {
  final List<MonthlyPlanItem> items;
  final double Function(MonthlyPlanItem item) amountFor;
  final bool Function(MonthlyPlanItem item) includedFor;
  final ValueChanged<MonthlyPlanItem> onTap;
  final VoidCallback? onSeeAll;

  const _ExpectedSummaryCard({
    required this.items,
    required this.amountFor,
    required this.includedFor,
    required this.onTap,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _CompactEmptyCard(
        icon: Icons.event_note_outlined,
        text: 'No reliable recurring items yet. Keep logging normally.',
      );
    }

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            _ExpectedRow(
              item: items[index],
              amount: amountFor(items[index]),
              included: includedFor(items[index]),
              onTap: () => onTap(items[index]),
            ),
            if (index != items.length - 1)
              const Divider(height: 1),
          ],
          if (onSeeAll != null) ...[
            const Divider(height: 1),
            TextButton(
              onPressed: onSeeAll,
              child: const Text('See all expected items'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExpectedRow extends StatelessWidget {
  final MonthlyPlanItem item;
  final double amount;
  final bool included;
  final VoidCallback onTap;

  const _ExpectedRow({
    required this.item,
    required this.amount,
    required this.included,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final suggestion = item.suggestion;
    final timing = suggestion.expectedDay == null
        ? null
        : 'around day ${suggestion.expectedDay}';

    return ListTile(
      onTap: onTap,
      dense: true,
      leading: Icon(
        item.status == MonthlyPlanItemStatus.handled
            ? Icons.check_circle_rounded
            : item.status == MonthlyPlanItemStatus.inProgress
                ? Icons.timelapse_rounded
                : Icons.schedule_rounded,
        color: included
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline,
      ),
      title: Text(
        suggestion.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          decoration: included ? null : TextDecoration.lineThrough,
        ),
      ),
      subtitle: Text(
        item.status == MonthlyPlanItemStatus.handled
            ? 'Handled · Rs. ${item.actualAmount.toStringAsFixed(0)}'
            : item.status == MonthlyPlanItemStatus.inProgress
                ? 'Rs. ${item.actualAmount.toStringAsFixed(0)} so far'
                : timing ?? _confidenceLabel(suggestion.confidenceTier),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        'Rs. ${amount.toStringAsFixed(0)}',
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }

  static String _confidenceLabel(BudgetConfidenceTier tier) {
    switch (tier) {
      case BudgetConfidenceTier.high:
        return 'Strong pattern';
      case BudgetConfidenceTier.medium:
        return 'Likely recurring';
      case BudgetConfidenceTier.low:
        return 'Review suggestion';
    }
  }
}

class _UnplannedSummaryCard extends StatelessWidget {
  final List<MonthlyNewExpense> items;
  final VoidCallback? onReview;

  const _UnplannedSummaryCard({
    required this.items,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _CompactEmptyCard(
        icon: Icons.check_circle_outline_rounded,
        text: 'No unexpected spending detected this month.',
      );
    }

    final total =
        items.fold<double>(0, (sum, item) => sum + item.amount);
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.new_releases_outlined, size: 21),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Unplanned spending',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  'Rs. ${total.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final item in items.take(3))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Text(
                      'Rs. ${item.amount.toStringAsFixed(0)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onReview,
                child: Text(
                  items.length > 3
                      ? 'Review all ${items.length}'
                      : 'Review',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BufferRow extends StatelessWidget {
  final double amount;
  final double recommended;
  final bool isCustom;
  final VoidCallback onTap;

  const _BufferRow({
    required this.amount,
    required this.recommended,
    required this.isCustom,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.shield_outlined),
        title: const Text(
          'Safety buffer',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          isCustom
              ? 'Custom · recommended Rs. ${recommended.toStringAsFixed(0)}'
              : 'Recommended from recent unexpected spending',
        ),
        trailing: Text(
          'Rs. ${amount.toStringAsFixed(0)}',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final BudgetCoachInsight insight;

  const _InsightCard({required this.insight});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    IconData icon;
    Color color;
    switch (insight.kind) {
      case BudgetCoachInsightKind.positive:
        icon = Icons.check_circle_outline_rounded;
        color = Colors.green;
        break;
      case BudgetCoachInsightKind.warning:
        icon = Icons.warning_amber_rounded;
        color = colors.error;
        break;
      case BudgetCoachInsightKind.upcoming:
        icon = Icons.event_upcoming_outlined;
        color = colors.primary;
        break;
      case BudgetCoachInsightKind.neutral:
        icon = Icons.lightbulb_outline_rounded;
        color = colors.secondary;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.13)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  insight.message,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactEmptyCard extends StatelessWidget {
  final IconData icon;
  final String text;

  const _CompactEmptyCard({
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
            Icon(
              icon,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
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

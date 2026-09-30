import 'dart:math' as math;

import '../../models/expense_model.dart';
import 'budget_prediction_models.dart';

class BudgetIntentEvaluator {
  static const Set<String> _billKeywords = {
    'fee', 'fees', 'bill', 'recharge', 'package', 'pkg', 'rent', 'mess',
    'subscription', 'wifi', 'internet', 'gym', 'hostel', 'dues',
  };

  static const Set<String> _fixedCategories = {
    'education', 'bills', 'hostel',
  };

  static const Set<String> _anomalyCategories = {
    'shopping', 'gifts', 'entertainment',
  };

  ExpenseIntent evaluateIntent(BudgetExpenseGroup group) {
    final category = group.category.trim().toLowerCase();
    final title = group.canonicalTitle.toLowerCase();
    final hasBillKeyword = _billKeywords.any(
      (keyword) => _containsWord(title, keyword),
    );

    if (_fixedCategories.contains(category) || hasBillKeyword) {
      return ExpenseIntent.fixedBill;
    }
    if (group.frequency >= 3 && !_anomalyCategories.contains(category)) {
      return ExpenseIntent.frequentHabit;
    }
    if (_anomalyCategories.contains(category)) {
      return ExpenseIntent.oneOffAnomaly;
    }
    return ExpenseIntent.uncertain;
  }

  bool isDiscretionaryCategory(String category) =>
      _anomalyCategories.contains(category.trim().toLowerCase());

  bool _containsWord(String title, String keyword) {
    return RegExp(
      '(?:^|\\s)${RegExp.escape(keyword)}(?:\\s|\$)',
      caseSensitive: false,
    ).hasMatch(title);
  }
}

class BudgetSuggestionEngine {
  final BudgetIntentEvaluator evaluator;

  BudgetSuggestionEngine({BudgetIntentEvaluator? evaluator})
      : evaluator = evaluator ?? BudgetIntentEvaluator();

  BudgetDraft buildDraft({
    required DateTime targetMonth,
    required Iterable<Expense> allTransactions,
    Set<String> excludedTransactionIds = const {},
    int surpriseLookbackMonths = 3,
  }) {
    final normalizedTarget = DateTime(targetMonth.year, targetMonth.month, 1);
    final sourceMonth = DateTime(
      normalizedTarget.year,
      normalizedTarget.month - 1,
      1,
    );

    final eligible = allTransactions.where(
      (entry) =>
          entry.deletedAt == null &&
          entry.type == 'expense' &&
          entry.category.trim().toLowerCase() != 'transfer' &&
          !excludedTransactionIds.contains(entry.id) &&
          entry.amount.isFinite &&
          entry.amount > 0,
    ).toList(growable: false);

    final sourceExpenses = eligible.where(
      (entry) => _sameMonth(entry.date, sourceMonth),
    );

    final sourceGroups = groupExpenses(sourceExpenses);
    final fixed = <BudgetSuggestion>[];
    final habits = <BudgetSuggestion>[];

    for (final group in sourceGroups) {
      final intent = evaluator.evaluateIntent(group);
      switch (intent) {
        case ExpenseIntent.fixedBill:
          fixed.add(
            _suggestionFor(
              group,
              intent,
              amount: group.latestAmount,
              confidence: _fixedConfidence(group),
              reason: group.frequency == 1
                  ? 'Paid last month and looks like a recurring obligation'
                  : 'Repeated last month and looks like a recurring obligation',
              selectedByDefault: true,
            ),
          );
          break;
        case ExpenseIntent.frequentHabit:
          habits.add(
            _suggestionFor(
              group,
              intent,
              amount: group.totalAmount,
              confidence: _habitConfidence(group),
              reason:
                  'Logged ${group.frequency} times last month · Rs. ${group.totalAmount.toStringAsFixed(0)} total',
              selectedByDefault: true,
            ),
          );
          break;
        case ExpenseIntent.oneOffAnomaly:
        case ExpenseIntent.uncertain:
          break;
      }
    }

    fixed.sort((a, b) => b.amount.compareTo(a.amount));
    habits.sort((a, b) => b.amount.compareTo(a.amount));

    final surpriseTotals = <double>[];
    for (var offset = 1; offset <= surpriseLookbackMonths; offset++) {
      final month = DateTime(
        normalizedTarget.year,
        normalizedTarget.month - offset,
        1,
      );
      final monthExpenses = eligible.where(
        (entry) => _sameMonth(entry.date, month),
      );
      final groups = groupExpenses(monthExpenses);
      var unexpectedTotal = 0.0;
      for (final group in groups) {
        final intent = evaluator.evaluateIntent(group);
        final isUnexpected = intent == ExpenseIntent.uncertain &&
            !evaluator.isDiscretionaryCategory(group.category);
        if (isUnexpected) unexpectedTotal += group.totalAmount;
      }
      surpriseTotals.add(unexpectedTotal);
    }

    final sourceIncome = allTransactions
        .where(
          (entry) =>
              entry.deletedAt == null &&
              entry.type == 'income' &&
              entry.category.trim().toLowerCase() != 'transfer' &&
              !excludedTransactionIds.contains(entry.id) &&
              _sameMonth(entry.date, sourceMonth),
        )
        .fold<double>(0, (sum, entry) => sum + entry.amount);

    return BudgetDraft(
      targetMonth: normalizedTarget,
      sourceMonth: sourceMonth,
      fixedObligations: fixed,
      routineHabits: habits,
      surpriseBuffer: _surpriseBuffer(surpriseTotals),
      previousMonthIncome: sourceIncome,
      surpriseHistoryMonths: surpriseTotals.length,
    );
  }

  List<BudgetExpenseGroup> groupExpenses(Iterable<Expense> expenses) {
    final buckets = <String, List<Expense>>{};
    for (final entry in expenses) {
      final canonicalTitle = _canonicalTitle(entry.title);
      final key =
          '${entry.category.trim().toLowerCase()}|${canonicalTitle}';
      buckets.putIfAbsent(key, () => <Expense>[]).add(entry);
    }

    return buckets.values.map((items) {
      items.sort((a, b) => b.date.compareTo(a.date));
      final first = items.first;
      final title = _displayTitle(_canonicalTitle(first.title));
      return BudgetExpenseGroup(
        canonicalTitle: title,
        category: first.category,
        transactions: List.unmodifiable(items),
        totalAmount: items.fold(0, (sum, entry) => sum + entry.amount),
      );
    }).toList(growable: false);
  }

  BudgetSuggestion _suggestionFor(
    BudgetExpenseGroup group,
    ExpenseIntent intent, {
    required double amount,
    required double confidence,
    required String reason,
    required bool selectedByDefault,
  }) {
    return BudgetSuggestion(
      id: '${group.category.toLowerCase()}|${_canonicalTitle(group.canonicalTitle)}',
      title: group.canonicalTitle,
      category: group.category,
      intent: intent,
      amount: amount,
      frequency: group.frequency,
      confidence: confidence.clamp(0, 1).toDouble(),
      reason: reason,
      selectedByDefault: selectedByDefault,
    );
  }

  double _fixedConfidence(BudgetExpenseGroup group) {
    var score = 0.65;
    if (group.frequency >= 2) score += 0.15;
    if (group.averageAmount > 0) score += 0.05;
    return math.min(score, 0.95);
  }

  double _habitConfidence(BudgetExpenseGroup group) {
    var score = 0.65;
    if (group.frequency >= 5) score += 0.15;
    return math.min(score, 0.9);
  }

  double _surpriseBuffer(List<double> monthlyTotals) {
    if (monthlyTotals.isEmpty) return 0;
    final sorted = [...monthlyTotals]..sort();
    final middle = sorted.length ~/ 2;
    final median = sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
    if (median <= 0) return 0;
    final buffered = median * 1.2;
    return (buffered / 100).ceilToDouble() * 100;
  }

  String _canonicalTitle(String value) {
    final title = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\\s]+'), ' ')
        .replaceAll(RegExp(r'\\s+'), ' ')
        .trim();

    const aliases = <String, String>{
      'fuel': 'petrol',
      'petrol bike': 'petrol',
      'bike petrol': 'petrol',
      'jazz cash': 'jazzcash',
      'zong pkg': 'zong package',
      'mobile pkg': 'mobile package',
      'internet pkg': 'internet package',
    };
    return aliases[title] ?? title;
  }

  String _displayTitle(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Expense';
    return trimmed
        .split(RegExp(r'\\s+'))
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }

  bool _sameMonth(DateTime value, DateTime month) =>
      value.year == month.year && value.month == month.month;
}

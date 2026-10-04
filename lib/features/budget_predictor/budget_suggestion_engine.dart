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
    Set<String> rememberedPatternKeys = const {},
    Set<String> ignoredPatternKeys = const {},
    int surpriseLookbackMonths = 6,
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
      final key = suggestionKey(group.canonicalTitle, group.category);
      if (ignoredPatternKeys.contains(key)) continue;
      final remembered = rememberedPatternKeys.contains(key);
      final recentTotals = _recentPatternTotals(
        eligible,
        key,
        sourceMonth,
        months: 6,
      );
      final recurringAcrossMonths =
          recentTotals.length >= 2 &&
          !evaluator.isDiscretionaryCategory(group.category);
      final expectedDay = _expectedDay(
        eligible,
        key,
        sourceMonth,
        months: 6,
      );
      final intent = remembered || recurringAcrossMonths
          ? ExpenseIntent.frequentHabit
          : evaluator.evaluateIntent(group);
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
              expectedDay: expectedDay,
            ),
          );
          break;
        case ExpenseIntent.frequentHabit:
          final recurringEstimate = recentTotals.isEmpty
              ? group.totalAmount
              : _median(recentTotals);
          habits.add(
            _suggestionFor(
              group,
              intent,
              amount: recurringAcrossMonths
                  ? recurringEstimate
                  : group.totalAmount,
              confidence: recurringAcrossMonths
                  ? math.min(
                      0.95,
                      math.max(_habitConfidence(group), 0.72 + recentTotals.length * 0.04),
                    )
                  : _habitConfidence(group),
              reason: remembered
                  ? 'Remembered from your plan'
                  : recurringAcrossMonths
                      ? 'Seen in ${recentTotals.length} recent months · usually around Rs. ${recurringEstimate.toStringAsFixed(0)}'
                      : 'Repeated last month',
              selectedByDefault: true,
              expectedDay: expectedDay,
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
      final monthExpenses = eligible
          .where((entry) => _sameMonth(entry.date, month))
          .toList(growable: false);
      if (monthExpenses.isEmpty) continue;
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
      final canonicalTitle = canonicalizeTitle(entry.title);
      final key = suggestionKey(canonicalTitle, entry.category);
      buckets.putIfAbsent(key, () => <Expense>[]).add(entry);
    }

    return buckets.values.map((items) {
      items.sort((a, b) => b.date.compareTo(a.date));
      final first = items.first;
      final title = _displayTitle(canonicalizeTitle(first.title));
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
    int? expectedDay,
  }) {
    return BudgetSuggestion(
      id: suggestionKey(group.canonicalTitle, group.category),
      title: group.canonicalTitle,
      category: group.category,
      intent: intent,
      amount: amount,
      frequency: group.frequency,
      confidence: confidence.clamp(0, 1).toDouble(),
      reason: reason,
      selectedByDefault: selectedByDefault,
      expectedDay: expectedDay,
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

  List<double> _recentPatternTotals(
    List<Expense> eligible,
    String key,
    DateTime sourceMonth, {
    required int months,
  }) {
    final totals = <double>[];
    for (var offset = 0; offset < months; offset++) {
      final month = DateTime(
        sourceMonth.year,
        sourceMonth.month - offset,
        1,
      );
      final matching = eligible.where(
        (entry) =>
            _sameMonth(entry.date, month) &&
            suggestionKey(entry.title, entry.category) == key,
      );
      final total =
          matching.fold<double>(0, (sum, entry) => sum + entry.amount);
      if (total > 0) totals.add(total);
    }
    return totals;
  }

  double _median(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }

  int? _expectedDay(
    List<Expense> eligible,
    String key,
    DateTime sourceMonth, {
    required int months,
  }) {
    final days = <int>[];
    for (var offset = 0; offset < months; offset++) {
      final month = DateTime(
        sourceMonth.year,
        sourceMonth.month - offset,
        1,
      );
      final matches = eligible
          .where(
            (entry) =>
                _sameMonth(entry.date, month) &&
                suggestionKey(entry.title, entry.category) == key,
          )
          .toList(growable: false);
      if (matches.isEmpty) continue;
      matches.sort((a, b) => a.date.compareTo(b.date));
      days.add(matches.first.date.day);
    }
    if (days.isEmpty) return null;
    days.sort();
    return days[days.length ~/ 2].clamp(1, 28);
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

  String suggestionKey(String title, String category) {
    return '${category.trim().toLowerCase()}|${canonicalizeTitle(title)}';
  }

  String canonicalizeTitle(String value) {
    final title = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    const aliases = <String, String>{
      'fuel': 'petrol',
      'petrol bike': 'petrol',
      'bike petrol': 'petrol',
      'bike fuel': 'petrol',
      'fuel bike': 'petrol',
      'petrol refill': 'petrol',
      'bike ka petrol': 'petrol',
      'jazz cash': 'jazzcash',
      'zong pkg': 'zong package',
      'zong recharge': 'zong package',
      'mobile pkg': 'mobile package',
      'mobile recharge': 'mobile package',
      'internet pkg': 'internet package',
      'wifi recharge': 'wifi bill',
      'hostel fees': 'hostel fee',
    };
    if (aliases.containsKey(title)) return aliases[title]!;
    if (RegExp(r'\b(petrol|fuel)\b').hasMatch(title) &&
        RegExp(r'\b(bike|refill)\b').hasMatch(title)) {
      return 'petrol';
    }
    return title;
  }

  String _displayTitle(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Expense';
    return trimmed
        .split(RegExp(r'\s+'))
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

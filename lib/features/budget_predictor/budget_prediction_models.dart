import '../../models/expense_model.dart';

enum ExpenseIntent {
  fixedBill,
  frequentHabit,
  oneOffAnomaly,
  uncertain,
}

class BudgetExpenseGroup {
  final String canonicalTitle;
  final String category;
  final List<Expense> transactions;
  final double totalAmount;

  const BudgetExpenseGroup({
    required this.canonicalTitle,
    required this.category,
    required this.transactions,
    required this.totalAmount,
  });

  int get frequency => transactions.length;

  double get averageAmount =>
      frequency == 0 ? 0 : totalAmount / frequency;

  double get latestAmount {
    if (transactions.isEmpty) return 0;
    final sorted = [...transactions]
      ..sort((a, b) => b.date.compareTo(a.date));
    return sorted.first.amount;
  }
}

class BudgetSuggestion {
  final String id;
  final String title;
  final String category;
  final ExpenseIntent intent;
  final double amount;
  final int frequency;
  final double confidence;
  final String reason;
  final bool selectedByDefault;

  const BudgetSuggestion({
    required this.id,
    required this.title,
    required this.category,
    required this.intent,
    required this.amount,
    required this.frequency,
    required this.confidence,
    required this.reason,
    required this.selectedByDefault,
  });
}

class BudgetDraft {
  final DateTime targetMonth;
  final DateTime sourceMonth;
  final List<BudgetSuggestion> fixedObligations;
  final List<BudgetSuggestion> routineHabits;
  final double surpriseBuffer;
  final double previousMonthIncome;
  final int surpriseHistoryMonths;

  const BudgetDraft({
    required this.targetMonth,
    required this.sourceMonth,
    required this.fixedObligations,
    required this.routineHabits,
    required this.surpriseBuffer,
    required this.previousMonthIncome,
    required this.surpriseHistoryMonths,
  });

  List<BudgetSuggestion> get suggestions => [
        ...fixedObligations,
        ...routineHabits,
      ];

  double get defaultSuggestedTotal =>
      suggestions
          .where((item) => item.selectedByDefault)
          .fold(0, (sum, item) => sum + item.amount) +
      surpriseBuffer;
}

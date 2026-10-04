import '../../models/expense_model.dart';

enum ExpenseIntent {
  fixedBill,
  frequentHabit,
  oneOffAnomaly,
  uncertain,
}

enum BudgetConfidenceTier {
  high,
  medium,
  low,
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
  final int? expectedDay;

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
    this.expectedDay,
  });

  BudgetConfidenceTier get confidenceTier {
    if (confidence >= 0.85) return BudgetConfidenceTier.high;
    if (confidence >= 0.65) return BudgetConfidenceTier.medium;
    return BudgetConfidenceTier.low;
  }

  bool get isAutoIncluded =>
      selectedByDefault && confidenceTier != BudgetConfidenceTier.low;
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
          .fold<double>(0.0, (sum, item) => sum + item.amount) +
      surpriseBuffer;
}


enum MonthlyPlanItemStatus {
  upcoming,
  inProgress,
  handled,
}

class MonthlyPlanItem {
  final BudgetSuggestion suggestion;
  final MonthlyPlanItemStatus status;
  final double actualAmount;
  final int actualFrequency;

  const MonthlyPlanItem({
    required this.suggestion,
    required this.status,
    required this.actualAmount,
    required this.actualFrequency,
  });

  bool get hasStarted => actualFrequency > 0;
  bool get isHandled => status == MonthlyPlanItemStatus.handled;
}

class MonthlyNewExpense {
  final String id;
  final String title;
  final String category;
  final double amount;
  final int frequency;
  final bool rememberedForFuture;

  const MonthlyNewExpense({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
    required this.frequency,
    required this.rememberedForFuture,
  });
}

class MonthlySmartPlan {
  final BudgetDraft draft;
  final List<MonthlyPlanItem> expectedItems;
  final List<MonthlyNewExpense> newExpenses;
  final double currentMonthIncome;
  final double currentMonthSpent;

  const MonthlySmartPlan({
    required this.draft,
    required this.expectedItems,
    required this.newExpenses,
    required this.currentMonthIncome,
    required this.currentMonthSpent,
  });

  double get expectedTotal => expectedItems.fold<double>(
        0,
        (sum, item) => sum + item.suggestion.amount,
      );

  double get plannedSpent => expectedItems.fold<double>(
        0,
        (sum, item) => sum + item.actualAmount,
      );

  double get newExpenseTotal => newExpenses.fold<double>(
        0,
        (sum, item) => sum + item.amount,
      );

  int get handledCount =>
      expectedItems.where((item) => item.isHandled).length;

  double get allowanceContext =>
      currentMonthIncome > 0 ? currentMonthIncome : draft.previousMonthIncome;
}

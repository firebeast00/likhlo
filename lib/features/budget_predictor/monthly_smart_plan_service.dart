import '../../models/expense_model.dart';
import 'budget_prediction_models.dart';
import 'budget_suggestion_engine.dart';

class MonthlySmartPlanService {
  final BudgetSuggestionEngine engine;

  MonthlySmartPlanService({
    BudgetSuggestionEngine? engine,
  }) : engine = engine ?? BudgetSuggestionEngine();

  MonthlySmartPlan build({
    required BudgetDraft draft,
    required Iterable<Expense> allTransactions,
    Set<String> excludedTransactionIds = const {},
    Set<String> rememberedPatternKeys = const {},
  }) {
    final monthExpenses = allTransactions.where(
      (entry) =>
          entry.deletedAt == null &&
          entry.type == 'expense' &&
          entry.category.trim().toLowerCase() != 'transfer' &&
          !excludedTransactionIds.contains(entry.id) &&
          _sameMonth(entry.date, draft.targetMonth),
    ).toList(growable: false);

    final groups = engine.groupExpenses(monthExpenses);
    final groupsByKey = {
      for (final group in groups)
        engine.suggestionKey(group.canonicalTitle, group.category): group,
    };

    final expected = draft.suggestions.map((suggestion) {
      final group = groupsByKey[suggestion.id];
      final actualAmount = group?.totalAmount ?? 0.0;
      final actualFrequency = group?.frequency ?? 0;

      MonthlyPlanItemStatus status;
      if (actualFrequency == 0) {
        status = MonthlyPlanItemStatus.upcoming;
      } else if (suggestion.intent == ExpenseIntent.fixedBill) {
        status = MonthlyPlanItemStatus.handled;
      } else {
        final target = suggestion.amount;
        status = target > 0 && actualAmount >= target * 0.85
            ? MonthlyPlanItemStatus.handled
            : MonthlyPlanItemStatus.inProgress;
      }

      return MonthlyPlanItem(
        suggestion: suggestion,
        status: status,
        actualAmount: actualAmount,
        actualFrequency: actualFrequency,
      );
    }).toList(growable: false);

    final expectedIds =
        draft.suggestions.map((suggestion) => suggestion.id).toSet();

    final newExpenses = groups
        .where(
          (group) => !expectedIds.contains(
            engine.suggestionKey(group.canonicalTitle, group.category),
          ),
        )
        .map((group) {
          final id = engine.suggestionKey(
            group.canonicalTitle,
            group.category,
          );
          return MonthlyNewExpense(
            id: id,
            title: group.canonicalTitle,
            category: group.category,
            amount: group.totalAmount,
            frequency: group.frequency,
            rememberedForFuture: rememberedPatternKeys.contains(id),
          );
        })
        .toList(growable: false)
      ..sort((a, b) => b.amount.compareTo(a.amount));

    var currentMonthIncome = 0.0;
    var currentMonthSpent = 0.0;
    for (final entry in allTransactions) {
      if (entry.deletedAt != null ||
          entry.category.trim().toLowerCase() == 'transfer' ||
          excludedTransactionIds.contains(entry.id) ||
          !_sameMonth(entry.date, draft.targetMonth)) {
        continue;
      }
      if (entry.type == 'income') {
        currentMonthIncome += entry.amount;
      } else if (entry.type == 'expense') {
        currentMonthSpent += entry.amount;
      }
    }

    return MonthlySmartPlan(
      draft: draft,
      expectedItems: expected,
      newExpenses: newExpenses,
      currentMonthIncome: currentMonthIncome,
      currentMonthSpent: currentMonthSpent,
    );
  }

  bool _sameMonth(DateTime value, DateTime month) =>
      value.year == month.year && value.month == month.month;
}

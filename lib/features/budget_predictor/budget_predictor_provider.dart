import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/expense_provider.dart';
import '../../services/udhar_ledger_link_service.dart';
import 'budget_prediction_models.dart';
import 'budget_suggestion_engine.dart';

final budgetSuggestionEngineProvider = Provider<BudgetSuggestionEngine>((ref) {
  return BudgetSuggestionEngine();
});

final budgetDraftProvider = Provider.family<BudgetDraft, DateTime>((ref, month) {
  final transactions = ref.watch(expenseProvider).allExpenses;
  final engine = ref.watch(budgetSuggestionEngineProvider);

  return engine.buildDraft(
    targetMonth: month,
    allTransactions: transactions,
    excludedTransactionIds: linkedUdharLedgerIds(),
  );
});

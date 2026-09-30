import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../providers/expense_provider.dart';
import '../../services/udhar_ledger_link_service.dart';
import 'budget_prediction_models.dart';
import 'budget_suggestion_engine.dart';
import 'monthly_smart_plan_service.dart';

class MonthlyPlanMemoryNotifier extends StateNotifier<Set<String>> {
  static const _storageKey = 'monthly_smart_plan_remembered_v1';
  final Box _box = Hive.box('preferences');

  MonthlyPlanMemoryNotifier() : super(const <String>{}) {
    final saved = _box.get(_storageKey);
    if (saved is List) {
      state = saved.whereType<String>().toSet();
    }
  }

  Future<void> setRemembered(String id, bool remembered) async {
    final next = {...state};
    if (remembered) {
      next.add(id);
    } else {
      next.remove(id);
    }
    state = next;
    await _box.put(_storageKey, next.toList(growable: false));
  }
}

final monthlyPlanMemoryProvider =
    StateNotifierProvider<MonthlyPlanMemoryNotifier, Set<String>>(
  (ref) => MonthlyPlanMemoryNotifier(),
);

final budgetSuggestionEngineProvider = Provider<BudgetSuggestionEngine>((ref) {
  return BudgetSuggestionEngine();
});

final budgetDraftProvider = Provider.family<BudgetDraft, DateTime>((ref, month) {
  final transactions = ref.watch(expenseProvider).allExpenses;
  final engine = ref.watch(budgetSuggestionEngineProvider);
  final remembered = ref.watch(monthlyPlanMemoryProvider);

  return engine.buildDraft(
    targetMonth: month,
    allTransactions: transactions,
    excludedTransactionIds: linkedUdharLedgerIds(),
    rememberedPatternKeys: remembered,
  );
});

final monthlySmartPlanServiceProvider = Provider<MonthlySmartPlanService>((ref) {
  return MonthlySmartPlanService(
    engine: ref.watch(budgetSuggestionEngineProvider),
  );
});

final monthlySmartPlanProvider =
    Provider.family<MonthlySmartPlan, DateTime>((ref, month) {
  final transactions = ref.watch(expenseProvider).allExpenses;
  final remembered = ref.watch(monthlyPlanMemoryProvider);
  final draft = ref.watch(budgetDraftProvider(month));
  final service = ref.watch(monthlySmartPlanServiceProvider);

  return service.build(
    draft: draft,
    allTransactions: transactions,
    excludedTransactionIds: linkedUdharLedgerIds(),
    rememberedPatternKeys: remembered,
  );
});

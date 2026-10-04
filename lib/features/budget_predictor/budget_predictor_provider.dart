import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/expense_model.dart';
import '../../providers/expense_provider.dart';
import '../../services/udhar_ledger_link_service.dart';
import 'budget_coach_engine.dart';
import 'budget_intent_parser.dart';
import 'budget_plan_preferences.dart';
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

final budgetHistoryTransactionsProvider =
    Provider.family<List<Expense>, DateTime>((ref, month) {
  final normalized = DateTime(month.year, month.month);
  final entries = <Expense>[];
  for (var offset = 1; offset <= 6; offset++) {
    final historyMonth = DateTime(
      normalized.year,
      normalized.month - offset,
    );
    final bucket = ref.watch(
      expenseProvider.select(
        (state) =>
            state.index.byMonth[LedgerIndex.monthKey(historyMonth)],
      ),
    );
    if (bucket != null) entries.addAll(bucket.transactions);
  }
  return List<Expense>.unmodifiable(entries);
});

final budgetTargetTransactionsProvider =
    Provider.family<List<Expense>, DateTime>((ref, month) {
  final normalized = DateTime(month.year, month.month);
  return ref.watch(
    expenseProvider.select(
      (state) =>
          state.index.byMonth[LedgerIndex.monthKey(normalized)]?.transactions ??
          const <Expense>[],
    ),
  );
});

final budgetDraftProvider = Provider.family<BudgetDraft, DateTime>((ref, month) {
  final history = ref.watch(budgetHistoryTransactionsProvider(month));
  final engine = ref.watch(budgetSuggestionEngineProvider);
  final remembered = ref.watch(monthlyPlanMemoryProvider);
  final oneTimePatterns = ref.watch(
    budgetPlanPreferencesProvider.select((state) => state.oneTimePatterns),
  );

  final now = DateTime.now();
  final target = DateTime(month.year, month.month);
  final current = DateTime(now.year, now.month);
  final ignoredForFuture =
      target.isAfter(current) ? oneTimePatterns : const <String>{};

  return engine.buildDraft(
    targetMonth: month,
    allTransactions: history,
    excludedTransactionIds: linkedUdharLedgerIds(),
    rememberedPatternKeys: remembered,
    ignoredPatternKeys: ignoredForFuture,
  );
});

final monthlySmartPlanServiceProvider = Provider<MonthlySmartPlanService>((ref) {
  return MonthlySmartPlanService(
    engine: ref.watch(budgetSuggestionEngineProvider),
  );
});

final monthlySmartPlanProvider =
    Provider.family<MonthlySmartPlan, DateTime>((ref, month) {
  final targetTransactions = ref.watch(budgetTargetTransactionsProvider(month));
  final remembered = ref.watch(monthlyPlanMemoryProvider);
  final draft = ref.watch(budgetDraftProvider(month));
  final service = ref.watch(monthlySmartPlanServiceProvider);

  return service.build(
    draft: draft,
    allTransactions: targetTransactions,
    excludedTransactionIds: linkedUdharLedgerIds(),
    rememberedPatternKeys: remembered,
  );
});


final budgetIntentParserProvider = Provider<BudgetIntentParser>((ref) {
  return BudgetIntentParser();
});

final budgetCoachEngineProvider = Provider<BudgetCoachEngine>((ref) {
  return BudgetCoachEngine();
});

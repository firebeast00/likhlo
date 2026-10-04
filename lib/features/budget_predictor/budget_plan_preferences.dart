import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

String budgetMonthKey(DateTime month) =>
    DateFormat('yyyy-MM').format(DateTime(month.year, month.month));

class BudgetPlanPreferences {
  final Map<String, double> savingsGoals;
  final Map<String, double> customBuffers;
  final Map<String, double> amountOverrides;
  final Set<String> excludedItems;
  final Set<String> oneTimePatterns;

  const BudgetPlanPreferences({
    this.savingsGoals = const {},
    this.customBuffers = const {},
    this.amountOverrides = const {},
    this.excludedItems = const {},
    this.oneTimePatterns = const {},
  });

  double savingsGoalFor(DateTime month) =>
      savingsGoals[budgetMonthKey(month)] ?? 0.0;

  double? customBufferFor(DateTime month) =>
      customBuffers[budgetMonthKey(month)];

  double? amountOverrideFor(DateTime month, String patternId) =>
      amountOverrides['${budgetMonthKey(month)}|$patternId'];

  bool isIncluded(DateTime month, String patternId) =>
      !excludedItems.contains('${budgetMonthKey(month)}|$patternId');

  bool isOneTime(String patternId) => oneTimePatterns.contains(patternId);

  BudgetPlanPreferences copyWith({
    Map<String, double>? savingsGoals,
    Map<String, double>? customBuffers,
    Map<String, double>? amountOverrides,
    Set<String>? excludedItems,
    Set<String>? oneTimePatterns,
  }) {
    return BudgetPlanPreferences(
      savingsGoals: savingsGoals ?? this.savingsGoals,
      customBuffers: customBuffers ?? this.customBuffers,
      amountOverrides: amountOverrides ?? this.amountOverrides,
      excludedItems: excludedItems ?? this.excludedItems,
      oneTimePatterns: oneTimePatterns ?? this.oneTimePatterns,
    );
  }
}

class BudgetPlanPreferencesNotifier
    extends StateNotifier<BudgetPlanPreferences> {
  static const _savingsKey = 'smart_budget_savings_v1';
  static const _bufferKey = 'smart_budget_buffers_v1';
  static const _amountOverridesKey = 'smart_budget_amount_overrides_v1';
  static const _excludedKey = 'smart_budget_excluded_v1';
  static const _oneTimeKey = 'smart_budget_one_time_v1';

  final Box _box = Hive.box('preferences');

  BudgetPlanPreferencesNotifier()
      : super(const BudgetPlanPreferences()) {
    state = BudgetPlanPreferences(
      savingsGoals: _readDoubleMap(_box.get(_savingsKey)),
      customBuffers: _readDoubleMap(_box.get(_bufferKey)),
      amountOverrides: _readDoubleMap(_box.get(_amountOverridesKey)),
      excludedItems: _readStringSet(_box.get(_excludedKey)),
      oneTimePatterns: _readStringSet(_box.get(_oneTimeKey)),
    );
  }

  Future<void> setSavingsGoal(DateTime month, double amount) async {
    if (!amount.isFinite || amount < 0) return;
    final next = Map<String, double>.from(state.savingsGoals);
    final key = budgetMonthKey(month);
    if (amount <= 0) {
      next.remove(key);
    } else {
      next[key] = amount;
    }
    state = state.copyWith(savingsGoals: Map.unmodifiable(next));
    await _box.put(_savingsKey, next);
  }

  Future<void> setCustomBuffer(DateTime month, double? amount) async {
    if (amount != null && (!amount.isFinite || amount < 0)) return;
    final next = Map<String, double>.from(state.customBuffers);
    final key = budgetMonthKey(month);
    if (amount == null) {
      next.remove(key);
    } else {
      next[key] = amount;
    }
    state = state.copyWith(customBuffers: Map.unmodifiable(next));
    await _box.put(_bufferKey, next);
  }

  Future<void> setAmountOverride(
    DateTime month,
    String patternId,
    double? amount,
  ) async {
    if (amount != null && (!amount.isFinite || amount < 0)) return;
    final next = Map<String, double>.from(state.amountOverrides);
    final key = '${budgetMonthKey(month)}|$patternId';
    if (amount == null) {
      next.remove(key);
    } else {
      next[key] = amount;
    }
    state = state.copyWith(amountOverrides: Map.unmodifiable(next));
    await _box.put(_amountOverridesKey, next);
  }

  Future<void> setIncluded(
    DateTime month,
    String patternId,
    bool included,
  ) async {
    final next = Set<String>.from(state.excludedItems);
    final key = '${budgetMonthKey(month)}|$patternId';
    if (included) {
      next.remove(key);
    } else {
      next.add(key);
    }
    state = state.copyWith(excludedItems: Set.unmodifiable(next));
    await _box.put(_excludedKey, next.toList(growable: false));
  }

  Future<void> setOneTime(String patternId, bool oneTime) async {
    final next = Set<String>.from(state.oneTimePatterns);
    if (oneTime) {
      next.add(patternId);
    } else {
      next.remove(patternId);
    }
    state = state.copyWith(oneTimePatterns: Set.unmodifiable(next));
    await _box.put(_oneTimeKey, next.toList(growable: false));
  }

  static Map<String, double> _readDoubleMap(dynamic raw) {
    if (raw is! Map) return const {};
    final result = <String, double>{};
    for (final entry in raw.entries) {
      if (entry.value is num) {
        result[entry.key.toString()] = (entry.value as num).toDouble();
      }
    }
    return result;
  }

  static Set<String> _readStringSet(dynamic raw) {
    if (raw is! List) return const {};
    return raw.whereType<String>().toSet();
  }
}

final budgetPlanPreferencesProvider =
    StateNotifierProvider<BudgetPlanPreferencesNotifier, BudgetPlanPreferences>(
  (ref) => BudgetPlanPreferencesNotifier(),
);

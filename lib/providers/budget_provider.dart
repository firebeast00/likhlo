import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

// State is now a Map: {"2023-10": 5000.0, "2023-11": 6000.0}
class BudgetNotifier extends StateNotifier<Map<String, double>> {
  BudgetNotifier() : super({}) {
    _loadBudgets();
  }

  void _loadBudgets() {
    final box = Hive.box('preferences');
    final saved = box.get('monthly_budgets');
    final currentMonthKey = DateFormat('yyyy-MM').format(DateTime.now());

    if (saved is Map && saved.isNotEmpty) {
      final normalized = <String, double>{};
      saved.forEach((key, value) {
        if (value is num) normalized[key.toString()] = value.toDouble();
      });
      state = normalized;
    } else {
      // 🚀 FIX: Actually SAVE the fallback to the box so Insights Engine can read it
      final rawOldLimit = box.get('limit', defaultValue: 20000.0);
      final oldLimit =
          rawOldLimit is num ? rawOldLimit.toDouble() : 20000.0;
      state = {currentMonthKey: oldLimit};
      box.put('monthly_budgets', state);
    }
  }

  Future<void> setBudget(double amount, DateTime date) async {
    if (!amount.isFinite || amount < 0) return;
    final key = DateFormat('yyyy-MM').format(date);
    final newState = Map<String, double>.from(state);
    newState[key] = amount;
    state = newState;

    final box = Hive.box('preferences');
    await box.put('monthly_budgets', newState);
  }

  // Helper to get budget for a specific month
  double getBudgetForMonth(DateTime date) {
    final key = DateFormat('yyyy-MM').format(date);
    // Return specific budget, or 0 if not set (or you could default to a base value)
    return state[key] ?? 0.0;
  }
}

final budgetProvider = StateNotifierProvider<BudgetNotifier, Map<String, double>>((ref) {
  return BudgetNotifier();
});

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
    // Load the map or default to empty
    final Map<dynamic, dynamic>? saved = box.get('monthly_budgets');
    if (saved != null) {
      state = saved.map((key, value) => MapEntry(key.toString(), value as double));
    } else {
      // Fallback for migration: try loading old single limit
      final oldLimit = box.get('limit', defaultValue: 20000.0);
      final currentMonthKey = DateFormat('yyyy-MM').format(DateTime.now());
      state = {currentMonthKey: oldLimit};
    }
  }

  Future<void> setBudget(double amount, DateTime date) async {
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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/expense_model.dart';

class ExpenseState {
  final List<Expense> allExpenses;
  ExpenseState({required this.allExpenses});
}

class ExpenseNotifier extends StateNotifier<ExpenseState> {
  final Box<Expense> _box = Hive.box<Expense>('expenses');

  ExpenseNotifier() : super(ExpenseState(allExpenses: [])) {
    _loadExpenses();
  }

  void _loadExpenses() {
    state = ExpenseState(allExpenses: _box.values.toList());
  }

  void addExpense(Expense expense) {
    _box.put(expense.id, expense);
    state = ExpenseState(allExpenses: _box.values.toList());
  }

  void editExpense(String id, Expense updated) {
    // 🚀 FIXED: Finds the exact key even for legacy entries
    final keyToEdit = _box.keys.firstWhere((k) => _box.get(k)?.id == id, orElse: () => id);
    _box.put(keyToEdit, updated);

    state = ExpenseState(allExpenses: _box.values.toList());
  }

  void deleteExpense(String id) {
    // 🚀 FIXED: Protects against old auto-incrementing integer keys
    // It searches the database for the matching ID and retrieves its true internal Hive key.
    final keyToDelete = _box.keys.firstWhere((k) => _box.get(k)?.id == id, orElse: () => null);

    if (keyToDelete != null) {
      _box.delete(keyToDelete);
    } else {
      _box.delete(id); // Fallback
    }

    // Updates the UI synchronously so Flutter knows the item is gone!
    state = ExpenseState(allExpenses: _box.values.toList());
  }
}

final expenseProvider = StateNotifierProvider<ExpenseNotifier, ExpenseState>((ref) {
  return ExpenseNotifier();
});
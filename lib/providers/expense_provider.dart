import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../models/expense_model.dart';

// 1. The State Class (Holds the list and filter status)
class ExpenseState {
  final List<Expense> allExpenses;
  final List<Expense> filteredExpenses;
  final String filterType; // 'date', 'category', 'amount'

  ExpenseState({
    this.allExpenses = const [],
    this.filteredExpenses = const [],
    this.filterType = 'date',
  });

  ExpenseState copyWith({
    List<Expense>? allExpenses,
    List<Expense>? filteredExpenses,
    String? filterType,
  }) {
    return ExpenseState(
      allExpenses: allExpenses ?? this.allExpenses,
      filteredExpenses: filteredExpenses ?? this.filteredExpenses,
      filterType: filterType ?? this.filterType,
    );
  }
}

// 2. The Notifier (The Logic)
class ExpenseNotifier extends StateNotifier<ExpenseState> {
  ExpenseNotifier() : super(ExpenseState()) {
    loadExpenses();
  }

  // Load from Hive
  void loadExpenses() {
    final box = Hive.box<Expense>('expenses');
    final expenses = box.values.toList();
    // Default sort: Date descending (newest first)
    expenses.sort((a, b) => b.date.compareTo(a.date));

    state = state.copyWith(allExpenses: expenses, filteredExpenses: expenses);
  }

  // Add Expense
  Future<void> addExpense(Expense expense) async {
    if (!expense.amount.isFinite || expense.amount <= 0) {
      throw ArgumentError('Expense amount must be greater than zero.');
    }
    final box = Hive.box<Expense>('expenses');
    await box.add(expense);
    loadExpenses();
  }

  // Edit Expense (New Feature)
  // Edit Expense (Upgraded to preserve database index)
  Future<void> editExpense(String id, Expense updatedExpense) async {
    final box = Hive.box<Expense>('expenses');

    if (!updatedExpense.amount.isFinite || updatedExpense.amount <= 0) {
      throw ArgumentError('Expense amount must be greater than zero.');
    }
    final matches = box.values.where((expense) => expense.id == id);
    if (matches.isEmpty) {
      throw StateError('Expense was not found.');
    }
    final expenseToEdit = matches.first;
    await box.put(expenseToEdit.key, updatedExpense);

    loadExpenses(); // Reload to update Riverpod state
  }

  // Delete Expense
  Future<void> deleteExpense(String id) async {
    final box = Hive.box<Expense>('expenses');
    final matches = box.values.where((expense) => expense.id == id);
    if (matches.isEmpty) return;
    await matches.first.delete();
    loadExpenses();
  }

  // Filter Logic (History)
  void sortExpenses(String criteria) {
    List<Expense> sorted = List.from(state.allExpenses);

    if (criteria == 'amount') {
      sorted.sort((a, b) => b.amount.compareTo(a.amount)); // High to Low
    } else if (criteria == 'category') {
      sorted.sort((a, b) => a.category.compareTo(b.category)); // A-Z
    } else {
      sorted.sort((a, b) => b.date.compareTo(a.date)); // Date (Default)
    }

    state = state.copyWith(filteredExpenses: sorted, filterType: criteria);
  }
}

// 3. The Provider (Global Access)
final expenseProvider = StateNotifierProvider<ExpenseNotifier, ExpenseState>((ref) {
  return ExpenseNotifier();
});
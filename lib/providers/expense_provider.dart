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

  Future<void> addExpense(Expense expense) async {
    if (!expense.amount.isFinite || expense.amount <= 0) return;
    await _box.put(expense.id, expense);
    state = ExpenseState(allExpenses: _box.values.toList());
  }

  Future<bool> editExpense(String id, Expense updated) async {
    if (!updated.amount.isFinite || updated.amount <= 0) return false;
    // 🚀 FIXED: Finds the exact key even for legacy entries
    final keyToEdit = _box.keys.cast<dynamic>().firstWhere(
      (key) => _box.get(key)?.id == id,
      orElse: () => null,
    );
    if (keyToEdit == null) return false;
    await _box.put(keyToEdit, updated);

    state = ExpenseState(allExpenses: _box.values.toList());
    return true;
  }

  Future<bool> deleteExpense(String id) async {
    // 🚀 FIXED: Protects against old auto-incrementing integer keys
    // It searches the database for the matching ID and retrieves its true internal Hive key.
    final keyToDelete = _box.keys.firstWhere((k) => _box.get(k)?.id == id, orElse: () => null);

    if (keyToDelete != null) {
      await _box.delete(keyToDelete);
    } else {
      return false;
    }

    // Updates the UI synchronously so Flutter knows the item is gone!
    state = ExpenseState(allExpenses: _box.values.toList());
    return true;
  }

  Future<void> deleteTransferPair(String transactionId) async {
    final separator = transactionId.endsWith('_out')
        ? '_out'
        : transactionId.endsWith('_in')
            ? '_in'
            : '';
    final transferId = separator.isEmpty
        ? transactionId
        : transactionId.substring(0, transactionId.length - separator.length);

    final keys = _box.keys
        .where((key) {
          final id = _box.get(key)?.id;
          return id == '${transferId}_out' || id == '${transferId}_in';
        })
        .toList();
    await _box.deleteAll(keys);
    state = ExpenseState(allExpenses: _box.values.toList());
  }

  Future<void> reassignWallet(String fromWalletId, String toWalletId) async {
    if (fromWalletId == toWalletId) return;
    final entries = _box.toMap().entries
        .where((entry) => entry.value.walletId == fromWalletId)
        .toList();

    for (final entry in entries) {
      await _box.put(
        entry.key,
        entry.value.copyWith(walletId: toWalletId),
      );
    }
    state = ExpenseState(allExpenses: _box.values.toList());
  }
}

final expenseProvider = StateNotifierProvider<ExpenseNotifier, ExpenseState>((ref) {
  return ExpenseNotifier();
});

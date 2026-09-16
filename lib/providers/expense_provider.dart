import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/expense_model.dart';
import '../models/wallet_model.dart';

class ExpenseState {
  final List<Expense> allExpenses;
  ExpenseState({required this.allExpenses});
}

class MonthlyLedgerSummary {
  final List<Expense> transactions;
  final double income;
  final double spent;

  const MonthlyLedgerSummary({
    required this.transactions,
    required this.income,
    required this.spent,
  });
}

class ExpenseNotifier extends StateNotifier<ExpenseState> {
  final Box<Expense> _box = Hive.box<Expense>('expenses');

  ExpenseNotifier() : super(ExpenseState(allExpenses: [])) {
    _loadExpenses();
  }

  List<Expense> _sortByNewest(Iterable<Expense> expenses) {
    final sorted = expenses.toList();
    sorted.sort((a, b) => b.date.compareTo(a.date));
    return sorted;
  }

  void _loadExpenses() {
    state = ExpenseState(allExpenses: _sortByNewest(_box.values));
  }

  dynamic _findKeyForId(String id) {
    if (_box.containsKey(id) && _box.get(id)?.id == id) {
      return id;
    }
    for (final key in _box.keys) {
      if (_box.get(key)?.id == id) return key;
    }
    return null;
  }

  Future<bool> addExpense(Expense expense) async {
    return addExpenses([expense]);
  }

  /// Persists related records together and emits a single UI update. Transfers
  /// use this path so the dashboard never renders a half-complete pair.
  Future<bool> addExpenses(Iterable<Expense> expenses) async {
    final additions = expenses.toList(growable: false);
    if (!isValidTransactionBatch(
      additions,
      existingIds: state.allExpenses.map((entry) => entry.id).toSet(),
    )) {
      return false;
    }
    if (!keepsWalletBalancesNonNegative(
      openingBalances: {
        for (final wallet in Hive.box<Wallet>('wallets').values)
          wallet.id: wallet.balance,
      },
      existingEntries: state.allExpenses,
      proposedEntries: additions,
    )) {
      return false;
    }

    await _box.putAll({for (final entry in additions) entry.id: entry});
    final addedIds = additions.map((entry) => entry.id).toSet();
    state = ExpenseState(
      allExpenses: _sortByNewest([
        ...state.allExpenses.where((entry) => !addedIds.contains(entry.id)),
        ...additions,
      ]),
    );
    return true;
  }

  Future<bool> editExpense(String id, Expense updated) async {
    if (!updated.amount.isFinite || updated.amount <= 0) return false;
    if (!keepsWalletBalancesNonNegative(
      openingBalances: {
        for (final wallet in Hive.box<Wallet>('wallets').values)
          wallet.id: wallet.balance,
      },
      existingEntries: state.allExpenses,
      proposedEntries: [updated],
      replacedIds: {id},
    )) {
      return false;
    }
    final keyToEdit = _findKeyForId(id);
    if (keyToEdit == null) return false;
    await _box.put(keyToEdit, updated);

    final updatedExpenses = state.allExpenses
        .map((entry) => entry.id == id ? updated : entry);
    state = ExpenseState(allExpenses: _sortByNewest(updatedExpenses));
    return true;
  }

  Future<bool> deleteExpense(String id) async {
    final keyToDelete = _findKeyForId(id);

    if (keyToDelete != null) {
      await _box.delete(keyToDelete);
    } else {
      return false;
    }

    // Updates the UI synchronously so Flutter knows the item is gone!
    state = ExpenseState(
      allExpenses:
          state.allExpenses.where((entry) => entry.id != id).toList(),
    );
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

    final keys = <dynamic>[
      _findKeyForId('${transferId}_out'),
      _findKeyForId('${transferId}_in'),
    ].where((key) => key != null).toList(growable: false);
    await _box.deleteAll(keys);
    state = ExpenseState(
      allExpenses: state.allExpenses
          .where((entry) =>
              entry.id != '${transferId}_out' &&
              entry.id != '${transferId}_in')
          .toList(),
    );
  }

  Future<void> reassignWallet(String fromWalletId, String toWalletId) async {
    if (fromWalletId == toWalletId) return;
    final entries = _box.toMap().entries
        .where((entry) => entry.value.walletId == fromWalletId)
        .toList();

    await _box.putAll({
      for (final entry in entries)
        entry.key: entry.value.copyWith(walletId: toWalletId),
    });
    state = ExpenseState(
      allExpenses: state.allExpenses
          .map((entry) => entry.walletId == fromWalletId
              ? entry.copyWith(walletId: toWalletId)
              : entry)
          .toList(),
    );
  }
}

final expenseProvider = StateNotifierProvider<ExpenseNotifier, ExpenseState>((ref) {
  return ExpenseNotifier();
});

bool keepsWalletBalancesNonNegative({
  required Map<String, double> openingBalances,
  required Iterable<Expense> existingEntries,
  required Iterable<Expense> proposedEntries,
  Set<String> replacedIds = const {},
}) {
  final proposed = proposedEntries.toList(growable: false);
  if (proposed.any((entry) => !openingBalances.containsKey(entry.walletId))) {
    return false;
  }
  final existing = existingEntries.toList(growable: false);
  final balances = Map<String, double>.from(openingBalances);
  void apply(Expense entry) {
    if (!balances.containsKey(entry.walletId)) return;
    final delta = entry.type == 'income'
        ? entry.amount
        : entry.type == 'expense'
            ? -entry.amount
            : 0.0;
    balances[entry.walletId] = balances[entry.walletId]! + delta;
  }
  for (final entry in existing) {
    if (!replacedIds.contains(entry.id)) apply(entry);
  }

  final affectedWallets = {
    ...proposed.map((entry) => entry.walletId),
    ...existing
        .where((entry) => replacedIds.contains(entry.id))
        .map((entry) => entry.walletId),
  };
  final balancesBefore = {
    for (final walletId in affectedWallets) walletId: balances[walletId]!,
  };
  for (final entry in proposed) {
    apply(entry);
  }

  const tolerance = 0.000001;
  for (final walletId in affectedWallets) {
    final before = balancesBefore[walletId]!;
    final after = balances[walletId]!;
    if (!after.isFinite) return false;
    if (replacedIds.isNotEmpty && after < -tolerance) return false;
    if (replacedIds.isEmpty) {
      if (before >= -tolerance && after < -tolerance) return false;
      if (before < -tolerance && after < before - tolerance) return false;
    }
  }
  return true;
}

bool isValidTransactionBatch(
  Iterable<Expense> entries, {
  Set<String> existingIds = const {},
}) {
  final transactions = entries.toList(growable: false);
  if (transactions.isEmpty ||
      transactions.any((entry) =>
          entry.id.trim().isEmpty ||
          !entry.amount.isFinite ||
          entry.amount <= 0 ||
          existingIds.contains(entry.id))) {
    return false;
  }
  final ids = transactions.map((entry) => entry.id).toSet();
  return ids.length == transactions.length;
}

/// Cached, single-pass monthly projection. Recomputed only when transaction
/// data changes or a different month is selected.
final monthlyLedgerProvider =
    Provider.family<MonthlyLedgerSummary, DateTime>((ref, focusedMonth) {
  final allExpenses = ref.watch(expenseProvider).allExpenses;
  final transactions = <Expense>[];
  double income = 0;
  double spent = 0;

  for (final entry in allExpenses) {
    if (entry.date.year != focusedMonth.year ||
        entry.date.month != focusedMonth.month) {
      continue;
    }

    transactions.add(entry);
    if (entry.category == 'Transfer') continue;
    if (entry.type == 'income') {
      income += entry.amount;
    } else if (entry.type == 'expense') {
      spent += entry.amount;
    }
  }

  return MonthlyLedgerSummary(
    transactions: visibleTransactions(transactions),
    income: income,
    spent: spent,
  );
});

/// Collapse only verified transfer pairs for global history; retain both in storage.
List<Expense> visibleTransactions(Iterable<Expense> entries) {
  final records = entries.toList(growable: false);
  final outgoing = {
    for (final e in records)
      if (e.category == 'Transfer' && e.id.endsWith('_out'))
        e.id.substring(0, e.id.length - 4): e,
  };
  return records.where((e) {
    if (e.category != 'Transfer' || !e.id.endsWith('_in')) return true;
    final source = outgoing[e.id.substring(0, e.id.length - 3)];
    return source == null || source.amount != e.amount ||
        source.date != e.date || source.type != 'expense' || e.type != 'income';
  }).toList(growable: false);
}


class LedgerReportSummary {
  final List<Expense> transactions;
  final int expenseCount;
  final double expenseTotal;
  final int incomeCount;
  final double incomeTotal;
  final int transferCount;
  final double transferTotal;

  const LedgerReportSummary({
    required this.transactions,
    required this.expenseCount,
    required this.expenseTotal,
    required this.incomeCount,
    required this.incomeTotal,
    required this.transferCount,
    required this.transferTotal,
  });
}

LedgerReportSummary calculateLedgerReportSummary(Iterable<Expense> entries) {
  final transactions = visibleTransactions(entries);
  var expenseCount = 0;
  var expenseTotal = 0.0;
  var incomeCount = 0;
  var incomeTotal = 0.0;
  var transferCount = 0;
  var transferTotal = 0.0;

  for (final entry in transactions) {
    final isTransfer =
        entry.category.trim().toLowerCase() == 'transfer';
    if (isTransfer) {
      transferCount++;
      transferTotal += entry.amount;
    } else if (entry.type == 'income') {
      incomeCount++;
      incomeTotal += entry.amount;
    } else if (entry.type == 'expense') {
      expenseCount++;
      expenseTotal += entry.amount;
    }
  }

  return LedgerReportSummary(
    transactions: transactions,
    expenseCount: expenseCount,
    expenseTotal: expenseTotal,
    incomeCount: incomeCount,
    incomeTotal: incomeTotal,
    transferCount: transferCount,
    transferTotal: transferTotal,
  );
}

Map<String, double> calculateWalletMovements(Iterable<Expense> entries) {
  final totals = <String, double>{};
  for (final entry in entries) {
    final delta = entry.type == 'income'
        ? entry.amount
        : entry.type == 'expense'
            ? -entry.amount
            : 0.0;
    totals.update(
      entry.walletId,
      (value) => value + delta,
      ifAbsent: () => delta,
    );
  }
  return totals;
}

final walletMovementsProvider = Provider<Map<String, double>>((ref) {
  return calculateWalletMovements(
    ref.watch(expenseProvider).allExpenses,
  );
});

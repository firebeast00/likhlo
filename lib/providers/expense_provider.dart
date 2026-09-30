import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/expense_model.dart';
import '../models/wallet_model.dart';
import '../services/udhar_ledger_link_service.dart';

class ExpenseState {
  final List<Expense> allExpenses;
  final List<Expense> deletedExpenses;
  final LedgerIndex index;

  const ExpenseState({
    required this.allExpenses,
    this.deletedExpenses = const [],
    this.index = const LedgerIndex.empty(),
  });

  List<Expense> get allRecords => [...allExpenses, ...deletedExpenses];
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

class LedgerMonthBucket {
  final List<Expense> transactions;
  final double income;
  final double spent;

  const LedgerMonthBucket({
    required this.transactions,
    required this.income,
    required this.spent,
  });
}

class LedgerIndex {
  final Map<String, Expense> byId;
  final Map<int, LedgerMonthBucket> byMonth;
  final Map<String, double> walletMovements;

  const LedgerIndex({
    required this.byId,
    required this.byMonth,
    required this.walletMovements,
  });

  const LedgerIndex.empty()
      : byId = const {},
        byMonth = const {},
        walletMovements = const {};

  static int monthKey(DateTime date) => date.year * 12 + date.month;

  LedgerMonthBucket? bucketFor(DateTime month) => byMonth[monthKey(month)];

  static LedgerIndex rebuild(
    Iterable<Expense> expenses, {
    LedgerIndex? previous,
  }) {
    final byId = <String, Expense>{};
    final monthEntries = <int, List<Expense>>{};
    final monthIncome = <int, double>{};
    final monthSpent = <int, double>{};
    final movements = <String, double>{};

    for (final entry in expenses) {
      byId[entry.id] = entry;
      final key = monthKey(entry.date);
      (monthEntries[key] ??= <Expense>[]).add(entry);

      if (entry.category != 'Transfer') {
        if (entry.type == 'income') {
          monthIncome.update(
            key,
            (value) => value + entry.amount,
            ifAbsent: () => entry.amount,
          );
        } else if (entry.type == 'expense') {
          monthSpent.update(
            key,
            (value) => value + entry.amount,
            ifAbsent: () => entry.amount,
          );
        }
      }

      final delta = entry.type == 'income'
          ? entry.amount
          : entry.type == 'expense'
              ? -entry.amount
              : 0.0;
      movements.update(
        entry.walletId,
        (value) => value + delta,
        ifAbsent: () => delta,
      );
    }

    final buckets = <int, LedgerMonthBucket>{};
    for (final item in monthEntries.entries) {
      final income = monthIncome[item.key] ?? 0.0;
      final spent = monthSpent[item.key] ?? 0.0;
      final previousBucket = previous?.byMonth[item.key];
      if (previousBucket != null &&
          previousBucket.income == income &&
          previousBucket.spent == spent &&
          _sameExpenseSequence(previousBucket.transactions, item.value)) {
        buckets[item.key] = previousBucket;
      } else {
        buckets[item.key] = LedgerMonthBucket(
          transactions: List<Expense>.unmodifiable(item.value),
          income: income,
          spent: spent,
        );
      }
    }

    final previousMovements = previous?.walletMovements;
    final stableMovements = previousMovements != null &&
            _sameDoubleMap(previousMovements, movements)
        ? previousMovements
        : Map<String, double>.unmodifiable(movements);

    return LedgerIndex(
      byId: Map<String, Expense>.unmodifiable(byId),
      byMonth: Map<int, LedgerMonthBucket>.unmodifiable(buckets),
      walletMovements: stableMovements,
    );
  }

  static bool _sameExpenseSequence(
    List<Expense> previous,
    List<Expense> next,
  ) {
    if (previous.length != next.length) return false;
    for (var i = 0; i < previous.length; i++) {
      if (!identical(previous[i], next[i])) return false;
    }
    return true;
  }

  static bool _sameDoubleMap(
    Map<String, double> previous,
    Map<String, double> next,
  ) {
    if (previous.length != next.length) return false;
    for (final entry in previous.entries) {
      if (next[entry.key] != entry.value) return false;
    }
    return true;
  }
}

class ExpenseNotifier extends StateNotifier<ExpenseState> {
  final Box<Expense> _box = Hive.box<Expense>('expenses');
  final UdharLedgerLinkService _udharLinks = const UdharLedgerLinkService();

  ExpenseNotifier() : super(const ExpenseState(allExpenses: [])) {
    _loadExpenses();
    unawaited(cleanupExpiredTrash());
  }

  bool containsAnyTransactionId(Iterable<String> ids) {
    final candidates = ids.toSet();
    if (candidates.any(state.index.byId.containsKey)) return true;
    return state.deletedExpenses.any((entry) => candidates.contains(entry.id));
  }

  Expense? findById(String id) => state.index.byId[id];

  Expense? findDeletedById(String id) {
    for (final entry in state.deletedExpenses) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  List<Expense> _sortByNewest(Iterable<Expense> expenses) {
    final sorted = expenses.toList();
    sorted.sort((a, b) => b.date.compareTo(a.date));
    return sorted;
  }

  ExpenseState _nextState({
    required List<Expense> allExpenses,
    List<Expense>? deletedExpenses,
  }) {
    return ExpenseState(
      allExpenses: allExpenses,
      deletedExpenses: deletedExpenses ?? state.deletedExpenses,
      index: LedgerIndex.rebuild(
        allExpenses,
        previous: state.index,
      ),
    );
  }

  void _loadExpenses() {
    final active = <Expense>[];
    final deleted = <Expense>[];
    for (final entry in _box.values) {
      if (entry.deletedAt == null) {
        active.add(entry);
      } else {
        deleted.add(entry);
      }
    }
    state = _nextState(
      allExpenses: _sortByNewest(active),
      deletedExpenses: _sortByNewest(deleted),
    );
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
      existingIds: state.allRecords.map((entry) => entry.id).toSet(),
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
    state = _nextState(
      allExpenses: _sortByNewest([
        ...state.allExpenses.where((entry) => !addedIds.contains(entry.id)),
        ...additions,
      ]),
      deletedExpenses: state.deletedExpenses,
    );
    return true;
  }

  Future<bool> editExpense(String id, Expense updated) async {
    if (updated.id != id || !updated.amount.isFinite || updated.amount <= 0) {
      return false;
    }
    final previous = findById(id);
    if (previous == null) return false;
    // A settlement must always reverse its original loan for the full amount.
    if (id.endsWith('_settlement') &&
        _udharLinks.find(id.substring(0, id.length - '_settlement'.length)) !=
            null &&
        (updated.amount != previous.amount ||
            updated.type != previous.type ||
            updated.walletId != previous.walletId ||
            updated.category != previous.category)) {
      return false;
    }
    final linkedDebt = _udharLinks.find(id);
    final linkedSettlement = linkedDebt == null || linkedDebt.settledAt == null
        ? null
        : findById(UdharLedgerLinkService.settlementId(id));
    final updatedSettlement = linkedSettlement?.copyWith(
      amount: updated.amount,
      type: updated.type == 'income' ? 'expense' : 'income',
      walletId: updated.walletId,
      title: updated.type == 'income'
          ? 'Udhaar repaid: ${UdharLedgerLinkService.personFromTitle(updated.title)}'
          : 'Udhaar returned: ${UdharLedgerLinkService.personFromTitle(updated.title)}',
    );
    if (!keepsWalletBalancesNonNegative(
      openingBalances: {
        for (final wallet in Hive.box<Wallet>('wallets').values)
          wallet.id: wallet.balance,
      },
      existingEntries: state.allExpenses,
      proposedEntries: [updated, if (updatedSettlement != null) updatedSettlement],
      replacedIds: {id, if (linkedSettlement != null) linkedSettlement.id},
    )) {
      return false;
    }
    final keyToEdit = _findKeyForId(id);
    if (keyToEdit == null) return false;
    await _box.putAll({
      keyToEdit: updated,
      if (updatedSettlement != null)
        _findKeyForId(updatedSettlement.id)!: updatedSettlement,
    });
    await _udharLinks.updated(updated);

    final updatedExpenses = state.allExpenses.map((entry) => entry.id == id
        ? updated
        : entry.id == updatedSettlement?.id
            ? updatedSettlement!
            : entry);
    state = _nextState(
      allExpenses: _sortByNewest(updatedExpenses),
      deletedExpenses: state.deletedExpenses,
    );
    return true;
  }

  Future<bool> deleteExpense(String id) async {
    final existing = findById(id);
    if (existing == null) return false;
    final linkedDebt = _udharLinks.find(id);
    final linkedSettlement = linkedDebt == null
        ? null
        : findById(UdharLedgerLinkService.settlementId(id));
    final ids = {id, if (linkedSettlement != null) linkedSettlement.id};
    if ((existing.type == 'income' || linkedSettlement != null) &&
        !keepsWalletBalancesNonNegative(
          openingBalances: {
            for (final wallet in Hive.box<Wallet>('wallets').values)
              wallet.id: wallet.balance,
          },
          existingEntries: state.allExpenses,
          proposedEntries: const [],
          replacedIds: ids,
        )) {
      return false;
    }
    final keyToDelete = _findKeyForId(id);
    if (keyToDelete == null) return false;
    final now = DateTime.now();
    final deleted = existing.copyWith(deletedAt: now);
    await _box.putAll({
      keyToDelete: deleted,
      if (linkedSettlement != null)
        _findKeyForId(linkedSettlement.id)!:
            linkedSettlement.copyWith(deletedAt: now),
    });
    await _udharLinks.deleted(id, now);
    state = _nextState(
      allExpenses: state.allExpenses
          .where((entry) => !ids.contains(entry.id)).toList(),
      deletedExpenses: _sortByNewest([
        ...state.deletedExpenses.where((entry) => !ids.contains(entry.id)),
        deleted,
        if (linkedSettlement != null)
          linkedSettlement.copyWith(deletedAt: now),
      ]),
    );
    return true;
  }

  Future<bool> deleteTransferPair(String transactionId) async {
    final separator = transactionId.endsWith('_out')
        ? '_out'
        : transactionId.endsWith('_in')
            ? '_in'
            : '';
    final transferId = separator.isEmpty
        ? transactionId
        : transactionId.substring(0, transactionId.length - separator.length);

    final ids = {'${transferId}_out', '${transferId}_in'};
    final timestamp = DateTime.now();
    final records = state.allExpenses
        .where((entry) => ids.contains(entry.id))
        .map((entry) => entry.copyWith(deletedAt: timestamp))
        .toList(growable: false);
    if (records.length != 2) return false;
    await _box.putAll({for (final entry in records) entry.id: entry});
    state = _nextState(
      allExpenses: state.allExpenses
          .where((entry) => !ids.contains(entry.id))
          .toList(),
      deletedExpenses: _sortByNewest([
        ...state.deletedExpenses.where((entry) => !ids.contains(entry.id)),
        ...records,
      ]),
    );
    return true;
  }

  Future<bool> restoreExpense(String id) async {
    final deleted = findDeletedById(id);
    if (deleted == null) return false;
    if (id.endsWith('_settlement') &&
        findDeletedById(id.substring(0, id.length - '_settlement'.length)) !=
            null) {
      return false;
    }
    if (!Hive.box<Wallet>('wallets').containsKey(deleted.walletId)) return false;
    final restored = deleted.copyWith(clearDeletedAt: true);
    final linkedDebt = _udharLinks.find(id);
    final deletedSettlement = linkedDebt == null
        ? null
        : findDeletedById(UdharLedgerLinkService.settlementId(id));
    final restoredSettlement = deletedSettlement?.copyWith(clearDeletedAt: true);
    if (restoredSettlement != null &&
        !Hive.box<Wallet>('wallets').containsKey(restoredSettlement.walletId)) {
      return false;
    }
    final restoredEntries = [
      restored,
      if (restoredSettlement != null) restoredSettlement,
    ];
    if (!keepsWalletBalancesNonNegative(
      openingBalances: {
        for (final wallet in Hive.box<Wallet>('wallets').values)
          wallet.id: wallet.balance,
      },
      existingEntries: state.allExpenses,
      proposedEntries: restoredEntries,
    )) {
      return false;
    }
    await _box.putAll({for (final entry in restoredEntries) entry.id: entry});
    await _udharLinks.restored(id);
    state = _nextState(
      allExpenses: _sortByNewest([...state.allExpenses, ...restoredEntries]),
      deletedExpenses:
          state.deletedExpenses
              .where((entry) => !restoredEntries.any((item) => item.id == entry.id))
              .toList(),
    );
    return true;
  }

  Future<bool> restoreTransferPair(String transactionId) async {
    final transferId = transactionId.endsWith('_out')
        ? transactionId.substring(0, transactionId.length - 4)
        : transactionId.endsWith('_in')
            ? transactionId.substring(0, transactionId.length - 3)
            : transactionId;
    final ids = {'${transferId}_out', '${transferId}_in'};
    final pair = state.deletedExpenses
        .where((entry) => ids.contains(entry.id))
        .toList(growable: false);
    if (pair.length != 2 ||
        pair.any(
          (entry) => !Hive.box<Wallet>('wallets').containsKey(entry.walletId),
        ) ||
        !keepsWalletBalancesNonNegative(
          openingBalances: {
            for (final wallet in Hive.box<Wallet>('wallets').values)
              wallet.id: wallet.balance,
          },
          existingEntries: state.allExpenses,
          proposedEntries: pair,
        )) {
      return false;
    }
    final restored =
        pair.map((entry) => entry.copyWith(clearDeletedAt: true)).toList();
    await _box.putAll({for (final entry in restored) entry.id: entry});
    state = _nextState(
      allExpenses: _sortByNewest([...state.allExpenses, ...restored]),
      deletedExpenses:
          state.deletedExpenses.where((entry) => !ids.contains(entry.id)).toList(),
    );
    return true;
  }

  Future<bool> permanentlyDelete(String id) async {
    final deleted = findDeletedById(id);
    if (deleted == null) return false;
    if (id.endsWith('_settlement') &&
        findDeletedById(id.substring(0, id.length - '_settlement'.length)) !=
            null) {
      return false;
    }
    final transferId = deleted.category == 'Transfer'
        ? (id.endsWith('_out')
            ? id.substring(0, id.length - 4)
            : id.endsWith('_in')
                ? id.substring(0, id.length - 3)
                : id)
        : null;
    final ids = transferId == null
        ? {id}
        : {'${transferId}_out', '${transferId}_in'};
    if (_udharLinks.find(id) != null &&
        findDeletedById(UdharLedgerLinkService.settlementId(id)) != null) {
      ids.add(UdharLedgerLinkService.settlementId(id));
    }
    final keys = ids.map(_findKeyForId).where((key) => key != null).toList();
    await _box.deleteAll(keys);
    await _udharLinks.permanentlyDeleted(id);
    state = _nextState(
      allExpenses: state.allExpenses,
      deletedExpenses:
          state.deletedExpenses.where((entry) => !ids.contains(entry.id)).toList(),
    );
    return true;
  }

  Future<void> emptyTrash() async {
    final deletedIds = state.deletedExpenses.map((entry) => entry.id).toList();
    final keys = state.deletedExpenses
        .map((entry) => _findKeyForId(entry.id))
        .where((key) => key != null)
        .toList(growable: false);
    await _box.deleteAll(keys);
    for (final id in deletedIds) {
      await _udharLinks.permanentlyDeleted(id);
    }
    state = _nextState(allExpenses: state.allExpenses, deletedExpenses: const []);
  }

  Future<void> cleanupExpiredTrash({
    Duration retention = const Duration(days: 30),
  }) async {
    final cutoff = DateTime.now().subtract(retention);
    final expiredIds = <String>{};
    for (final entry in state.deletedExpenses) {
      if (!(entry.deletedAt?.isBefore(cutoff) ?? false)) continue;
      if (entry.category != 'Transfer') {
        expiredIds.add(entry.id);
        continue;
      }
      final transferId = entry.id.endsWith('_out')
          ? entry.id.substring(0, entry.id.length - 4)
          : entry.id.endsWith('_in')
              ? entry.id.substring(0, entry.id.length - 3)
              : entry.id;
      expiredIds.addAll({'${transferId}_out', '${transferId}_in'});
    }
    if (expiredIds.isEmpty) return;

    final keys = expiredIds
        .map(_findKeyForId)
        .where((key) => key != null)
        .toList(growable: false);
    await _box.deleteAll(keys);
    for (final id in expiredIds) {
      await _udharLinks.permanentlyDeleted(id);
    }
    state = _nextState(
      allExpenses: state.allExpenses,
      deletedExpenses: state.deletedExpenses
          .where((entry) => !expiredIds.contains(entry.id))
          .toList(growable: false),
    );
  }

  Future<void> reassignWallet(String fromWalletId, String toWalletId) async {
    if (fromWalletId == toWalletId) return;
    final entries = _box
        .toMap()
        .entries
        .where((entry) => entry.value.walletId == fromWalletId)
        .toList();

    await _box.putAll({
      for (final entry in entries)
        entry.key: entry.value.copyWith(walletId: toWalletId),
    });
    await _udharLinks.reassignWallet(fromWalletId, toWalletId);
    state = _nextState(
      allExpenses: state.allExpenses
          .map((entry) => entry.walletId == fromWalletId
              ? entry.copyWith(walletId: toWalletId)
              : entry)
          .toList(),
      deletedExpenses: state.deletedExpenses
          .map((entry) => entry.walletId == fromWalletId
              ? entry.copyWith(walletId: toWalletId)
              : entry)
          .toList(),
    );
  }

}

final expenseProvider =
    StateNotifierProvider<ExpenseNotifier, ExpenseState>((ref) {
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

/// Month-scoped ledger projection backed by the cached ledger index.
/// Unrelated months keep the same bucket identity, so Riverpod can skip
/// rebuilding consumers that are focused on an unchanged month.
final monthlyLedgerProvider =
    Provider.family<MonthlyLedgerSummary, DateTime>((ref, focusedMonth) {
  final key = LedgerIndex.monthKey(focusedMonth);
  final bucket = ref.watch(
    expenseProvider.select((state) => state.index.byMonth[key]),
  );
  if (bucket == null) {
    return const MonthlyLedgerSummary(
      transactions: [],
      income: 0,
      spent: 0,
    );
  }

  final linkedUdhaarIds = linkedUdharLedgerIds();
  var income = bucket.income;
  var spent = bucket.spent;
  if (linkedUdhaarIds.isNotEmpty) {
    for (final entry in bucket.transactions) {
      if (!linkedUdhaarIds.contains(entry.id) ||
          entry.category == 'Transfer') {
        continue;
      }
      if (entry.type == 'income') {
        income -= entry.amount;
      } else if (entry.type == 'expense') {
        spent -= entry.amount;
      }
    }
  }

  return MonthlyLedgerSummary(
    transactions: visibleTransactions(bucket.transactions),
    income: income,
    spent: spent,
  );
});

final ledgerIndexProvider = Provider<LedgerIndex>((ref) {
  return ref.watch(expenseProvider.select((state) => state.index));
});

final activeTransactionCountProvider = Provider<int>((ref) {
  return ref.watch(
    expenseProvider.select((state) => state.index.byId.length),
  );
});

final walletMovementProvider =
    Provider.family<double, String>((ref, walletId) {
  return ref.watch(
    expenseProvider.select(
      (state) => state.index.walletMovements[walletId] ?? 0.0,
    ),
  );
});

final todaySpentProvider = Provider<double>((ref) {
  final now = DateTime.now();
  final key = LedgerIndex.monthKey(now);
  final bucket = ref.watch(
    expenseProvider.select((state) => state.index.byMonth[key]),
  );
  if (bucket == null) return 0.0;

  final linkedUdhaarIds = linkedUdharLedgerIds();
  var spent = 0.0;
  for (final entry in bucket.transactions) {
    if (entry.type != 'expense' ||
        entry.category == 'Transfer' ||
        linkedUdhaarIds.contains(entry.id) ||
        entry.date.year != now.year ||
        entry.date.month != now.month ||
        entry.date.day != now.day) {
      continue;
    }
    spent += entry.amount;
  }
  return spent;
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
    return source == null ||
        source.amount != e.amount ||
        source.date != e.date ||
        source.type != 'expense' ||
        e.type != 'income';
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
  final linkedUdhaarIds = linkedUdharLedgerIds();
  var expenseCount = 0;
  var expenseTotal = 0.0;
  var incomeCount = 0;
  var incomeTotal = 0.0;
  var transferCount = 0;
  var transferTotal = 0.0;

  for (final entry in transactions) {
    if (linkedUdhaarIds.contains(entry.id)) continue;
    final isTransfer = entry.category.trim().toLowerCase() == 'transfer';
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
  return ref.watch(
    expenseProvider.select((state) => state.index.walletMovements),
  );
});

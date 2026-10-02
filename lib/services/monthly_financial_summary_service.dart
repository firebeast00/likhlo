import '../models/expense_model.dart';
import '../models/wallet_model.dart';

class WalletActivitySummary {
  final String walletId;
  final String walletName;
  final String walletType;
  final int colorValue;
  final List<Expense> entries;
  final double income;
  final double expense;
  final double transferIn;
  final double transferOut;
  final double udharIn;
  final double udharOut;

  const WalletActivitySummary({
    required this.walletId,
    required this.walletName,
    required this.walletType,
    required this.colorValue,
    required this.entries,
    required this.income,
    required this.expense,
    required this.transferIn,
    required this.transferOut,
    required this.udharIn,
    required this.udharOut,
  });

  int get entryCount => entries.length;

  double get netFlow =>
      income + transferIn + udharIn - expense - transferOut - udharOut;

  double get transferActivity => transferIn + transferOut;

  double get udharActivity => udharIn + udharOut;
}

class MonthlyFinancialSummary {
  final DateTime month;
  final List<Expense> rawTransactions;
  final List<Expense> reportTransactions;
  final double income;
  final double spent;
  final List<MapEntry<String, double>> categories;
  final List<WalletActivitySummary> walletActivity;

  const MonthlyFinancialSummary({
    required this.month,
    required this.rawTransactions,
    required this.reportTransactions,
    required this.income,
    required this.spent,
    required this.categories,
    required this.walletActivity,
  });

  double get netFlow => income - spent;

  int get transactionCount => reportTransactions.length;
}

bool isSameFinancialMonth(DateTime date, DateTime month) =>
    date.year == month.year && date.month == month.month;

MonthlyFinancialSummary buildMonthlyFinancialSummary({
  required DateTime month,
  required Iterable<Expense> transactions,
  required Iterable<Wallet> wallets,
  Set<String> linkedUdharIds = const <String>{},
}) {
  final normalizedMonth = DateTime(month.year, month.month);
  final walletList = wallets.toList(growable: false);
  final raw = transactions
      .where((entry) => isSameFinancialMonth(entry.date, normalizedMonth))
      .toList(growable: false)
    ..sort((a, b) => b.date.compareTo(a.date));

  final reportTransactions = _visibleTransactions(raw)
      .where((entry) => !linkedUdharIds.contains(entry.id))
      .toList(growable: false);

  var income = 0.0;
  var spent = 0.0;
  final categoryTotals = <String, double>{};

  for (final entry in raw) {
    if (entry.category == 'Transfer' || linkedUdharIds.contains(entry.id)) {
      continue;
    }
    if (entry.type == 'income') {
      income += entry.amount;
    } else if (entry.type == 'expense') {
      spent += entry.amount;
      categoryTotals.update(
        entry.category,
        (value) => value + entry.amount,
        ifAbsent: () => entry.amount,
      );
    }
  }

  final categories = categoryTotals.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final entriesByWallet = <String, List<Expense>>{};
  for (final entry in raw) {
    (entriesByWallet[entry.walletId] ??= <Expense>[]).add(entry);
  }

  final walletActivity = <WalletActivitySummary>[];
  for (final wallet in walletList) {
    final entries = entriesByWallet[wallet.id] ?? const <Expense>[];
    var walletIncome = 0.0;
    var walletExpense = 0.0;
    var transferIn = 0.0;
    var transferOut = 0.0;
    var udharIn = 0.0;
    var udharOut = 0.0;

    for (final entry in entries) {
      if (entry.category == 'Transfer') {
        if (entry.type == 'income') {
          transferIn += entry.amount;
        } else if (entry.type == 'expense') {
          transferOut += entry.amount;
        }
        continue;
      }

      if (linkedUdharIds.contains(entry.id)) {
        if (entry.type == 'income') {
          udharIn += entry.amount;
        } else if (entry.type == 'expense') {
          udharOut += entry.amount;
        }
        continue;
      }

      if (entry.type == 'income') {
        walletIncome += entry.amount;
      } else if (entry.type == 'expense') {
        walletExpense += entry.amount;
      }
    }

    walletActivity.add(
      WalletActivitySummary(
        walletId: wallet.id,
        walletName: wallet.name,
        walletType: wallet.walletType,
        colorValue: wallet.colorValue,
        entries: List<Expense>.unmodifiable(entries),
        income: walletIncome,
        expense: walletExpense,
        transferIn: transferIn,
        transferOut: transferOut,
        udharIn: udharIn,
        udharOut: udharOut,
      ),
    );
  }

  // Preserve entries whose wallet was removed from an old backup/legacy state.
  for (final item in entriesByWallet.entries) {
    if (walletList.any((wallet) => wallet.id == item.key)) continue;
    var walletIncome = 0.0;
    var walletExpense = 0.0;
    var transferIn = 0.0;
    var transferOut = 0.0;
    var udharIn = 0.0;
    var udharOut = 0.0;
    for (final entry in item.value) {
      if (entry.category == 'Transfer') {
        if (entry.type == 'income') {
          transferIn += entry.amount;
        } else {
          transferOut += entry.amount;
        }
      } else if (linkedUdharIds.contains(entry.id)) {
        if (entry.type == 'income') {
          udharIn += entry.amount;
        } else {
          udharOut += entry.amount;
        }
      } else if (entry.type == 'income') {
        walletIncome += entry.amount;
      } else {
        walletExpense += entry.amount;
      }
    }
    walletActivity.add(
      WalletActivitySummary(
        walletId: item.key,
        walletName: 'Legacy wallet',
        walletType: 'legacy',
        colorValue: 0xFF64748B,
        entries: List<Expense>.unmodifiable(item.value),
        income: walletIncome,
        expense: walletExpense,
        transferIn: transferIn,
        transferOut: transferOut,
        udharIn: udharIn,
        udharOut: udharOut,
      ),
    );
  }

  return MonthlyFinancialSummary(
    month: normalizedMonth,
    rawTransactions: List<Expense>.unmodifiable(raw),
    reportTransactions: List<Expense>.unmodifiable(reportTransactions),
    income: income,
    spent: spent,
    categories: List<MapEntry<String, double>>.unmodifiable(categories),
    walletActivity: List<WalletActivitySummary>.unmodifiable(walletActivity),
  );
}

List<Expense> _visibleTransactions(Iterable<Expense> entries) {
  final records = entries.toList(growable: false);
  final outgoing = {
    for (final entry in records)
      if (entry.category == 'Transfer' && entry.id.endsWith('_out'))
        entry.id.substring(0, entry.id.length - 4): entry,
  };

  return records.where((entry) {
    if (entry.category != 'Transfer' || !entry.id.endsWith('_in')) return true;
    final source = outgoing[entry.id.substring(0, entry.id.length - 3)];
    return source == null ||
        source.amount != entry.amount ||
        source.date != entry.date ||
        source.type != 'expense' ||
        entry.type != 'income';
  }).toList(growable: false);
}

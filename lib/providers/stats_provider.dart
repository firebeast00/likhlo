import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../services/monthly_financial_summary_service.dart';
import '../services/udhar_ledger_link_service.dart';
import 'expense_provider.dart';
import 'wallet_provider.dart';

class ExpenseStats {
  final DateTime selectedMonth;
  final List<double> monthlyTotals;
  final List<String> monthLabels;
  final double maxMonthTotal;
  final double totalSpent;
  final double totalIncome;
  final double netFlow;
  final List<MapEntry<String, double>> sortedCategories;
  final List<WalletActivitySummary> walletActivity;

  const ExpenseStats({
    required this.selectedMonth,
    required this.monthlyTotals,
    required this.monthLabels,
    required this.maxMonthTotal,
    required this.totalSpent,
    required this.totalIncome,
    required this.netFlow,
    required this.sortedCategories,
    required this.walletActivity,
  });
}

/// Selected-month statistics plus the six-month spending trend ending at that
/// month. Only the six cached month buckets and wallet metadata are watched.
final statsProvider = Provider.family<ExpenseStats, DateTime>((ref, month) {
  final selectedMonth = DateTime(month.year, month.month);
  final linkedUdharIds = linkedUdharLedgerIds();
  final wallets = ref.watch(walletProvider);

  final months = List<DateTime>.generate(
    6,
    (i) => DateTime(
      selectedMonth.year,
      selectedMonth.month - 5 + i,
      1,
    ),
  );

  final buckets = <LedgerMonthBucket?>[
    for (final item in months)
      ref.watch(
        expenseProvider.select(
          (state) => state.index.byMonth[LedgerIndex.monthKey(item)],
        ),
      ),
  ];

  final monthlyTotals = List<double>.filled(6, 0);
  var maxMonthTotal = 0.0;
  for (var i = 0; i < buckets.length; i++) {
    final bucket = buckets[i];
    if (bucket == null) continue;
    var spent = 0.0;
    for (final entry in bucket.transactions) {
      if (entry.type == 'expense' &&
          entry.category != 'Transfer' &&
          !linkedUdharIds.contains(entry.id)) {
        spent += entry.amount;
      }
    }
    monthlyTotals[i] = spent;
    if (spent > maxMonthTotal) maxMonthTotal = spent;
  }

  final selectedBucket = buckets.isEmpty ? null : buckets.last;
  final summary = buildMonthlyFinancialSummary(
    month: selectedMonth,
    transactions:
        selectedBucket?.transactions ?? const <dynamic>[],
    wallets: wallets,
    linkedUdharIds: linkedUdharIds,
  );

  return ExpenseStats(
    selectedMonth: selectedMonth,
    monthlyTotals: monthlyTotals,
    monthLabels: [
      for (final item in months) DateFormat.MMM().format(item),
    ],
    maxMonthTotal: maxMonthTotal,
    totalSpent: summary.spent,
    totalIncome: summary.income,
    netFlow: summary.netFlow,
    sortedCategories: summary.categories,
    walletActivity: summary.walletActivity,
  );
});

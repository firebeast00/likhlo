import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'expense_provider.dart';
import '../services/udhar_ledger_link_service.dart';

// A clean data model to hold the pre-calculated stats
class ExpenseStats {
  final List<double> monthlyTotals;
  final List<String> monthLabels;
  final double maxMonthTotal;
  final double totalSpentThisMonth;
  final List<MapEntry<String, double>> sortedCategories;

  ExpenseStats({
    required this.monthlyTotals,
    required this.monthLabels,
    required this.maxMonthTotal,
    required this.totalSpentThisMonth,
    required this.sortedCategories,
  });
}

// Watches only the six month buckets used by this screen. Transactions added
// outside this window no longer invalidate the Stats calculations.
final statsProvider = Provider<ExpenseStats>((ref) {
  final linkedUdhaarIds = linkedUdharLedgerIds();
  final now = DateTime.now();

  final months = List<DateTime>.generate(
    6,
    (i) => DateTime(now.year, now.month - 5 + i, 1),
  );
  final buckets = <LedgerMonthBucket?>[
    for (final month in months)
      ref.watch(
        expenseProvider.select(
          (state) => state.index.byMonth[LedgerIndex.monthKey(month)],
        ),
      ),
  ];

  final monthlyTotals = List<double>.filled(6, 0);
  final monthLabels = [
    for (final month in months) DateFormat.MMM().format(month),
  ];
  final categoryTotals = <String, double>{};
  var totalSpentThisMonth = 0.0;
  var maxMonthTotal = 0.0;

  for (var i = 0; i < buckets.length; i++) {
    final bucket = buckets[i];
    if (bucket == null) continue;
    for (final entry in bucket.transactions) {
      if (entry.type != 'expense' ||
          entry.category == 'Transfer' ||
          linkedUdhaarIds.contains(entry.id)) {
        continue;
      }
      monthlyTotals[i] += entry.amount;
      if (i == buckets.length - 1) {
        categoryTotals.update(
          entry.category,
          (value) => value + entry.amount,
          ifAbsent: () => entry.amount,
        );
        totalSpentThisMonth += entry.amount;
      }
    }
  }

  for (final total in monthlyTotals) {
    if (total > maxMonthTotal) maxMonthTotal = total;
  }

  final sortedCategories = categoryTotals.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return ExpenseStats(
    monthlyTotals: monthlyTotals,
    monthLabels: monthLabels,
    maxMonthTotal: maxMonthTotal,
    totalSpentThisMonth: totalSpentThisMonth,
    sortedCategories: sortedCategories,
  );
});

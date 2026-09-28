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

// The Provider that does all the math
final statsProvider = Provider<ExpenseStats>((ref) {
  final allExpenses = ref.watch(expenseProvider).allExpenses;
  final linkedUdhaarIds = linkedUdharLedgerIds();
  final now = DateTime.now();

  final monthlyTotals = List<double>.filled(6, 0);
  final monthLabels = List<String>.generate(6,
      (i) => DateFormat.MMM().format(DateTime(now.year, now.month - 5 + i, 1)));
  final categoryTotals = <String, double>{};
  double totalSpentThisMonth = 0;
  double maxMonthTotal = 0;
  final currentMonth = now.year * 12 + now.month;
  for (final e in allExpenses) {
    if (e.type != 'expense' ||
        e.category == 'Transfer' ||
        linkedUdhaarIds.contains(e.id)) continue;
    final age = currentMonth - (e.date.year * 12 + e.date.month);
    if (age < 0 || age > 5) continue;
    monthlyTotals[5 - age] += e.amount;
    if (age == 0) {
      categoryTotals.update(e.category, (v) => v + e.amount,
          ifAbsent: () => e.amount);
      totalSpentThisMonth += e.amount;
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

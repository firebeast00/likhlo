import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'expense_provider.dart';

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
  final now = DateTime.now();

  // 1. Calculate 6-Month Trend
  List<double> monthlyTotals = [];
  List<String> monthLabels = [];
  double maxMonthTotal = 0;

  for (int i = 5; i >= 0; i--) {
    final monthDate = DateTime(now.year, now.month - i, 1);
    final monthExpenses = allExpenses.where((e) =>
        e.date.month == monthDate.month &&
        e.date.year == monthDate.year &&
        e.type == 'expense' &&
        e.category != 'Transfer');
    final total = monthExpenses.fold(0.0, (sum, e) => sum + e.amount);

    monthlyTotals.add(total);
    monthLabels.add(DateFormat.MMM().format(monthDate));

    if (total > maxMonthTotal) maxMonthTotal = total;
  }

  // 2. Calculate Current Month Category Breakdown
  final currentMonthExpenses = allExpenses.where((e) =>
      e.date.month == now.month &&
      e.date.year == now.year &&
      e.type == 'expense' &&
      e.category != 'Transfer').toList();
  final Map<String, double> categoryTotals = {};
  double totalSpentThisMonth = 0;

  for (var e in currentMonthExpenses) {
    categoryTotals[e.category] = (categoryTotals[e.category] ?? 0) + e.amount;
    totalSpentThisMonth += e.amount;
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

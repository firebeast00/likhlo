import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'expense_provider.dart';
import 'budget_provider.dart';
import 'package:intl/intl.dart';

enum VelocityRiskLevel { healthy, caution, critical }

class EnhancedVelocityInsight {
  final double dailyVelocity;
  final double safeDailyCap;
  final double burnRatio; // actual / safe
  final int daysUntilBroke;
  final DateTime? predictedExhaustionDate;
  final VelocityRiskLevel riskLevel;
  final String headline;
  final String actionableAdvice;
  final double projectedSurplusDeficit;

  EnhancedVelocityInsight({
    required this.dailyVelocity,
    required this.safeDailyCap,
    required this.burnRatio,
    required this.daysUntilBroke,
    this.predictedExhaustionDate,
    required this.riskLevel,
    required this.headline,
    required this.actionableAdvice,
    required this.projectedSurplusDeficit,
  });
}

final velocityProvider = Provider<EnhancedVelocityInsight>((ref) {
  final expenseState = ref.watch(expenseProvider);
  final budgetState = ref.watch(budgetProvider);

  final now = DateTime.now();
  final monthKey = DateFormat('yyyy-MM').format(now);
  final double monthlyBudget = budgetState[monthKey] ?? 0.0;

  // 1. Current Month Overview
  final monthExpenses = expenseState.allExpenses.where(
        (e) => e.date.month == now.month && e.date.year == now.year,
  ).toList();

  final double totalSpent = monthExpenses.fold(0.0, (sum, e) => sum + e.amount);
  final double remainingBudget = monthlyBudget - totalSpent;

  final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
  final int daysRemaining = (daysInMonth - now.day) + 1; // including today

  // 2. Safe Daily Cap
  final double safeDailyCap = monthlyBudget > 0
      ? (remainingBudget > 0 ? remainingBudget / daysRemaining : 0.0)
      : 0.0;

  // 3. Outlier-Filtered 7-Day Moving Velocity
  final sevenDaysAgo = now.subtract(const Duration(days: 7));
  final recentExpenses = expenseState.allExpenses.where(
        (e) => e.date.isAfter(sevenDaysAgo) && e.date.isBefore(now.add(const Duration(days: 1))),
  ).toList();

  double spentLast7Days = 0.0;
  int activeDays = 7;

  if (recentExpenses.isNotEmpty) {
    // Exclude single extreme outlier payments (e.g. fees > 40% of entire budget)
    final filtered = monthlyBudget > 0
        ? recentExpenses.where((e) => e.amount < (monthlyBudget * 0.40)).toList()
        : recentExpenses;

    spentLast7Days = filtered.fold(0.0, (sum, e) => sum + e.amount);

    // Cold start adjustment
    final earliest = recentExpenses.map((e) => e.date).reduce((a, b) => a.isBefore(b) ? a : b);
    final daysSpan = now.difference(earliest).inDays + 1;
    activeDays = daysSpan.clamp(1, 7);
  }

  final double dailyVelocity = activeDays > 0 ? (spentLast7Days / activeDays) : 0.0;

  // 4. Evaluation & Classification
  if (monthlyBudget <= 0) {
    return EnhancedVelocityInsight(
      dailyVelocity: dailyVelocity,
      safeDailyCap: 0.0,
      burnRatio: 0.0,
      daysUntilBroke: 999,
      riskLevel: VelocityRiskLevel.healthy,
      headline: "No Budget Limit Configured",
      actionableAdvice: "Set a monthly budget on the dashboard to activate real-time velocity tracking.",
      projectedSurplusDeficit: 0.0,
    );
  }

  final double burnRatio = safeDailyCap > 0 ? (dailyVelocity / safeDailyCap) : (remainingBudget <= 0 ? 2.0 : 1.0);
  final int daysUntilBroke = dailyVelocity > 0 ? (remainingBudget / dailyVelocity).floor() : 999;
  final double projectedSurplusDeficit = remainingBudget - (dailyVelocity * daysRemaining);

  if (remainingBudget <= 0 || burnRatio > 1.3) {
    final exhaustionDays = daysUntilBroke.clamp(0, daysRemaining);
    final exhaustionDate = now.add(Duration(days: exhaustionDays));
    final double trimNeeded = dailyVelocity - safeDailyCap;

    return EnhancedVelocityInsight(
      dailyVelocity: dailyVelocity,
      safeDailyCap: safeDailyCap,
      burnRatio: burnRatio,
      daysUntilBroke: exhaustionDays,
      predictedExhaustionDate: exhaustionDate,
      riskLevel: VelocityRiskLevel.critical,
      headline: "High Spending Velocity",
      actionableAdvice: remainingBudget <= 0
          ? "Monthly limit exceeded by Rs. ${remainingBudget.abs().toStringAsFixed(0)}. Halt non-essential expenses."
          : "Reduce spending by Rs. ${trimNeeded.toStringAsFixed(0)}/day. Restrict daily spend to Rs. ${safeDailyCap.toStringAsFixed(0)}/day to last until month-end.",
      projectedSurplusDeficit: projectedSurplusDeficit,
    );
  } else if (burnRatio > 1.0) {
    return EnhancedVelocityInsight(
      dailyVelocity: dailyVelocity,
      safeDailyCap: safeDailyCap,
      burnRatio: burnRatio,
      daysUntilBroke: daysUntilBroke,
      predictedExhaustionDate: now.add(Duration(days: daysUntilBroke)),
      riskLevel: VelocityRiskLevel.caution,
      headline: "Slight Budget Pressure",
      actionableAdvice: "You are pacing slightly above target. Keep daily spend under Rs. ${safeDailyCap.toStringAsFixed(0)} to preserve a safety buffer.",
      projectedSurplusDeficit: projectedSurplusDeficit,
    );
  }

  return EnhancedVelocityInsight(
    dailyVelocity: dailyVelocity,
    safeDailyCap: safeDailyCap,
    burnRatio: burnRatio,
    daysUntilBroke: daysUntilBroke,
    riskLevel: VelocityRiskLevel.healthy,
    headline: "Optimal Spending Velocity",
    actionableAdvice: "Pacing is sustainable. You are on track to save ~Rs. ${projectedSurplusDeficit.toStringAsFixed(0)} this month.",
    projectedSurplusDeficit: projectedSurplusDeficit,
  );
});
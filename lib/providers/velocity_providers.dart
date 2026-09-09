import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'expense_provider.dart';
import 'budget_provider.dart';
import '../services/time_series_engine.dart';

// 🚀 RESTORED: The Enum your UI relies on
enum VelocityRiskLevel { healthy, caution, critical }

// 🚀 RESTORED: The Model your Insights Screen relies on
class EnhancedVelocityInsight {
  final double dailyVelocity;
  final double safeDailyCap;
  final double burnRatio;
  final int daysUntilBroke;
  final VelocityRiskLevel riskLevel;
  final String headline;
  final String actionableAdvice;
  final double projectedSurplusDeficit;

  EnhancedVelocityInsight({
    required this.dailyVelocity,
    required this.safeDailyCap,
    required this.burnRatio,
    required this.daysUntilBroke,
    required this.riskLevel,
    required this.headline,
    required this.actionableAdvice,
    required this.projectedSurplusDeficit,
  });
}

// 1. The Advanced Time Series Engine (Used by the AI Chatbot)
final timeSeriesForecastProvider = Provider<VelocityForecast>((ref) {
  final expenses = ref.watch(expenseProvider).allExpenses;
  final budgets = ref.watch(budgetProvider);

  final now = DateTime.now();
  final monthKey = DateFormat('yyyy-MM').format(now);

  final double baseBudget = budgets[monthKey] ?? 0.0;
  final double totalIncome = expenses
      .where((e) => e.date.month == now.month && e.date.year == now.year && e.type == 'income' && e.category != 'Transfer')
      .fold(0.0, (sum, e) => sum + e.amount);

  final double effectiveBudget = baseBudget + totalIncome;

  final monthlyExpenses = expenses
      .where((e) => e.date.month == now.month && e.date.year == now.year)
      .toList();

  return TimeSeriesEngine.generateForecast(
    monthlyExpenses: monthlyExpenses,
    monthlyBudget: effectiveBudget,
    focusedMonth: now,
  );
});

// 2. 🚀 THE BRIDGE: Packages the Time Series math for your UI Screens
final velocityProvider = Provider<EnhancedVelocityInsight>((ref) {
  final forecast = ref.watch(timeSeriesForecastProvider);
  final expenses = ref.watch(expenseProvider).allExpenses;
  final budgets = ref.watch(budgetProvider);

  final now = DateTime.now();
  final monthKey = DateFormat('yyyy-MM').format(now);

  // Calculate Budgets
  final double baseBudget = budgets[monthKey] ?? 0.0;
  final double totalIncome = expenses
      .where((e) => e.date.month == now.month && e.date.year == now.year && e.type == 'income' && e.category != 'Transfer')
      .fold(0.0, (sum, e) => sum + e.amount);
  final double effectiveBudget = baseBudget + totalIncome;

  final double globalSpent = expenses
      .where((e) => e.date.month == now.month && e.date.year == now.year && e.type == 'expense' && e.category != 'Transfer')
      .fold(0.0, (sum, e) => sum + e.amount);

  // Calculate Caps & Ratios
  final double remaining = effectiveBudget - globalSpent;
  final int daysInMonth = DateTime(now.year, now.month + 1, 0).day;
  final int daysLeft = daysInMonth - now.day > 0 ? daysInMonth - now.day : 1;

  final double safeCap = remaining > 0 ? remaining / daysLeft : 0.0;
  final double ratio = safeCap > 0 ? forecast.currentEmaVelocity / safeCap : 99.0;

  // Translate Time Series to UI Warnings
  VelocityRiskLevel risk;
  String headline;
  String advice;
  int daysToBroke = 999; // 999 acts as "Safe" in UI

  if (forecast.projectedBankruptcyDate != null) {
    risk = VelocityRiskLevel.critical;
    headline = "Critical: Bankruptcy Projected";
    advice = "Cut Rs. ${forecast.suggestedCorrection.toStringAsFixed(0)}/day immediately.";
    daysToBroke = forecast.projectedBankruptcyDate!.difference(now).inDays;
    if (daysToBroke < 0) daysToBroke = 0;
  } else if (forecast.trend == 'accelerating') {
    risk = VelocityRiskLevel.caution;
    headline = "Caution: Velocity Spiking";
    advice = "Spending is accelerating. Cut back slightly to stabilize.";
  } else {
    risk = VelocityRiskLevel.healthy;
    headline = "Velocity Stable";
    advice = "Pacing perfectly. You are on track to survive the month.";
  }

  final double surplusDeficit = effectiveBudget - forecast.predictedMonthEndSpend;

  return EnhancedVelocityInsight(
    dailyVelocity: forecast.currentEmaVelocity,
    safeDailyCap: safeCap,
    burnRatio: ratio,
    daysUntilBroke: daysToBroke,
    riskLevel: risk,
    headline: headline,
    actionableAdvice: advice,
    projectedSurplusDeficit: surplusDeficit,
  );
});
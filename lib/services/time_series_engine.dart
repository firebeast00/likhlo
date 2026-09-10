import '../models/expense_model.dart';

class VelocityForecast {
  final double currentEmaVelocity; // True daily burn rate based on recent trends
  final double predictedMonthEndSpend;
  final DateTime? projectedBankruptcyDate; // When will they hit Rs. 0?
  final double suggestedCorrection; // How much to cut daily to survive
  final String trend; // 'stable', 'accelerating', 'decelerating'

  VelocityForecast({
    required this.currentEmaVelocity,
    required this.predictedMonthEndSpend,
    this.projectedBankruptcyDate,
    required this.suggestedCorrection,
    required this.trend,
  });
}

class TimeSeriesEngine {
  /// Analyzes expenses and budget to generate a Time Series Forecast.
  /// Uses a 7-day Exponential Moving Average (EMA) to weight recent spending higher.
  static VelocityForecast generateForecast({
    required List<Expense> monthlyExpenses,
    required double monthlyBudget,
    required DateTime focusedMonth,
  }) {
    final now = DateTime.now();
    final isCurrentMonth = focusedMonth.month == now.month && focusedMonth.year == now.year;

    // Only analyze up to 'today' if we are looking at the current month
    final endDay = isCurrentMonth ? now.day : _daysInMonth(focusedMonth);
    final daysInTotal = _daysInMonth(focusedMonth);

    // 1. Group expenses by Day (Only count actual expenses, not income)
    Map<int, double> dailySpends = {};
    for (var e in monthlyExpenses.where(
      (e) => e.type == 'expense' && e.category != 'Transfer',
    )) {
      dailySpends[e.date.day] = (dailySpends[e.date.day] ?? 0) + e.amount;
    }

    if (dailySpends.isEmpty || monthlyBudget == 0) {
      return VelocityForecast(currentEmaVelocity: 0, predictedMonthEndSpend: 0, suggestedCorrection: 0, trend: 'stable');
    }

    // 2. Calculate Exponential Moving Average (EMA)
    // Alpha (Smoothing Factor): 2 / (N + 1). For a 7-day trend, alpha ≈ 0.25
    const double alpha = 0.3;
    double ema = dailySpends[1] ?? 0.0; // Start EMA with Day 1

    for (int day = 2; day <= endDay; day++) {
      double spendToday = dailySpends[day] ?? 0.0;
      ema = (spendToday * alpha) + (ema * (1 - alpha));
    }

    // 3. Compare EMA to SMA (Simple Moving Average) to detect Acceleration
    double totalSpentSoFar = dailySpends.values.fold(0.0, (a, b) => a + b);
    double sma = totalSpentSoFar / endDay;

    String trend = 'stable';
    if (ema > sma * 1.15) trend = 'accelerating'; // Spending is speeding up recently
    if (ema < sma * 0.85) trend = 'decelerating'; // User is successfully slowing down

    // 4. Project Month-End Spend
    int daysRemaining = daysInTotal - endDay;
    double predictedMonthEndSpend = totalSpentSoFar + (ema * daysRemaining);

    // 5. Calculate Bankruptcy Date (When does Remaining Budget hit 0?)
    DateTime? bankruptcyDate;
    double remainingBudget = monthlyBudget - totalSpentSoFar;

    if (ema > 0 && (remainingBudget / ema) < daysRemaining) {
      int daysUntilZero = (remainingBudget / ema).floor();
      bankruptcyDate = DateTime(focusedMonth.year, focusedMonth.month, endDay).add(Duration(days: daysUntilZero));
    }

    // 6. Suggested Correction (How much to reduce daily spend to survive)
    final calculationDays = daysRemaining > 0 ? daysRemaining : 1;
    double optimalRemainingVelocity =
        remainingBudget > 0 ? (remainingBudget / calculationDays) : 0;
    double suggestedCorrection = ema > optimalRemainingVelocity ? (ema - optimalRemainingVelocity) : 0;

    return VelocityForecast(
      currentEmaVelocity: ema,
      predictedMonthEndSpend: predictedMonthEndSpend,
      projectedBankruptcyDate: bankruptcyDate,
      suggestedCorrection: suggestedCorrection,
      trend: trend,
    );
  }

  static int _daysInMonth(DateTime date) {
    return DateTime(date.year, date.month + 1, 0).day;
  }
}

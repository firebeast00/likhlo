import 'budget_prediction_models.dart';

enum BudgetCoachInsightKind {
  positive,
  warning,
  upcoming,
  neutral,
}

class BudgetCoachInsight {
  final BudgetCoachInsightKind kind;
  final String title;
  final String message;

  const BudgetCoachInsight({
    required this.kind,
    required this.title,
    required this.message,
  });
}

class BudgetEffectiveItem {
  final MonthlyPlanItem item;
  final double plannedAmount;

  const BudgetEffectiveItem({
    required this.item,
    required this.plannedAmount,
  });
}

class BudgetCoachEngine {
  List<BudgetCoachInsight> build({
    required MonthlySmartPlan plan,
    required List<BudgetEffectiveItem> includedItems,
    required double recommendedBudget,
    required double savingsGoal,
    required double allowance,
    required DateTime targetMonth,
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final insights = <BudgetCoachInsight>[];
    final freeAfterPlan = allowance - savingsGoal - recommendedBudget;

    if (allowance > 0 && freeAfterPlan < 0) {
      insights.add(
        BudgetCoachInsight(
          kind: BudgetCoachInsightKind.warning,
          title: 'Plan is above expected income',
          message:
              'Reduce about Rs. ${freeAfterPlan.abs().toStringAsFixed(0)} or lower the savings target.',
        ),
      );
    } else if (allowance > 0 && savingsGoal > 0) {
      insights.add(
        BudgetCoachInsight(
          kind: BudgetCoachInsightKind.positive,
          title: 'Savings protected',
          message:
              'This plan keeps Rs. ${savingsGoal.toStringAsFixed(0)} aside and leaves about Rs. ${freeAfterPlan.clamp(0, double.infinity).toStringAsFixed(0)} free.',
        ),
      );
    }

    BudgetEffectiveItem? overspending;
    for (final candidate in includedItems) {
      final actual = candidate.item.actualAmount;
      final target = candidate.plannedAmount;
      if (target > 0 && actual > target * 1.15) {
        if (overspending == null ||
            actual - target >
                overspending.item.actualAmount - overspending.plannedAmount) {
          overspending = candidate;
        }
      }
    }
    if (overspending != null) {
      final extra =
          overspending.item.actualAmount - overspending.plannedAmount;
      insights.add(
        BudgetCoachInsight(
          kind: BudgetCoachInsightKind.warning,
          title: '${overspending.item.suggestion.title} is running high',
          message:
              'About Rs. ${extra.toStringAsFixed(0)} above the planned amount so far.',
        ),
      );
    }

    final upcoming = includedItems
        .where(
          (item) =>
              item.item.status == MonthlyPlanItemStatus.upcoming &&
              item.item.suggestion.expectedDay != null,
        )
        .toList(growable: false)
      ..sort(
        (a, b) => a.item.suggestion.expectedDay!
            .compareTo(b.item.suggestion.expectedDay!),
      );
    if (upcoming.isNotEmpty) {
      final first = upcoming.first;
      insights.add(
        BudgetCoachInsight(
          kind: BudgetCoachInsightKind.upcoming,
          title: 'Upcoming around day ${first.item.suggestion.expectedDay}',
          message:
              '${first.item.suggestion.title} · about Rs. ${first.plannedAmount.toStringAsFixed(0)}.',
        ),
      );
    }

    if (targetMonth.year == reference.year &&
        targetMonth.month == reference.month &&
        allowance > 0 &&
        insights.length < 2) {
      final remaining = (allowance - savingsGoal - plan.currentMonthSpent)
          .clamp(0, double.infinity)
          .toDouble();
      final lastDay = DateTime(targetMonth.year, targetMonth.month + 1, 0).day;
      final daysLeft = (lastDay - reference.day + 1).clamp(1, lastDay);
      insights.add(
        BudgetCoachInsight(
          kind: BudgetCoachInsightKind.neutral,
          title: 'Safe pace for the rest of the month',
          message:
              'About Rs. ${(remaining / daysLeft).toStringAsFixed(0)} per day from the money not reserved for savings.',
        ),
      );
    }

    if (insights.isEmpty) {
      insights.add(
        const BudgetCoachInsight(
          kind: BudgetCoachInsightKind.neutral,
          title: 'Plan is learning',
          message:
              'Keep logging normally. Likhlo will refine recurring amounts and timing from your history.',
        ),
      );
    }

    return insights.take(2).toList(growable: false);
  }
}

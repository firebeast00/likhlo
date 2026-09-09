import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/goal_model.dart';
import 'expense_provider.dart';
import 'budget_provider.dart';
import 'velocity_providers.dart'; // 🚀 NEW: Link Velocity to Goals!
import 'package:intl/intl.dart';

enum GoalStatus { completed, onTrack, atRisk, paused }

class GoalFeasibility {
  final double requiredDailySavings;
  final String recommendation;
  final double completionPercentage;
  final GoalStatus status;

  GoalFeasibility({
    required this.requiredDailySavings,
    required this.recommendation,
    required this.completionPercentage,
    required this.status,
  });
}

class GoalsNotifier extends StateNotifier<List<SmartGoal>> {
  GoalsNotifier() : super([]) {
    loadGoals();
  }

  void loadGoals() {
    if (!Hive.isBoxOpen('goals')) return;
    final box = Hive.box<SmartGoal>('goals');
    state = [...box.values.toList()];
  }

  Future<void> addGoal(SmartGoal goal) async {
    final box = Hive.box<SmartGoal>('goals');
    await box.add(goal);
    loadGoals();
  }

  Future<void> depositFunds(String id, double amount) async {
    final box = Hive.box<SmartGoal>('goals');
    final goal = box.values.firstWhere((g) => g.id == id);
    goal.savedAmount = (goal.savedAmount + amount).clamp(0.0, goal.targetAmount);
    await goal.save();
    loadGoals();
  }

  Future<void> deleteGoal(String id) async {
    final box = Hive.box<SmartGoal>('goals');
    final goal = box.values.firstWhere((g) => g.id == id);
    await goal.delete();
    loadGoals();
  }
}

final goalsProvider = StateNotifierProvider<GoalsNotifier, List<SmartGoal>>((ref) {
  return GoalsNotifier();
});

/// Evaluates goal feasibility against user's actual live Velocity and Outflow
final goalFeasibilityProvider = Provider.family<GoalFeasibility, SmartGoal>((ref, goal) {
  final expenses = ref.watch(expenseProvider).allExpenses;

  // 🚀 DYNAMIC INJECTION: The AI now reads your live burn rate!
  final velocity = ref.watch(velocityProvider);

  final now = DateTime.now();
  final daysLeft = goal.targetDate.difference(now).inDays;
  final double remainingTarget = (goal.targetAmount - goal.savedAmount);
  final double progress = (goal.savedAmount / (goal.targetAmount > 0 ? goal.targetAmount : 1.0)).clamp(0.0, 1.0);

  if (remainingTarget <= 0) {
    return GoalFeasibility(
      requiredDailySavings: 0.0,
      recommendation: "Goal completed! Funds are ready for deployment. 🎉",
      completionPercentage: 1.0,
      status: GoalStatus.completed,
    );
  }

  if (daysLeft <= 0) {
    return GoalFeasibility(
      requiredDailySavings: remainingTarget,
      recommendation: "Target date has passed. Edit the goal date to re-calibrate your plan.",
      completionPercentage: progress,
      status: GoalStatus.paused,
    );
  }

  final double dailySaveTarget = remainingTarget / daysLeft;

  // AI Category Analysis: Find where the user is wasting discretionary money
  final thirtyDaysAgo = now.subtract(const Duration(days: 30));
  final recentExpenses = expenses.where((e) => e.date.isAfter(thirtyDaysAgo));
  final Map<String, double> categorySums = {};

  for (var e in recentExpenses) {
    if (e.category != 'Bills' && e.category != 'Education' && e.category != 'Udhaar') {
      categorySums[e.category] = (categorySums[e.category] ?? 0) + e.amount;
    }
  }

  String highestCategory = "discretionary items";
  if (categorySums.isNotEmpty) {
    highestCategory = categorySums.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  // 🧠 SMART DYNAMIC LOGIC
  if (velocity.riskLevel == VelocityRiskLevel.critical) {
    return GoalFeasibility(
      requiredDailySavings: dailySaveTarget,
      recommendation: "🚨 Goal At Risk! Your monthly budget is burning too fast to save Rs. ${dailySaveTarget.toStringAsFixed(0)}/day. Halt spending on '$highestCategory' immediately to recover.",
      completionPercentage: progress,
      status: GoalStatus.atRisk,
    );
  } else if (velocity.riskLevel == VelocityRiskLevel.caution) {
    return GoalFeasibility(
      requiredDailySavings: dailySaveTarget,
      recommendation: "⚠️ Tight Margins. You need to save Rs. ${dailySaveTarget.toStringAsFixed(0)}/day, but your budget pacing is high. Try cutting '$highestCategory' expenses by 15% this week.",
      completionPercentage: progress,
      status: GoalStatus.atRisk,
    );
  } else {
    // Healthy Velocity
    final projectedSurplus = velocity.projectedSurplusDeficit;
    String healthyAdvice = "✅ Pacing perfectly! Keep setting aside Rs. ${dailySaveTarget.toStringAsFixed(0)}/day.";

    if (projectedSurplus > (dailySaveTarget * 30)) {
      healthyAdvice = "🔥 Great pacing! You are projected to have a surplus of Rs. ${projectedSurplus.toStringAsFixed(0)} this month. Consider depositing a chunk here to finish early!";
    }

    return GoalFeasibility(
      requiredDailySavings: dailySaveTarget,
      recommendation: healthyAdvice,
      completionPercentage: progress,
      status: GoalStatus.onTrack,
    );
  }
});
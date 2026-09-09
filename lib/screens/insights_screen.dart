import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../providers/velocity_providers.dart';
import '../providers/goals_providers.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart'; // 🚀 ADDED: To fetch dynamic user theme
import '../models/goal_model.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  // --- DIALOGS ---
  void _showDepositDialog(BuildContext context, WidgetRef ref, SmartGoal goal, Color primaryColor) {
    final depositCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: primaryColor.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(Icons.savings_rounded, color: primaryColor, size: 32),
            ),
            const SizedBox(height: 12),
            Text("Fund ${goal.title}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          ],
        ),
        content: TextField(
          controller: depositCtrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            hintText: "Rs. 0",
            filled: true,
            fillColor: Theme.of(context).scaffoldBackgroundColor,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              onPressed: () {
                final amt = double.tryParse(depositCtrl.text) ?? 0.0;
                if (amt > 0) {
                  ref.read(goalsProvider.notifier).depositFunds(goal.id, amt);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("✅ Rs. ${amt.toStringAsFixed(0)} added to ${goal.title}!"), backgroundColor: Colors.green));
                }
              },
              child: const Text("Confirm Deposit", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  void _showAddGoalDialog(BuildContext context, WidgetRef ref, Color primaryColor) {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    DateTime targetDate = DateTime.now().add(const Duration(days: 90));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text("Create AI Goal", style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleCtrl, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: "What are you saving for?")),
              const SizedBox(height: 12),
              TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Target Amount (Rs.)")),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(DateFormat('MMM yyyy').format(targetDate), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    GestureDetector(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: targetDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2035),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: ColorScheme.light(primary: primaryColor), // Match date picker to theme
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null) setState(() => targetDate = picked);
                      },
                      child: Icon(Icons.edit_calendar_rounded, color: primaryColor),
                    )
                  ],
                ),
              )
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () {
                final amt = double.tryParse(amountCtrl.text) ?? 0.0;
                if (titleCtrl.text.isNotEmpty && amt > 0) {
                  ref.read(goalsProvider.notifier).addGoal(SmartGoal(id: const Uuid().v4(), title: titleCtrl.text, targetAmount: amt, targetDate: targetDate));
                  Navigator.pop(ctx);
                }
              },
              child: const Text("Initialize Goal", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }

  // --- REFINED FINANCIAL HEALTH SCORE CALCULATOR ---
  int _calculateHealthScore(EnhancedVelocityInsight velocity, List<SmartGoal> goals, WidgetRef ref) {
    int score = 100;

    if (velocity.burnRatio > 1.3) score -= 35;
    else if (velocity.burnRatio > 1.0) score -= 15;

    if (goals.isNotEmpty) {
      score += 5;
      for (var goal in goals) {
        final feasibility = ref.watch(goalFeasibilityProvider(goal));
        if (feasibility.status == GoalStatus.atRisk) score -= 10;
        else if (feasibility.status == GoalStatus.completed) score += 5;
      }
    }
    return score.clamp(0, 100);
  }

  // --- DYNAMIC RANKING SYSTEM ---
  String _getRank(int score) {
    if (score >= 95) return "Rank S";
    if (score >= 85) return "Rank A";
    if (score >= 70) return "Rank B";
    if (score >= 50) return "Rank C";
    return "Rank F";
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final primaryColor = Color(settings.profileColorValue); // 🚀 DYNAMIC THEME COLOR

    final velocity = ref.watch(velocityProvider);
    final goals = ref.watch(goalsProvider);
    final expenses = ref.watch(expenseProvider).allExpenses;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final int healthScore = _calculateHealthScore(velocity, goals, ref);
    final String healthRank = _getRank(healthScore);

    // 🧠 SEMANTIC COLORS: Health state should always be intuitive regardless of user's theme choice.
    Color themeAlertColor;
    switch (velocity.riskLevel) {
      case VelocityRiskLevel.critical: themeAlertColor = Colors.red; break;
      case VelocityRiskLevel.caution: themeAlertColor = Colors.orange; break;
      case VelocityRiskLevel.healthy: themeAlertColor = Colors.green; break;
    }

    // --- CALCULATE RECENT MONEY LEAK ---
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
    final recentExpenses = expenses.where((e) => e.date.isAfter(sevenDaysAgo) && e.category != 'Bills' && e.category != 'Udhaar');
    final Map<String, double> leakMap = {};
    for (var e in recentExpenses) { leakMap[e.category] = (leakMap[e.category] ?? 0) + e.amount; }

    String topLeakCategory = "None";
    double topLeakAmount = 0.0;
    if (leakMap.isNotEmpty) {
      final topLeak = leakMap.entries.reduce((a, b) => a.value > b.value ? a : b);
      topLeakCategory = topLeak.key;
      topLeakAmount = topLeak.value;
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("AI Intelligence", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                  const Text("Telemetry & structural forecasting", style: TextStyle(color: Colors.grey, fontSize: 13)),
                  const SizedBox(height: 25),

                  // --- 1. GAMIFIED HEALTH SCORE & LEAK DETECTOR ---
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [themeAlertColor, themeAlertColor.withOpacity(0.7)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [BoxShadow(color: themeAlertColor.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Health Score", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text("$healthScore", style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
                                  const Text("/100", style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                                child: Text(healthRank, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                              )
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.grey.withOpacity(0.1)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.water_drop_rounded, color: Colors.blue.shade400, size: 16),
                                  const SizedBox(width: 4),
                                  const Expanded(
                                    child: Text("7-Day Leak", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(topLeakCategory, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              Text("Rs. ${topLeakAmount.toStringAsFixed(0)}", style: TextStyle(color: Colors.red.shade400, fontSize: 13, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 35),

                  const Text("Velocity Telemetry", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),

                  // --- 2. UPGRADED VELOCITY GRID ---
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: themeAlertColor.withOpacity(0.3), width: 1.5),
                        boxShadow: [BoxShadow(color: themeAlertColor.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 8))]
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: themeAlertColor.withOpacity(0.1), shape: BoxShape.circle),
                              child: Icon(velocity.riskLevel == VelocityRiskLevel.critical ? Icons.local_fire_department_rounded : Icons.speed_rounded, color: themeAlertColor, size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(child: Text(velocity.headline, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: themeAlertColor))),
                          ],
                        ),
                        const SizedBox(height: 20),

                        Row(
                          children: [
                            Expanded(child: _buildMetricCol("Burn Rate", "Rs. ${velocity.dailyVelocity.toStringAsFixed(0)}", "/day")),
                            Container(width: 1, height: 30, color: Colors.grey.withOpacity(0.2)),
                            Expanded(child: _buildMetricCol("Safe Cap", "Rs. ${velocity.safeDailyCap.toStringAsFixed(0)}", "/day")),
                            Container(width: 1, height: 30, color: Colors.grey.withOpacity(0.2)),
                            Expanded(child: _buildMetricCol("Zero In", "${velocity.daysUntilBroke}", " days")),
                          ],
                        ),
                        const SizedBox(height: 20),

                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: isDark ? Colors.black12 : Colors.grey.shade50, borderRadius: BorderRadius.circular(16)),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.auto_awesome_rounded, color: themeAlertColor, size: 16),
                              const SizedBox(width: 10),
                              Expanded(child: Text(velocity.actionableAdvice, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, height: 1.5, fontSize: 13, fontWeight: FontWeight.w500))),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 35),

                  // --- 3. DYNAMIC SMART GOALS SECTION ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          "Strategic Objectives",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: Icon(Icons.add_rounded, color: primaryColor, size: 20),
                        label: Text("New Target", style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 14)),
                        onPressed: () => _showAddGoalDialog(context, ref, primaryColor),
                      )
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (goals.isEmpty)
                    GestureDetector(
                      onTap: () => _showAddGoalDialog(context, ref, primaryColor),
                      child: Container(
                        padding: const EdgeInsets.all(30),
                        width: double.infinity,
                        decoration: BoxDecoration(color: primaryColor.withOpacity(0.05), borderRadius: BorderRadius.circular(24), border: Border.all(color: primaryColor.withOpacity(0.2))),
                        child: Column(
                          children: [
                            Icon(Icons.flag_circle_rounded, size: 48, color: primaryColor),
                            const SizedBox(height: 10),
                            Text("Initialize your first AI Goal", style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                      ),
                    ),

                  ...goals.map((goal) {
                    final feasibility = ref.watch(goalFeasibilityProvider(goal));
                    final double progress = (goal.savedAmount / goal.targetAmount).clamp(0.0, 1.0);

                    // 🧠 DYNAMIC THEME GOAL COLOR
                    Color goalColor = primaryColor;
                    IconData statusIcon = Icons.lightbulb_rounded;

                    if (feasibility.status == GoalStatus.atRisk) {
                      goalColor = velocity.riskLevel == VelocityRiskLevel.critical ? Colors.red : Colors.orange;
                      statusIcon = Icons.warning_amber_rounded;
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: isDark ? Colors.white10 : Colors.transparent),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 20, top: 20, right: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                    flex: 2,
                                    child: Text(goal.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18), overflow: TextOverflow.ellipsis)
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  flex: 3,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(color: goalColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text("Req: Rs. ${feasibility.requiredDailySavings.toStringAsFixed(0)}/d", style: TextStyle(color: goalColor, fontSize: 11, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ),
                                IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.grey, size: 20),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => ref.read(goalsProvider.notifier).deleteGoal(goal.id)
                                ),
                              ],
                            ),
                          ),

                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text("Rs. ${goal.savedAmount.toStringAsFixed(0)}", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: primaryColor)),
                                    Text("of Rs. ${goal.targetAmount.toStringAsFixed(0)}", style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Stack(
                                  children: [
                                    Container(height: 12, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(10))),
                                    FractionallySizedBox(
                                      widthFactor: progress,
                                      child: Container(height: 12, decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(10))),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text("Deadline: ${DateFormat('MMM yyyy').format(goal.targetDate)}", style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                  color: goalColor.withOpacity(0.05),
                                  border: Border.all(color: goalColor.withOpacity(0.3), width: 1.2),
                                  borderRadius: BorderRadius.circular(16)
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(statusIcon, size: 18, color: goalColor),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(feasibility.recommendation, style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.w600, height: 1.4))),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          Container(
                            width: double.infinity,
                            height: 55,
                            decoration: const BoxDecoration(
                              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
                            ),
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: progress >= 1.0 ? Colors.grey.shade400 : primaryColor,
                                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24))),
                                elevation: 0,
                              ),
                              icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white),
                              label: Text(progress >= 1.0 ? "Target Reached!" : "Allocate Funds", style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                              onPressed: progress >= 1.0 ? null : () => _showDepositDialog(context, ref, goal, primaryColor),
                            ),
                          )
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 50),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildMetricCol(String title, String value, String suffix) {
    return Column(
      children: [
        Text(title, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text(suffix, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w500)),
            ],
          ),
        )
      ],
    );
  }
}
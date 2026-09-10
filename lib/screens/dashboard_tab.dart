import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/budget_provider.dart';
import '../providers/expense_provider.dart';

class DashboardTab extends ConsumerWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgetState = ref.watch(budgetProvider);
    final expenseState = ref.watch(expenseProvider);

    // 1. Get Current Month Data
    final now = DateTime.now();
    final monthKey = DateFormat('yyyy-MM').format(now);
    final double monthlyBudget = budgetState[monthKey] ?? 0.0;

    // 2. Calculate Spending
    final currentMonthTransactions = expenseState.allExpenses
        .where((e) => e.date.month == now.month && e.date.year == now.year)
        .toList();

    final double totalIncome = currentMonthTransactions
        .where((item) => item.type == 'income' && item.category != 'Transfer')
        .fold(0.0, (sum, item) => sum + item.amount);
    final double effectiveBudget = monthlyBudget + totalIncome;
    final double totalSpent = currentMonthTransactions
        .where((item) => item.type == 'expense' && item.category != 'Transfer')
        .fold(0.0, (sum, item) => sum + item.amount);
    final double remaining = effectiveBudget - totalSpent;

    // 3. Health & Progress Math
    final double progress = effectiveBudget > 0
        ? (totalSpent / effectiveBudget).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final bool isOverBudget = totalSpent > effectiveBudget && effectiveBudget > 0;

    final primaryColor = Theme.of(context).primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 4. Dynamic Theme Logic
    Color cardColorStart = primaryColor;
    Color cardColorEnd = primaryColor.withOpacity(0.75);
    IconData healthIcon = Icons.account_balance_wallet_rounded;

    if (isOverBudget) {
      cardColorStart = Colors.red.shade700;
      cardColorEnd = Colors.red.shade400;
      healthIcon = Icons.warning_amber_rounded;
    } else if (progress > 0.85) {
      cardColorStart = Colors.orange.shade700;
      cardColorEnd = Colors.orange.shade400;
      healthIcon = Icons.local_fire_department_rounded;
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- HERO BUDGET CARD ---
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cardColorStart, cardColorEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(36),
              boxShadow: [
                BoxShadow(
                  color: cardColorStart.withOpacity(isDark ? 0.2 : 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today_rounded, color: Colors.white, size: 14),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('MMMM yyyy').format(now),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                          ),
                        ],
                      ),
                    ),
                    Icon(healthIcon, color: Colors.white.withOpacity(0.9), size: 28),
                  ],
                ),
                const SizedBox(height: 30),
                Text(
                  isOverBudget ? "Overspent By" : "Remaining Balance",
                  style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  "Rs. ${remaining.abs().toStringAsFixed(0)}",
                  style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.5),
                ),
                const SizedBox(height: 30),

                // --- VISUAL BURN RATE BAR ---
                if (effectiveBudget > 0) ...[
                  Stack(
                    children: [
                      Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: progress,
                        child: Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Budget + Income", style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 6),
                        Text(
                          effectiveBudget > 0 ? "Rs. ${effectiveBudget.toStringAsFixed(0)}" : "Not Set",
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 17),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text("Total Spent", style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 6),
                        Text(
                          "Rs. ${totalSpent.toStringAsFixed(0)}",
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 17),
                        ),
                      ],
                    ),
                  ],
                )
              ],
            ),
          ),

          const SizedBox(height: 40),

          // --- QUICK STATS GRID ---
          const Text("Month at a Glance", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                    context,
                    "Daily Avg",
                    "Rs. ${(totalSpent / (now.day)).toStringAsFixed(0)}",
                    Icons.analytics_rounded,
                    Colors.blue
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                    context,
                    "Transactions",
                    "${currentMonthTransactions.where((item) => item.category != 'Transfer').length}",
                    Icons.receipt_long_rounded,
                    Colors.purple
                ),
              ),
            ],
          ),
          const SizedBox(height: 40), // Bottom Padding
        ],
      ),
    );
  }

  // --- STAT CARD COMPONENT ---
  Widget _buildStatCard(BuildContext context, String title, String value, IconData icon, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: isDark ? Colors.white10 : Colors.grey.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 15,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 20),
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          ),
        ],
      ),
    );
  }
}

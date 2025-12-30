import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/budget_provider.dart';
import '../providers/expense_provider.dart';

class DashboardTab extends ConsumerWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgetState = ref.watch(budgetProvider); // This is now a Map
    final expenseState = ref.watch(expenseProvider);

    // 1. Get Current Month Key (e.g., "2024-05")
    final now = DateTime.now();
    final monthKey = DateFormat('yyyy-MM').format(now);

    // 2. Get Budget for THIS Month (Fixes ".limit" error)
    final double monthlyBudget = budgetState[monthKey] ?? 0.0;

    // 3. Calculate Total Spent Manually (Fixes "totalSpentProvider" error)
    final double totalSpent = expenseState.allExpenses
        .where((e) => e.date.month == now.month && e.date.year == now.year)
        .fold(0, (sum, item) => sum + item.amount);

    final double remaining = monthlyBudget - totalSpent;
    final primaryColor = Theme.of(context).primaryColor;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Budget Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryColor, primaryColor.withOpacity(0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withOpacity(0.4),
                  blurRadius: 15,
                  offset: const Offset(0, 10),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Remaining Balance", style: TextStyle(color: Colors.white70)),
                Text(
                  "Rs. ${remaining.toStringAsFixed(0)}",
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Monthly Budget", style: TextStyle(color: Colors.white70)),
                        Text(
                          monthlyBudget.toStringAsFixed(0),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text("Spent", style: TextStyle(color: Colors.white70)),
                        Text(
                          totalSpent.toStringAsFixed(0),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ],
                    ),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}
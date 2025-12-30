import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../providers/expense_provider.dart';
import '../models/expense_model.dart';

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  int _touchedIndex = -1; // For Pie Chart Animation
  int _touchedBarIndex = -1; // For Bar Chart Interaction

  @override
  Widget build(BuildContext context) {
    final expenseState = ref.watch(expenseProvider);
    final allExpenses = expenseState.allExpenses;
    final primaryColor = Theme.of(context).primaryColor;

    // 1. Prepare Data for 6-Month Trend
    final now = DateTime.now();
    List<double> monthlyTotals = [];
    List<String> monthLabels = [];
    double maxMonthTotal = 0;

    for (int i = 5; i >= 0; i--) {
      final monthDate = DateTime(now.year, now.month - i, 1);
      final monthExpenses = allExpenses.where((e) => e.date.month == monthDate.month && e.date.year == monthDate.year);
      final total = monthExpenses.fold(0.0, (sum, e) => sum + e.amount);

      monthlyTotals.add(total);
      monthLabels.add(DateFormat.MMM().format(monthDate));
      if (total > maxMonthTotal) maxMonthTotal = total;
    }

    // 2. Prepare Data for Current Month Pie Chart
    final currentMonthExpenses = allExpenses.where((e) => e.date.month == now.month && e.date.year == now.year).toList();
    final Map<String, double> categoryTotals = {};
    double totalSpentThisMonth = 0;

    for (var e in currentMonthExpenses) {
      categoryTotals[e.category] = (categoryTotals[e.category] ?? 0) + e.amount;
      totalSpentThisMonth += e.amount;
    }

    final sortedCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value)); // Sort highest first

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Spending Trends", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            const Text("Last 6 Months History", style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 20),

            // --- 📊 6-MONTH BAR CHART ---
            Container(
              height: 220,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))]
              ),
              child: BarChart(
                  BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: maxMonthTotal == 0 ? 100 : maxMonthTotal * 1.2, // Avoid 0 crash
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                            tooltipBgColor: primaryColor,
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              return BarTooltipItem(
                                  "Rs. ${rod.toY.toStringAsFixed(0)}",
                                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                              );
                            }
                        ),
                        touchCallback: (FlTouchEvent event, barTouchResponse) {
                          setState(() {
                            // ✅ FIX: Check event type directly
                            if (barTouchResponse != null &&
                                barTouchResponse.spot != null &&
                                event is FlTapUpEvent) {
                              _touchedBarIndex = barTouchResponse.spot!.touchedBarGroupIndex;
                            } else {
                              _touchedBarIndex = -1;
                            }
                          });
                        },
                      ),
                      titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (val, meta) {
                                  if (val.toInt() >= 0 && val.toInt() < monthLabels.length) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text(monthLabels[val.toInt()], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                                    );
                                  }
                                  return const SizedBox();
                                },
                              )
                          )
                      ),
                      borderData: FlBorderData(show: false),
                      gridData: const FlGridData(show: false),
                      barGroups: List.generate(monthlyTotals.length, (i) {
                        bool isTouched = i == _touchedBarIndex;
                        return BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: monthlyTotals[i],
                                color: isTouched ? Colors.orange : (i == 5 ? primaryColor : primaryColor.withOpacity(0.3)), // Highlight current month
                                width: 16,
                                borderRadius: BorderRadius.circular(6),
                                backDrawRodData: BackgroundBarChartRodData(show: true, toY: maxMonthTotal * 1.2, color: Colors.grey.withOpacity(0.05)),
                              )
                            ]
                        );
                      })
                  )
              ),
            ),

            const SizedBox(height: 30),

            // --- 🍩 BREAKDOWN SECTION ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("This Month", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text("Rs. ${totalSpentThisMonth.toStringAsFixed(0)}", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: primaryColor)),
              ],
            ),
            const SizedBox(height: 20),

            if (totalSpentThisMonth == 0)
              const Center(child: Padding(padding: EdgeInsets.all(40), child: Text("No data for this month", style: TextStyle(color: Colors.grey)))),

            if (totalSpentThisMonth > 0) ...[
              SizedBox(
                height: 200,
                child: PieChart(
                  PieChartData(
                    pieTouchData: PieTouchData(touchCallback: (FlTouchEvent event, pieTouchResponse) {
                      setState(() {
                        if (!event.isInterestedForInteractions || pieTouchResponse == null || pieTouchResponse.touchedSection == null) {
                          _touchedIndex = -1;
                          return;
                        }
                        _touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                      });
                    }),
                    borderData: FlBorderData(show: false),
                    sectionsSpace: 2, // Space between sections
                    centerSpaceRadius: 50, // Donut hole size
                    sections: List.generate(sortedCategories.length, (i) {
                      final isTouched = i == _touchedIndex;
                      final fontSize = isTouched ? 20.0 : 0.0; // Hide text inside chart, show only on touch
                      final radius = isTouched ? 65.0 : 55.0; // Pop out effect
                      final double percent = (sortedCategories[i].value / totalSpentThisMonth) * 100;
                      final Color color = _getCategoryColor(i);

                      return PieChartSectionData(
                        color: color,
                        value: sortedCategories[i].value,
                        title: "${percent.toStringAsFixed(0)}%",
                        radius: radius,
                        titleStyle: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold, color: Colors.white),
                        badgeWidget: isTouched ? _buildBadge(sortedCategories[i].key, color) : null,
                        badgePositionPercentageOffset: 1.3,
                      );
                    }),
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // --- 📝 LIST VIEW ---
              ...List.generate(sortedCategories.length, (i) {
                final category = sortedCategories[i].key;
                final amount = sortedCategories[i].value;
                final percent = (amount / totalSpentThisMonth);
                final color = _getCategoryColor(i);

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.withOpacity(0.05))
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                          const SizedBox(width: 12),
                          Text(category, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const Spacer(),
                          Text("${(percent * 100).toStringAsFixed(1)}%", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                          const SizedBox(width: 10),
                          Text("Rs. ${amount.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Progress Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: percent,
                          backgroundColor: color.withOpacity(0.1),
                          valueColor: AlwaysStoppedAnimation(color),
                          minHeight: 6,
                        ),
                      )
                    ],
                  ),
                );
              }),

              const SizedBox(height: 80), // Bottom padding
            ]
          ],
        ),
      ),
    );
  }

  // Helper to generate elegant badge when chart is touched
  Widget _buildBadge(String text, Color color) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [const BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  // Helper to get nice consistent colors
  Color _getCategoryColor(int index) {
    final colors = [
      const Color(0xFF3B82F6), // Blue
      const Color(0xFF10B981), // Green
      const Color(0xFFF59E0B), // Amber
      const Color(0xFFEF4444), // Red
      const Color(0xFF8B5CF6), // Purple
      const Color(0xFFEC4899), // Pink
      const Color(0xFF06B6D4), // Cyan
    ];
    return colors[index % colors.length];
  }
}
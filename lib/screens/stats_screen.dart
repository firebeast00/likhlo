import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/stats_provider.dart';
import '../providers/settings_provider.dart';

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});
  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  int _touchedIndex = -1;
  int _touchedBarIndex = -1;

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(statsProvider);
    final settings = ref.watch(settingsProvider);
    final primaryColor =
        Color(settings.profileColorValue); // 🛡️ Guaranteed theme color support
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- HEADER ---
            const Text("Spending Trends",
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5)),
            const SizedBox(height: 4),
            Text("Your financial overview for the last 6 months",
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
            const SizedBox(height: 28),

            // --- 6-MONTH BAR CHART CARD ---
            Container(
              height: 240,
              padding: const EdgeInsets.fromLTRB(20, 30, 20, 16),
              decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.grey.withValues(alpha: 0.12)),
                ),
              child: BarChart(BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: stats.maxMonthTotal == 0
                      ? 100
                      : stats.maxMonthTotal * 1.2,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                        tooltipBgColor:
                            isDark ? Colors.grey.shade800 : Colors.black87,
                        tooltipRoundedRadius: 12,
                        tooltipMargin: 8,
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          return BarTooltipItem(
                              "Rs. ${rod.toY.toStringAsFixed(0)}",
                              const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13));
                        }),
                    touchCallback: (FlTouchEvent event, barTouchResponse) {
                      setState(() {
                        if (barTouchResponse != null &&
                            barTouchResponse.spot != null &&
                            event is FlTapUpEvent) {
                          _touchedBarIndex =
                              barTouchResponse.spot!.touchedBarGroupIndex;
                        } else {
                          _touchedBarIndex = -1;
                        }
                      });
                    },
                  ),
                  titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        interval: 1,
                        getTitlesWidget: (val, meta) {
                          if (val == val.roundToDouble() &&
                              val.toInt() >= 0 &&
                              val.toInt() < stats.monthLabels.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(stats.monthLabels[val.toInt()],
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade500)),
                            );
                          }
                          return const SizedBox();
                        },
                      ))),
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                  barGroups: List.generate(stats.monthlyTotals.length, (i) {
                    bool isTouched = i == _touchedBarIndex;
                    return BarChartGroupData(x: i, barRods: [
                      BarChartRodData(
                        toY: stats.monthlyTotals[i],
                        color: isTouched
                            ? primaryColor
                            : (i == 5
                                ? primaryColor.withValues(alpha: 0.8)
                                : primaryColor.withValues(alpha: 0.25)),
                        width: 14,
                        borderRadius: BorderRadius.circular(8),
                        backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: stats.maxMonthTotal * 1.2,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.03)
                                : Colors.grey.withValues(alpha: 0.08)),
                      )
                    ]);
                  }))),
            ),
            const SizedBox(height: 36),

            // --- BREAKDOWN SECTION HEADER ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text("This Month",
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5)),
                Text("Rs. ${stats.totalSpentThisMonth.toStringAsFixed(0)}",
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: primaryColor)),
              ],
            ),
            const SizedBox(height: 8),
            Divider(color: Colors.grey.withValues(alpha: 0.15)),
            const SizedBox(height: 24),

            if (stats.totalSpentThisMonth == 0)
              Center(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Column(
                        children: [
                          Icon(Icons.pie_chart_outline_rounded,
                              size: 60,
                              color: Colors.grey.withValues(alpha: 0.3)),
                          const SizedBox(height: 12),
                          Text("No data for this month",
                              style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w500)),
                        ],
                      ))),

            if (stats.totalSpentThisMonth > 0) ...[
              // --- SLEEK DONUT CHART ---
              SizedBox(
                height: 220,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Center Text
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("Total",
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(
                            "Rs. ${stats.totalSpentThisMonth.toStringAsFixed(0)}",
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: isDark ? Colors.white : Colors.black87)),
                      ],
                    ),
                    PieChart(
                      PieChartData(
                        pieTouchData: PieTouchData(touchCallback:
                            (FlTouchEvent event, pieTouchResponse) {
                          setState(() {
                            if (!event.isInterestedForInteractions ||
                                pieTouchResponse == null ||
                                pieTouchResponse.touchedSection == null) {
                              _touchedIndex = -1;
                              return;
                            }
                            _touchedIndex = pieTouchResponse
                                .touchedSection!.touchedSectionIndex;
                          });
                        }),
                        borderData: FlBorderData(show: false),
                        sectionsSpace: 4,
                        centerSpaceRadius:
                            75, // Large center space for elegant donut look
                        sections:
                            List.generate(stats.sortedCategories.length, (i) {
                          final isTouched = i == _touchedIndex;
                          final radius = isTouched ? 28.0 : 20.0;
                          final double percent =
                              (stats.sortedCategories[i].value /
                                      stats.totalSpentThisMonth) *
                                  100;
                          final Color color =
                              _getCategoryColor(i, primaryColor);

                          return PieChartSectionData(
                            color: color,
                            value: stats.sortedCategories[i].value,
                            title: "", // Hide default titles for a cleaner look
                            radius: radius,
                            badgeWidget: isTouched
                                ? _buildBadge(stats.sortedCategories[i].key,
                                    percent, color, isDark)
                                : null,
                            badgePositionPercentageOffset: 1.6,
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // --- ELEGANT CATEGORY LIST ---
              ...List.generate(stats.sortedCategories.length, (i) {
                final category = stats.sortedCategories[i].key;
                final amount = stats.sortedCategories[i].value;
                final percent = (amount / stats.totalSpentThisMonth);
                final color = _getCategoryColor(i, primaryColor);

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.grey.withValues(alpha: 0.12)),
                    ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle)),
                          const SizedBox(width: 14),
                          Expanded(
                              child: Text(
                            category,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )),
                          Text("${(percent * 100).toStringAsFixed(1)}%",
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade500,
                                  fontSize: 13)),
                          const SizedBox(width: 12),
                          Text("Rs. ${amount.toStringAsFixed(0)}",
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 15)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: percent,
                          backgroundColor: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : color.withValues(alpha: 0.1),
                          valueColor: AlwaysStoppedAnimation(color),
                          minHeight: 6,
                        ),
                      )
                    ],
                  ),
                );
              }),
              const SizedBox(height: 80),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String text, double percent, Color color, bool isDark) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Text("$text (${percent.toStringAsFixed(0)}%)",
          style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 11,
              fontWeight: FontWeight.bold)),
    );
  }

  Color _getCategoryColor(int index, Color primaryColor) {
    // Elegant, saturated palette that works well in both light and dark modes
    final colors = [
      primaryColor, // 1st uses user's theme color
      const Color(0xFF10B981), // Emerald
      const Color(0xFFF59E0B), // Amber
      const Color(0xFFEF4444), // Red
      const Color(0xFF8B5CF6), // Violet
      const Color(0xFF06B6D4), // Cyan
      const Color(0xFFF43F5E), // Rose
      const Color(0xFF3B82F6), // Blue
    ];
    return colors[index % colors.length];
  }
}

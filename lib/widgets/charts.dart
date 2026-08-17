import 'dart:math';
import 'package:flutter/material.dart';

class TrendBarChart extends StatelessWidget {
  final Map<String, double> data;

  const TrendBarChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    // Calculate maximum value for accurate scaling
    double maxVal = data.values.isEmpty ? 0 : data.values.reduce(max);
    if (maxVal == 0) maxVal = 1; // Prevent division by zero

    final entries = data.entries.toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.withOpacity(0.12),
          ),
          boxShadow: [
            BoxShadow(
                color: isDark ? Colors.black26 : Colors.black.withOpacity(0.03),
                blurRadius: 15,
                offset: const Offset(0, 8)
            )
          ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- CHART HEADER ---
          const Text(
              "6-Month Trend",
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)
          ),
          const SizedBox(height: 4),
          Text(
              "Your recent spending history",
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13, fontWeight: FontWeight.w500)
          ),
          const SizedBox(height: 30),

          // --- BARS ROW ---
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(entries.length, (index) {
              final e = entries[index];
              final pct = e.value / maxVal;
              final isLast = index == entries.length - 1; // Highlight the current/latest month

              return Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Styled Tooltip for tap/long-press interactions
                    Tooltip(
                      message: "Rs. ${e.value.toStringAsFixed(0)}",
                      preferBelow: false,
                      verticalOffset: 12,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey.shade800 : Colors.black87,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      triggerMode: TooltipTriggerMode.tap,
                      child: Container(
                        height: 140, // Fixed total height for the chart area
                        alignment: Alignment.bottomCenter,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          // Soft background track
                          color: isDark ? Colors.white.withOpacity(0.04) : primaryColor.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: pct),
                          duration: const Duration(milliseconds: 800),
                          curve: Curves.easeOutQuart, // Smoother, fintech-style slide up
                          builder: (ctx, val, _) {
                            return FractionallySizedBox(
                              heightFactor: val == 0 ? 0.03 : val, // Ensure 0 values show a tiny nub
                              child: Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: isLast ? primaryColor : primaryColor.withOpacity(0.4),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Month Label
                    Text(
                        e.key,
                        style: TextStyle(
                            fontSize: 11,
                            color: isLast ? (isDark ? Colors.white : Colors.black87) : Colors.grey.shade500,
                            fontWeight: isLast ? FontWeight.w800 : FontWeight.bold
                        )
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
import 'dart:math';
import 'package:flutter/material.dart';

class TrendBarChart extends StatelessWidget {
  final Map<String, double> data;
  const TrendBarChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    double maxVal = data.values.isEmpty ? 0 : data.values.reduce(max);
    if (maxVal == 0) maxVal = 1;

    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("6-Month Spend Trend", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black87)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: data.entries.map((e) {
              final pct = e.value / maxVal;
              return Column(
                children: [
                  Tooltip(
                    message: "Rs. ${e.value.toStringAsFixed(0)}",
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: pct),
                      duration: const Duration(milliseconds: 1000),
                      curve: Curves.easeOutBack,
                      builder: (ctx, val, _) => Container(
                        width: 30,
                        height: max(val * 120, 4),
                        decoration: BoxDecoration(color: Theme.of(context).primaryColor, borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(e.key, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
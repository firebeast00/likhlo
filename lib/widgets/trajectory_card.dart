import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/velocity_providers.dart';

class TrajectoryCard extends ConsumerWidget {
  const TrajectoryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forecast = ref.watch(timeSeriesForecastProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (forecast.currentEmaVelocity == 0) return const SizedBox.shrink();

    // Determine colors based on trend
    Color statusColor = Colors.green;
    IconData statusIcon = Icons.trending_flat_rounded;
    String statusMessage = "Pacing well. You are on track.";

    if (forecast.projectedBankruptcyDate != null) {
      statusColor = Colors.red;
      statusIcon = Icons.trending_up_rounded;
      final dateStr = DateFormat('MMM d').format(forecast.projectedBankruptcyDate!);
      statusMessage = "Warning: Based on recent spend, you will run out on $dateStr.";
    } else if (forecast.trend == 'accelerating') {
      statusColor = Colors.orange;
      statusIcon = Icons.speed_rounded;
      statusMessage = "Spending is accelerating. Cut back Rs. ${forecast.suggestedCorrection.toStringAsFixed(0)}/day.";
    } else if (forecast.trend == 'decelerating') {
      statusColor = Colors.green;
      statusIcon = Icons.trending_down_rounded;
      statusMessage = "Great job! Your spending velocity is dropping.";
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: statusColor.withOpacity(0.2), shape: BoxShape.circle),
            child: Icon(statusIcon, color: statusColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("AI Velocity Forecast", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : Colors.black87)),
                const SizedBox(height: 4),
                Text(statusMessage, style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
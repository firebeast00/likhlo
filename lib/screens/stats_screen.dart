import '../l10n/app_strings.dart';
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app/app_action.dart';
import '../providers/settings_provider.dart';
import '../providers/stats_provider.dart';
import '../services/monthly_financial_summary_service.dart';
import '../services/audio_feedback_service.dart';
import '../widgets/month_selector_control.dart';

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  late DateTime _selectedMonth;
  int _touchedIndex = -1;
  int _touchedBarIndex = -1;
  int? _handledAppActionId;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
  }

  void _handlePendingAppAction(AppActionRequest request) {
    if (request.action != AppActionType.openStatsMonth) return;
    ref.read(appActionProvider.notifier).consume(request.id);
    if (!mounted) return;

    final requested = request.month;
    if (requested == null) return;
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    final normalized = DateTime(requested.year, requested.month);
    final target = normalized.isAfter(currentMonth) ? currentMonth : normalized;
    _changeMonth(target);
    if (request.spokenFeedback) {
      unawaited(AudioFeedbackService().announceMessage(
        'Showing ${DateFormat('MMMM yyyy').format(target)} Stats.',
      ));
    }

    if (normalized.isAfter(currentMonth)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(AppStrings.current.text('stats_are_available_through_the_current_month_b47844')),
          ),
        );
    }
  }

  void _changeMonth(DateTime value) {
    final normalized = DateTime(value.year, value.month);
    if (normalized == _selectedMonth) return;
    setState(() {
      _selectedMonth = normalized;
      _touchedIndex = -1;
      _touchedBarIndex = -1;
    });
  }

  @override
  Widget build(BuildContext context) {
    AppStrings.of(context);
    final pendingAction = ref.watch(appActionProvider);
    if (pendingAction != null &&
        pendingAction.action == AppActionType.openStatsMonth &&
        _handledAppActionId != pendingAction.id) {
      _handledAppActionId = pendingAction.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handlePendingAppAction(pendingAction);
      });
    }

    final stats = ref.watch(statsProvider(_selectedMonth));
    final settings = ref.watch(settingsProvider);
    final primaryColor = Color(settings.profileColorValue);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final monthLabel = DateFormat.yMMMM().format(_selectedMonth);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.current.text('spending_trends_2bffb9'),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              AppStrings.current.text('six_month_overview_ending_in_8ef0ef', {'p0': monthLabel}),
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.grey.withValues(alpha: 0.12),
                ),
              ),
              child: MonthSelectorControl(
                selectedMonth: _selectedMonth,
                maxMonth: DateTime.now(),
                onChanged: _changeMonth,
              ),
            ),
            const SizedBox(height: 24),
            RepaintBoundary(
              child: Container(
                height: 240,
                padding: const EdgeInsets.fromLTRB(20, 30, 20, 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.grey.withValues(alpha: 0.12),
                  ),
                ),
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY:
                        stats.maxMonthTotal == 0 ? 100 : stats.maxMonthTotal * 1.2,
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        tooltipBgColor:
                            isDark ? Colors.grey.shade800 : Colors.black87,
                        tooltipRoundedRadius: 12,
                        tooltipMargin: 8,
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          return BarTooltipItem(
                            'Rs. ${rod.toY.toStringAsFixed(0)}',
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          );
                        },
                      ),
                      touchCallback: (event, response) {
                        setState(() {
                          if (response?.spot != null && event is FlTapUpEvent) {
                            _touchedBarIndex =
                                response!.spot!.touchedBarGroupIndex;
                          } else {
                            _touchedBarIndex = -1;
                          }
                        });
                      },
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          interval: 1,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (value != index.toDouble() ||
                                index < 0 ||
                                index >= stats.monthLabels.length) {
                              return const SizedBox();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                AppStrings.current.dateLabel(stats.monthLabels[index]),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(show: false),
                    barGroups: List.generate(stats.monthlyTotals.length, (i) {
                      final isTouched = i == _touchedBarIndex;
                      return BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: stats.monthlyTotals[i],
                            color: isTouched
                                ? primaryColor
                                : i == stats.monthlyTotals.length - 1
                                    ? primaryColor.withValues(alpha: 0.8)
                                    : primaryColor.withValues(alpha: 0.25),
                            width: 14,
                            borderRadius: BorderRadius.circular(8),
                            backDrawRodData: BackgroundBarChartRodData(
                              show: true,
                              toY: stats.maxMonthTotal == 0
                                  ? 100
                                  : stats.maxMonthTotal * 1.2,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.03)
                                  : Colors.grey.withValues(alpha: 0.08),
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              monthLabel,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _summaryCard(
                  context,
                  'Income',
                  stats.totalIncome,
                  Colors.green.shade600,
                ),
                const SizedBox(width: 8),
                _summaryCard(
                  context,
                  'Spent',
                  stats.totalSpent,
                  Colors.red.shade600,
                ),
                const SizedBox(width: 8),
                _summaryCard(
                  context,
                  'Net',
                  stats.netFlow,
                  stats.netFlow >= 0
                      ? Colors.green.shade600
                      : Colors.red.shade600,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppStrings.current.text('spending_by_category_d4aadf'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                Text(
                  'Rs. ${stats.totalSpent.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Divider(color: Colors.grey.withValues(alpha: 0.15)),
            const SizedBox(height: 20),
            if (stats.totalSpent == 0)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Column(
                    children: [
                      Icon(
                        Icons.pie_chart_outline_rounded,
                        size: 56,
                        color: Colors.grey.withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        AppStrings.current.text('no_spending_data_for_cb6041', {'p0': monthLabel}),
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              RepaintBoundary(
                child: SizedBox(
                  height: 220,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            AppStrings.current.text('spent_c0d3c9'),
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Rs. ${stats.totalSpent.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      PieChart(
                        PieChartData(
                          pieTouchData: PieTouchData(
                            touchCallback: (event, response) {
                              setState(() {
                                if (!event.isInterestedForInteractions ||
                                    response?.touchedSection == null) {
                                  _touchedIndex = -1;
                                  return;
                                }
                                _touchedIndex =
                                    response!.touchedSection!.touchedSectionIndex;
                              });
                            },
                          ),
                          borderData: FlBorderData(show: false),
                          sectionsSpace: 4,
                          centerSpaceRadius: 75,
                          sections: List.generate(
                            stats.sortedCategories.length,
                            (i) {
                              final isTouched = i == _touchedIndex;
                              final amount = stats.sortedCategories[i].value;
                              final percent = amount / stats.totalSpent * 100;
                              final color =
                                  _getCategoryColor(i, primaryColor);
                              return PieChartSectionData(
                                color: color,
                                value: amount,
                                title: '',
                                radius: isTouched ? 28 : 20,
                                badgeWidget: isTouched
                                    ? _buildBadge(
                                        stats.sortedCategories[i].key,
                                        percent,
                                        color,
                                        isDark,
                                      )
                                    : null,
                                badgePositionPercentageOffset: 1.6,
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              ...List.generate(stats.sortedCategories.length, (i) {
                final category = stats.sortedCategories[i].key;
                final amount = stats.sortedCategories[i].value;
                final percent = amount / stats.totalSpent;
                final color = _getCategoryColor(i, primaryColor);
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.grey.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              AppStrings.current.display(category),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            AppStrings.current.text('_6c727a', {'p0': (percent * 100).toStringAsFixed(1)}),
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Rs. ${amount.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
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
                      ),
                    ],
                  ),
                );
              }),
            ],
            const SizedBox(height: 30),
            Text(
              AppStrings.current.text('wallet_activity_55b837'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              AppStrings.current.text('entries_and_money_movement_for_160a95', {'p0': monthLabel}),
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
            const SizedBox(height: 14),
            ...stats.walletActivity.map(
              (activity) => _walletCard(
                context,
                activity,
                isDark,
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(
    BuildContext context,
    String label,
    double value,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.current.display(label),
              style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
            ),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'Rs. ${value.toStringAsFixed(0)}',
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _walletCard(
    BuildContext context,
    WalletActivitySummary activity,
    bool isDark,
  ) {
    final color = Color(activity.colorValue);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: activity.entryCount == 0
          ? null
          : () => _showWalletEntries(activity, color),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : color.withValues(alpha: 0.15),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: color.withValues(alpha: 0.14),
                  child: Icon(
                    Icons.account_balance_wallet_rounded,
                    color: color,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activity.walletName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        AppStrings.current.text('entr_b66858', {'p0': activity.entryCount, 'p1': activity.entryCount == 1 ? 'y' : 'ies', 'p2': activity.walletType}),
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  AppStrings.current.text('net_rs_aac7a9', {'p0': activity.netFlow >= 0 ? '+' : '-', 'p1': activity.netFlow.abs().toStringAsFixed(0)}),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: activity.netFlow >= 0
                        ? Colors.green.shade600
                        : Colors.red.shade600,
                  ),
                ),
                if (activity.entryCount > 0)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.chevron_right_rounded, size: 18),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _walletMetric('Income', activity.income, Colors.green),
                _walletMetric('Expense', activity.expense, Colors.red),
                if (activity.transferActivity > 0)
                  _walletMetric(
                    'Transfers',
                    activity.transferActivity,
                    Colors.blue,
                  ),
                if (activity.udharActivity > 0)
                  _walletMetric(
                    'Udhar',
                    activity.udharActivity,
                    Colors.orange,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _walletMetric(String label, double amount, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        AppStrings.current.text('rs_0a1fb6', {'p0': label, 'p1': amount.toStringAsFixed(0)}),
        style: TextStyle(
          color: color.shade700,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  void _showWalletEntries(WalletActivitySummary activity, Color color) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.72,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: color.withValues(alpha: 0.14),
                        child: Icon(
                          Icons.account_balance_wallet_rounded,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${activity.walletName} · ${DateFormat.yMMMM().format(_selectedMonth)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                    itemCount: activity.entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = activity.entries[index];
                      final isIncome = entry.type == 'income';
                      final isTransfer = entry.category == 'Transfer';
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        leading: Icon(
                          isTransfer
                              ? Icons.swap_horiz_rounded
                              : isIncome
                                  ? Icons.south_west_rounded
                                  : Icons.north_east_rounded,
                          color: isTransfer
                              ? Colors.blue
                              : isIncome
                                  ? Colors.green
                                  : Colors.red,
                        ),
                        title: Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          "${DateFormat('dd MMM').format(entry.date)} · ${entry.category}",
                        ),
                        trailing: Text(
                          AppStrings.current.text('rs_d8aea4', {'p0': isIncome ? '+' : '-', 'p1': entry.amount.toStringAsFixed(0)}),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: isTransfer
                                ? Colors.blue
                                : isIncome
                                    ? Colors.green
                                    : Colors.red,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBadge(String text, double percent, Color color, bool isDark) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Text(
        AppStrings.current.text('_e86e71', {'p0': text, 'p1': percent.toStringAsFixed(0)}),
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _getCategoryColor(int index, Color primaryColor) {
    final colors = [
      primaryColor,
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFFEF4444),
      const Color(0xFF8B5CF6),
      const Color(0xFF06B6D4),
      const Color(0xFFF43F5E),
      const Color(0xFF3B82F6),
    ];
    return colors[index % colors.length];
  }
}

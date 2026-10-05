import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

DateTime normalizeMonth(DateTime value) => DateTime(value.year, value.month);

bool isMonthAfter(DateTime value, DateTime other) {
  final a = value.year * 12 + value.month;
  final b = other.year * 12 + other.month;
  return a > b;
}

Future<DateTime?> showMonthYearPickerDialog(
  BuildContext context, {
  required DateTime initialMonth,
  DateTime? maxMonth,
  int minimumYear = 2000,
}) async {
  final maximum = normalizeMonth(maxMonth ?? DateTime.now());
  var selectedYear = initialMonth.year.clamp(minimumYear, maximum.year).toInt();
  var selectedMonth = initialMonth.month;
  if (selectedYear == maximum.year && selectedMonth > maximum.month) {
    selectedMonth = maximum.month;
  }

  return showDialog<DateTime>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(AppStrings.current.text('select_month_4342f7')),
            content: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    value: selectedYear,
                    decoration: InputDecoration(
                      labelText: AppStrings.current.text('year_879e32'),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (var year = maximum.year; year >= minimumYear; year--)
                        DropdownMenuItem(value: year, child: Text('$year')),
                    ],
                    onChanged: (year) {
                      if (year == null) return;
                      setDialogState(() {
                        selectedYear = year;
                        if (selectedYear == maximum.year &&
                            selectedMonth > maximum.month) {
                          selectedMonth = maximum.month;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 12,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 2.2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemBuilder: (context, index) {
                      final month = index + 1;
                      final disabled =
                          selectedYear == maximum.year && month > maximum.month;
                      final selected = month == selectedMonth;
                      return ChoiceChip(
                        label: Text(
                          DateFormat.MMM().format(DateTime(2024, month)),
                        ),
                        selected: selected,
                        onSelected: disabled
                            ? null
                            : (_) => setDialogState(
                                  () => selectedMonth = month,
                                ),
                      );
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(AppStrings.current.text('cancel_77dfd2')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  DateTime(selectedYear, selectedMonth),
                ),
                child: Text(AppStrings.current.text('select_859822')),
              ),
            ],
          );
        },
      );
    },
  );
}

class MonthSelectorControl extends StatelessWidget {
  final DateTime selectedMonth;
  final ValueChanged<DateTime> onChanged;
  final DateTime? maxMonth;

  const MonthSelectorControl({
    super.key,
    required this.selectedMonth,
    required this.onChanged,
    this.maxMonth,
  });

  @override
  Widget build(BuildContext context) {
    AppStrings.of(context);
    final selected = normalizeMonth(selectedMonth);
    final maximum = normalizeMonth(maxMonth ?? DateTime.now());
    final minimum = DateTime(2000, 1);
    final canGoPrevious = isMonthAfter(selected, minimum);
    final canGoNext = !isMonthAfter(
      DateTime(selected.year, selected.month + 1),
      maximum,
    );

    Future<void> pickMonth() async {
      final picked = await showMonthYearPickerDialog(
        context,
        initialMonth: selected,
        maxMonth: maximum,
      );
      if (picked != null) onChanged(picked);
    }

    return Row(
      children: [
        IconButton(
          tooltip: AppStrings.current.text('previous_month_46a299'),
          onPressed: canGoPrevious
              ? () => onChanged(
                    DateTime(selected.year, selected.month - 1),
                  )
              : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: pickMonth,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                children: [
                  Text(
                    DateFormat.yMMMM().format(selected),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppStrings.current.text('tap_to_choose_month_f4d52f'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: AppStrings.current.text('next_month_8abf7c'),
          onPressed: canGoNext
              ? () => onChanged(
                    DateTime(selected.year, selected.month + 1),
                  )
              : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

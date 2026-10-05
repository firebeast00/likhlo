part of '../../screens/home_screen.dart';

extension _DashboardMonthMethods on _HomeScreenState {
  Future<void> _pickBudgetMonth() async {
    _dismissKeyboard();
    var selectedYear = _focusedMonth.year;
    final selected = await showDialog<DateTime>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(AppStrings.current.text('select_month_and_year_5391d2')),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: selectedYear,
                  decoration: InputDecoration(
                    labelText: AppStrings.current.text('year_879e32'),
                    prefixIcon: Icon(Icons.calendar_today_rounded),
                  ),
                  items: [
                    for (var year = 2000; year <= 2100; year++)
                      DropdownMenuItem(value: year, child: Text('$year')),
                  ],
                  onChanged: (year) {
                    if (year != null) {
                      setDialogState(() => selectedYear = year);
                    }
                  },
                ),
                const SizedBox(height: 16),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 2.2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: 12,
                  itemBuilder: (context, index) {
                    final month = index + 1;
                    final isSelected = selectedYear == _focusedMonth.year &&
                        month == _focusedMonth.month;
                    return FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        backgroundColor: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : null,
                        foregroundColor: isSelected ? Colors.white : null,
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () => Navigator.pop(
                        dialogContext,
                        DateTime(selectedYear, month, 1),
                      ),
                      child: Text(DateFormat.MMM().format(DateTime(2000, month))),
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
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _focusedMonth = selected);
    }
  }

  Widget _buildMonthSelector(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
            onPressed: () => setState(() => _focusedMonth =
                DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1)),
          ),
          TextButton.icon(
            onPressed: _pickBudgetMonth,
            icon: const Icon(Icons.calendar_month_rounded, size: 18),
            label: Text(
              DateFormat.yMMMM().format(_focusedMonth),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            onPressed: () => setState(() => _focusedMonth =
                DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1)),
          ),
        ],
      ),
    );
  }


}

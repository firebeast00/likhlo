part of '../../screens/home_screen.dart';

extension _DashboardSmartEntryMatchingMethods on _HomeScreenState {
  Future<Expense?> _showSmartEntryMatchPicker(
      List<SmartEntryTransaction> matches, {
        required bool deleting,
        bool repeating = false,
      }) async {
    final allEntries = ref
        .read(expenseProvider)
        .allExpenses;
    final entriesById = {
      for (final entry in allEntries) entry.id: entry,
    };
    final wallets = ref.read(walletProvider);
    final walletNames = {
      for (final wallet in wallets) wallet.id: wallet.name,
    };
    final candidates = matches
        .map((match) => entriesById[match.id])
        .whereType<Expense>()
        .toList(growable: false);
    if (candidates.isEmpty) return null;

    return showModalBottomSheet<Expense>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.68,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                  child: Row(
                    children: [
                      Icon(
                        deleting
                            ? Icons.delete_outline_rounded
                            : repeating
                            ? Icons.replay_rounded
                            : Icons.edit_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              deleting
                                  ? AppStrings.current.text('choose_entry_to_delete_fafeb7')
                                  : repeating
                                  ? AppStrings.current.text('choose_entry_to_repeat_05a271')
                                  : AppStrings.current.text('choose_entry_to_edit_8765a3'),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              AppStrings.current.text('several_entries_match_your_command_e9a6dd'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: candidates.length,
                    separatorBuilder: (_, __) => const Divider(
                      height: 1,
                      indent: 72,
                    ),
                    itemBuilder: (context, index) {
                      final entry = candidates[index];
                      final isIncome = entry.type == 'income';
                      final walletName =
                          walletNames[entry.walletId] ?? 'Unknown wallet';
                      final dateLabel =
                      DateFormat('dd MMM, h:mm a').format(entry.date);
                      final amountLabel = entry.amount.toStringAsFixed(
                        entry.amount == entry.amount.truncateToDouble()
                            ? 0
                            : 2,
                      );
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: (isIncome
                              ? Colors.green
                              : Colors.red)
                              .withValues(alpha: 0.12),
                          child: Icon(
                            isIncome
                                ? Icons.south_west_rounded
                                : Icons.north_east_rounded,
                            color: isIncome ? Colors.green : Colors.red,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '$walletName · $dateLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          'Rs. $amountLabel',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onTap: () =>
                            Navigator.of(sheetContext).pop(entry),
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


}

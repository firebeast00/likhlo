part of '../../screens/home_screen.dart';

extension _DashboardTransactionWidgetMethods on _HomeScreenState {
  Widget _buildMoneySetupCard(Color primaryColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: primaryColor.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.rocket_launch_outlined,
                  color: primaryColor,
                  size: 21,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.current.text('set_up_your_first_money_c2c03e'),
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                    ),
                    SizedBox(height: 2),
                    Text(
                      AppStrings.current.text('your_total_balance_automatically_equals_all_wall_a044f3'),
                      style: TextStyle(fontSize: 11.5, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.south_west_rounded, size: 17),
                label: Text(AppStrings.current.text('add_first_income_a489e8')),
                onPressed: () => _showAddOrEditModal(initialType: 'income'),
              ),
              ActionChip(
                avatar: const Icon(Icons.account_balance_wallet_outlined, size: 17),
                label: Text(AppStrings.current.text('set_wallet_balance_c9c8e4')),
                onPressed: _openIncomeAccounts,
              ),
              ActionChip(
                avatar: const Icon(Icons.auto_awesome_rounded, size: 17),
                label: Text(AppStrings.current.text('try_smart_entry_fa76d5')),
                onPressed: () {
                  _smartInputCtrl.text = '5000 salary JazzCash mein add karo';
                  _smartInputCtrl.selection = TextSelection.collapsed(
                    offset: _smartInputCtrl.text.length,
                  );
                  _showTransactionInfo(
                    AppMessage('review_the_example_then_tap_send_55b44f'),
                    title: AppMessage('smart_entry_example_ready_753417'),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseList(List<Expense> expenses, Color primaryColor, bool isDark, {required bool isSliver}) {
    if (expenses.isEmpty) {
      final emptyState = Center(child: Padding(padding: const EdgeInsets.only(top: 40.0), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.receipt_long_rounded, size: 50, color: Colors.grey.withValues(alpha: 0.3)), const SizedBox(height: 12), Text(AppStrings.current.text('no_transactions_here_yet_6e0cda'), style: TextStyle(color: Colors.grey.shade500, fontSize: 13))])));
      return isSliver ? SliverFillRemaining(hasScrollBody: false, child: emptyState) : emptyState;
    }

    final now = DateTime.now();
    final double todaySpend = expenses
        .where((e) =>
    e.type == 'expense' &&
        e.category != 'Transfer' &&
        e.date.day == now.day &&
        e.date.month == now.month &&
        e.date.year == now.year)
        .fold(0.0, (sum, e) => sum + e.amount);

    final hasTodaySummary = todaySpend > 0;
    final itemCount = expenses.length + (hasTodaySummary ? 1 : 0);

    Widget buildItem(BuildContext context, int index) {
      if (hasTodaySummary && index == 0) {
        return _buildTodaySpendPill(todaySpend, primaryColor);
      }
      final expenseIndex = index - (hasTodaySummary ? 1 : 0);
      return _buildExpenseTile(
        expenses[expenseIndex],
        primaryColor,
        isDark,
      );
    }

    if (isSliver) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 80),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            buildItem,
            childCount: itemCount,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 80),
      itemCount: itemCount,
      itemBuilder: buildItem,
    );
  }

  Widget _buildTodaySpendPill(double todaySpend, Color primaryColor) {
    return Padding(
      key: const ValueKey('daily_spend_pill'),
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Align(
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: primaryColor.withValues(alpha: 0.2)),
          ),
          child: Text(
            AppStrings.current.text('today_s_spend_rs_ca82eb', {'p0': todaySpend.toStringAsFixed(0)}),
            style: TextStyle(
              color: primaryColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpenseTile(Expense e, Color primaryColor, bool isDark) {
    final eColor = Color(e.colorValue);
    final isIncome = e.type == 'income';
    final isTransfer = e.category == 'Transfer';

    final amountSign = isTransfer ? "" : (isIncome ? "+" : "-");
    final amountColor = isTransfer ? Colors.blue : (isIncome ? Colors.green : (isDark ? Colors.white : Colors.black87));
    final displayIcon = isTransfer ? Icons.swap_horiz_rounded : (isIncome ? Icons.south_west_rounded : Icons.category_rounded);

    return Dismissible(
      key: Key(e.id),
      direction: DismissDirection.endToStart,
      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(18)), child: const Icon(Icons.delete_outline_rounded, color: Colors.white)),
      confirmDismiss: (direction) async {
        final confirmed = await showDialog<bool>(
              context: context,
              builder: (dialogCtx) => Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                backgroundColor: Theme.of(context).cardColor,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.red,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isTransfer
                            ? AppStrings.current.text('move_transfer_to_trash_5ce57e')
                            : AppStrings.current.text('move_transaction_to_trash_e78f60'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isTransfer
                            ? AppStrings.current.text('both_linked_wallet_entries_will_move_together_an_f82612')
                            : AppStrings.current.text('move_to_trash_it_can_be_restored_for_30_days_5372a8', {'p0': e.title}),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.of(dialogCtx).pop(false),
                              child: Text(AppStrings.current.text('cancel_77dfd2')),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => Navigator.of(dialogCtx).pop(true),
                              child: Text(AppStrings.current.text('move_to_trash_dffd3b')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ) ??
            false;
        if (!confirmed) return false;
        final result = isTransfer
            ? await ref
              .read(transactionExecutorProvider)
              .execute(DeleteTransferCommand(e.id))
            : await ref
              .read(transactionExecutorProvider)
              .execute(DeleteTransactionCommand(e.id));
        if (!mounted) return false;
        if (!result.succeeded) {
          _showTransactionError(
            result.reason ?? AppMessage('the_entry_could_not_be_moved_to_trash_ec0ca1'),
          );
          return false;
        }
        return true;
      },
      onDismissed: (direction) {
        unawaited(NotificationService().showManualLedgerResult(
          isTransfer ? 'Transfer deleted' : 'Entry deleted',
          '${e.title} · Rs. ${e.amount.toStringAsFixed(2)}',
        ));
        _showDeletionMessage(
          AppMessage('can_be_restored_from_trash_11909a', {'p0': e.title}),
          title: isTransfer ? AppMessage('transfer_moved_to_trash_e0cc25') : AppMessage('moved_to_trash_b646b3'),
          actionLabel: AppMessage('undo_39fc72'),
          onAction: () async {
            final restored = isTransfer
                ? await ref
                    .read(transactionExecutorProvider)
                    .execute(RestoreTransferCommand(e.id))
                : await ref
                    .read(transactionExecutorProvider)
                    .execute(RestoreTransactionCommand(e.id));
            if (!mounted) return;
            if (restored.succeeded) {
              _showTransactionInfo(
                AppMessage('the_entry_was_restored_057112'),
                title: AppMessage('restored_b54d62'),
                announce: false,
              );
            }
          },
        );
      },
      child: GestureDetector(
        onTap: isTransfer ? null : () => _showAddOrEditModal(existing: e),
        child: Container(
            margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(18), border: Border.all(color: isDark ? primaryColor.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.12), width: 1.2)),
            child: LedgerEntryContent(
              title: e.title,
              dateLabel: AppStrings.current.dateLabel(DateFormat.MMMEd().format(e.date)),
              amountLabel: AppStrings.current.text('rs_0a1fb6', {'p0': amountSign, 'p1': e.amount.toStringAsFixed(0)}),
              icon: displayIcon,
              iconColor: isTransfer ? Colors.blue : (isIncome ? Colors.green : eColor),
              iconBackground: (isTransfer ? Colors.blue : (isIncome ? Colors.green : eColor)).withValues(alpha: 0.15),
              amountColor: amountColor,
            )
        ),
      ),
    );
  }


}

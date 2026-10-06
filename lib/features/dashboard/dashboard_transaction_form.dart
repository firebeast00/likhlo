part of '../../screens/home_screen.dart';

extension _DashboardTransactionFormMethods on _HomeScreenState {
  Future<bool?> _showAddOrEditModal({
    Expense? existing,
    String? prefilledAmount,
    String? prefilledTitle,
    String? prefilledCategory,
    DateTime? prefilledDate,
    String? preselectedWalletId,
    String initialType = 'expense',
    String? reviewMessage,
  }) async {
    final diagnosticId = VoiceDiagnosticsService.instance.currentId;
    _dismissKeyboard();
    if (existing?.category == 'Transfer') {
      _showTransactionInfo(
        AppMessage('delete_this_transfer_and_create_it_again_if_its__f61a0b'),
        title: AppMessage('transfers_cannot_be_edited_557173'),
      );
      return null;
    }

    final titleCtrl = TextEditingController(
      text: existing?.title ?? prefilledTitle ?? "",
    );
    final amountCtrl = TextEditingController(
      text: prefilledAmount ?? (existing?.amount.toString() ?? ""),
    );
    String selectedCategory =
        existing?.category ?? prefilledCategory ?? "General";
    DateTime selectedDate =
        existing?.date ?? prefilledDate ?? DateTime.now();

    String transactionType = existing?.type ?? initialType;

    final wallets = ref.read(walletProvider);
    String selectedWalletId =
        existing?.walletId ?? preselectedWalletId ?? '';
    String transferToWalletId = '';

    final categories = ref.read(categoryProvider);
    if (!categories.contains(selectedCategory) && categories.isNotEmpty) {
      selectedCategory = categories.first;
    }

    final primaryColor = Color(ref.read(settingsProvider).profileColorValue);

    if (!wallets.any((w) => w.id == selectedWalletId) && wallets.isNotEmpty) {
      final cashWallet = wallets.cast<Wallet?>().firstWhere(
            (w) => w != null && !w.isBackup && (w.walletType == 'cash' || w.name.toLowerCase().contains('cash')),
        orElse: () => null,
      );

      if (cashWallet != null) {
        selectedWalletId = cashWallet.id;
      } else {
        selectedWalletId = wallets.firstWhere((w) => !w.isBackup, orElse: () => wallets.first).id;
      }
    }

    if (wallets.length > 1) {
      transferToWalletId = wallets.firstWhere((w) => w.id != selectedWalletId, orElse: () => wallets.last).id;
    }

    return showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setModalState) => Container(
            decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
            ),
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 24, left: 24, right: 24, top: 12),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 48, height: 4, decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)), margin: const EdgeInsets.only(bottom: 24)),

                  if (reviewMessage != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: primaryColor.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.fact_check_outlined,
                            color: primaryColor,
                            size: 21,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppStrings.current.text('review_before_saving_6f92b7'),
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  AppStrings.current.display(reviewMessage),
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontSize: 12.5,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  Container(
                    decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        _buildSegment(transactionType, 'expense', "Expense", Colors.red, () => setModalState(() => transactionType = 'expense')),
                        _buildSegment(transactionType, 'income', "Income", Colors.green, () => setModalState(() => transactionType = 'income')),
                        _buildSegment(transactionType, 'transfer', "Transfer", Colors.blue, () => setModalState(() => transactionType = 'transfer')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (transactionType != 'transfer')
                    _buildModernInput(titleCtrl, "Title", Icons.title_rounded, primaryColor)
                  else
                    Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(left: 8, bottom: 8), child: Text(AppStrings.current.text('moving_money_between_wallets_2919b3'), style: TextStyle(color: Colors.grey, fontSize: 13)))),

                  const SizedBox(height: 12),
                  _buildModernInput(amountCtrl, "Amount", Icons.attach_money_rounded, primaryColor, isNumber: true),
                  const SizedBox(height: 12),

                  if (transactionType == 'transfer') ...[
                    _buildWalletDropdown(wallets, selectedWalletId, "From Wallet", (v) => setModalState(() => selectedWalletId = v!)),
                    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Icon(Icons.arrow_downward_rounded, color: Colors.grey)),
                    _buildWalletDropdown(wallets, transferToWalletId, "To Wallet", (v) => setModalState(() => transferToWalletId = v!)),
                  ] else ...[
                    _buildWalletDropdown(wallets, selectedWalletId, "Wallet", (v) => setModalState(() => selectedWalletId = v!)),
                  ],
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: GestureDetector(
                          onTap: () async {
                            final picked = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
                            if (picked != null) setModalState(() => selectedDate = picked);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today_rounded, color: Colors.grey.shade500, size: 20),
                                const SizedBox(width: 8),
                                Expanded(child: Text(AppStrings.current.dateLabel(DateFormat.yMMMd().format(selectedDate)), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (transactionType == 'expense') ...[
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: categories.contains(selectedCategory) ? selectedCategory : (categories.isNotEmpty ? categories.first : "General"),
                                isExpanded: true,
                                icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade500),
                                items: categories.map((c) => DropdownMenuItem(value: c, child: Text(AppStrings.current.display(c), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis))).toList(),
                                onChanged: (v) => setModalState(() => selectedCategory = v!),
                              ),
                            ),
                          ),
                        ),
                      ]
                    ],
                  ),

                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity, height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: transactionType == 'transfer' ? Colors.blue : primaryColor, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      onPressed: () => VoiceDiagnosticsService.instance.run(diagnosticId, () async {
                        final amt = double.tryParse(amountCtrl.text.trim());
                        if (amt == null || !amt.isFinite || amt <= 0) {
                          _showTransactionError(AppMessage('enter_a_valid_amount_above_zero_8262af'));
                          return;
                        }
                        if (wallets.isEmpty) {
                          _showTransactionError(AppMessage('create_a_wallet_first_16db9a'));
                          return;
                        }

                        if (transactionType == 'expense') {
                          final currentBalance = ref
                              .read(walletProvider.notifier)
                              .getBalanceForWallet(selectedWalletId);
                          final reusableAmount = existing != null &&
                              existing.type == 'expense' &&
                              existing.walletId == selectedWalletId
                              ? existing.amount
                              : 0.0;
                          final available = currentBalance + reusableAmount;
                          if (amt > available) {
                            final accountName = wallets
                                .firstWhere((w) => w.id == selectedWalletId)
                                .name;
                            _showTransactionError(
                              AppMessage('available_in_rs_required_rs_add_money_to_this_wa_96b697', {'p0': accountName, 'p1': available.toStringAsFixed(0), 'p2': amt.toStringAsFixed(0)}),
                              title: AppMessage('insufficient_balance_1a1823'),
                            );
                            return;
                          }
                        }

                        Expense? preferenceEntry;
                        if (transactionType == 'transfer') {
                          if (wallets.length < 2) {
                            _showTransactionError(AppMessage('create_at_least_two_wallets_to_transfer_money_c80e1c'));
                            return;
                          }
                          if (selectedWalletId == transferToWalletId) {
                            _showTransactionError(AppMessage('choose_two_different_wallets_32b992'));
                            return;
                          }
                          final available = ref
                              .read(walletProvider.notifier)
                              .getBalanceForWallet(selectedWalletId);
                          if (amt > available) {
                            _showTransactionError(
                              AppMessage('available_in_the_source_wallet_rs_enter_a_smalle_ac724e', {'p0': available.toStringAsFixed(0)}),
                              title: AppMessage('insufficient_balance_1a1823'),
                            );
                            return;
                          }
                          final fromName = wallets.firstWhere((w) => w.id == selectedWalletId).name;
                          final toName = wallets.firstWhere((w) => w.id == transferToWalletId).name;
                          final transferId = const Uuid().v4();

                          final transferResult = await ref
                              .read(transactionExecutorProvider)
                              .execute(CreateTransferCommand(
                            outgoing: Expense(id: '${transferId}_out', title: coreTransactionTitle("Transfer to $toName"), amount: amt, date: selectedDate, category: "Transfer", colorValue: Colors.blue.toARGB32(), type: 'expense', walletId: selectedWalletId),
                            incoming: Expense(id: '${transferId}_in', title: coreTransactionTitle("Transfer from $fromName"), amount: amt, date: selectedDate, category: "Transfer", colorValue: Colors.blue.toARGB32(), type: 'income', walletId: transferToWalletId),
                          ));
                          if (!transferResult.succeeded) {
                            _showTransactionError(
                              AppMessage('the_source_wallet_no_longer_has_enough_money_for_63c806'),
                              title: AppMessage('transfer_not_saved_ff0de3'),
                            );
                            return;
                          }
                        } else {
                          String finalTitle =
                          coreTransactionTitle(titleCtrl.text);
                          if (finalTitle.isEmpty) {
                            if (transactionType == 'income') {
                              finalTitle = 'Income / Allowance';
                            } else {
                              _showTransactionError(AppMessage('enter_a_transaction_title_817c58'));
                              return;
                            }
                          }

                          final finalCategory = transactionType == 'income' ? 'Income / Allowance' : selectedCategory;
                          if (existing == null) {
                            final newEntry = Expense(id: const Uuid().v4(), title: finalTitle, amount: amt, date: selectedDate, category: finalCategory, colorValue: primaryColor.toARGB32(), type: transactionType, walletId: selectedWalletId);
                            final createResult = await ref
                                .read(transactionExecutorProvider)
                                .execute(CreateTransactionCommand(newEntry));
                            if (!createResult.succeeded) {
                              _showTransactionError(
                                AppMessage('check_the_selected_wallet_balance_and_try_again_b1bee5'),
                                title: AppMessage('transaction_not_saved_16554e'),
                              );
                              return;
                            }
                            preferenceEntry = newEntry;
                          } else {
                            final editedEntry = Expense(id: existing.id, title: finalTitle, amount: amt, date: selectedDate, category: finalCategory, colorValue: existing.colorValue, type: transactionType, walletId: selectedWalletId);
                            final updateResult = await ref
                                .read(transactionExecutorProvider)
                                .execute(UpdateTransactionCommand(
                              existingId: existing.id,
                              updated: editedEntry,
                            ));
                            if (!updateResult.succeeded) {
                              _showTransactionError(AppMessage('this_transaction_no_longer_exists_11cb0e'));
                              return;
                            }
                            preferenceEntry = editedEntry;
                          }
                        }
                        if (ctx.mounted) Navigator.pop(ctx, true);
                        if (reviewMessage == null && mounted) {
                          final notificationTitle = transactionType == 'transfer'
                              ? 'Transfer saved'
                              : existing != null ? 'Entry updated' : 'Entry saved';
                          final notificationDetail = transactionType == 'transfer'
                              ? 'Rs. ${amt.toStringAsFixed(2)} transferred between wallets.'
                              : '${preferenceEntry?.title ?? titleCtrl.text.trim()} · Rs. ${amt.toStringAsFixed(2)}';
                          unawaited(NotificationService().showManualLedgerResult(
                            notificationTitle, notificationDetail));
                          if (transactionType == 'transfer') {
                            _showTransferMessage(
                              AppMessage('money_was_moved_between_the_selected_wallets_a92dc6'),
                            );
                          } else if (transactionType == 'income') {
                            _showIncomeMessage(
                              AppMessage('the_income_was_added_to_the_selected_wallet_36d17e'),
                            );
                          } else {
                            _showExpenseMessage(
                              AppMessage('the_expense_was_saved_to_the_selected_wallet_2f0ad9'),
                            );
                          }
                        }
                        if (preferenceEntry != null) {
                          unawaited(
                            _rememberSmartEntryPreference(preferenceEntry),
                          );
                        }
                        unawaited(_refreshSmartEntryReminders());
                      }),
                      child: Text(transactionType == 'transfer' ? AppStrings.current.text('complete_transfer_bf7f6e') : AppStrings.current.text('save_transaction_a3f812'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  )
                ],
              ),
            ),
          ),
        )
    );
  }

  Widget _buildSegment(String current, String type, String label, Color color, VoidCallback onTap) {
    bool isActive = current == type;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: isActive ? color.withValues(alpha: 0.15) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
          child: Center(child: Text(AppStrings.current.display(label), style: TextStyle(color: isActive ? color : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12))),
        ),
      ),
    );
  }

  Widget _buildWalletDropdown(List<Wallet> wallets, String value, String hint, Function(String?) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.withValues(alpha: 0.1))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: wallets.any((w) => w.id == value) ? value : wallets.first.id,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade500),
          items: wallets.map((w) => DropdownMenuItem(value: w.id, child: Row(children: [
            Icon(w.isBackup ? Icons.shield_rounded : Icons.account_balance_wallet_rounded, size: 18, color: Color(w.colorValue)),
            const SizedBox(width: 12),
            Text(w.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))
          ]))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildModernInput(TextEditingController ctrl, String label, IconData icon, Color primaryColor, {bool isNumber = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber
          ? const TextInputType.numberWithOptions(decimal: true, signed: false)
          : TextInputType.text,
      inputFormatters: isNumber
          ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))]
          : null,
      textCapitalization: isNumber ? TextCapitalization.none : TextCapitalization.sentences,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      decoration: InputDecoration(labelText: label, labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13), prefixIcon: Icon(icon, color: Colors.grey.shade500, size: 20), filled: true, fillColor: Theme.of(context).cardColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: primaryColor, width: 1.5)), contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16)),
    );
  }


}

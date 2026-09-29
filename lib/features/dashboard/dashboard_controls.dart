part of '../../screens/home_screen.dart';

extension _DashboardControlMethods on _HomeScreenState {
  void _selectCategory(String category, int index) {
    _dismissKeyboard();
    setState(() => _selectedCategoryTab = category);
    double offset = (index * 70.0) - (MediaQuery.of(context).size.width / 2) + 35;
    if (offset < 0) offset = 0;
    if (_categoryScrollCtrl.hasClients) {
      _categoryScrollCtrl.animateTo(offset, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _changeSection(AppSection section) {
    _dismissKeyboard();
    if (!mounted || section == ref.read(appNavigationProvider)) return;
    setState(() {
      _isSearching = false;
      _searchQuery = '';
      _smartEntryTypeFilter = null;
      _smartEntrySearchRange = null;
      _smartEntrySearchAllHistory = false;
    });
    ref.read(appNavigationProvider.notifier).open(section);
  }

  void _openPrimaryLedgerTab(PrimaryLedgerTab tab) {
    _dismissKeyboard();
    if (!mounted) return;
    ref.read(appNavigationProvider.notifier).openDashboard();
    setState(() {
      _activePrimaryTab = tab;
      _isSearching = false;
      _searchQuery = '';
      _smartEntryTypeFilter = null;
      _smartEntrySearchRange = null;
      _smartEntrySearchAllHistory = false;
    });
    _primaryTabsController.select(tab);
    if (tab == PrimaryLedgerTab.main) {
      _queuePersistentNotificationUpdate();
    }
  }

  void _showAddCategoryDialog() {
    _dismissKeyboard();
    final catCtrl = TextEditingController();
    final primaryColor = Color(ref.read(settingsProvider).profileColorValue);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: primaryColor.withValues(alpha: 0.15), shape: BoxShape.circle), child: Icon(Icons.category_rounded, color: primaryColor, size: 20)),
            const SizedBox(width: 12),
            const Expanded(child: Text("New Category", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ],
        ),
        content: _buildModernInput(catCtrl, "Category Name", Icons.new_label_rounded, primaryColor),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel", style: TextStyle(color: Colors.grey)))),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 12)),
                  onPressed: () {
                    if (catCtrl.text.trim().isNotEmpty) {
                      final added = ref
                          .read(categoryProvider.notifier)
                          .addCategory(catCtrl.text.trim());
                      if (!added) {
                        _showTransactionError(
                          'Choose a different name for this category.',
                          title: 'Category already exists',
                        );
                        return;
                      }
                      Navigator.pop(ctx);
                      Future.delayed(const Duration(milliseconds: 300), () {
                        if (_categoryScrollCtrl.hasClients) {
                          _categoryScrollCtrl.animateTo(_categoryScrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                        }
                      });
                    }
                  },
                  child: const Text("Save"),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Future<void> _confirmDeleteCategory(String category) async {
    _dismissKeyboard();
    if (category == 'All') return;
    final categories = ref.read(categoryProvider);

    if (categories.length <= 1) {
      _showTransactionError('Keep at least one expense category.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Delete Category?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Text(
          "Delete '$category'? Existing transactions will remain unchanged.",
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    ref.read(categoryProvider.notifier).deleteCategory(category);

    if (_selectedCategoryTab == category) {
      setState(() => _selectedCategoryTab = 'All');
    }
    _showDeletionMessage(
      "Category '$category' was deleted.",
      title: 'Category deleted',
    );
  }

  // ==================== TRANSACTION / TRANSFER MODAL ====================
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
    _dismissKeyboard();
    if (existing?.category == 'Transfer') {
      _showTransactionInfo(
        'Delete this transfer and create it again if its details need to change.',
        title: 'Transfers cannot be edited',
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
                                const Text(
                                  'Review before saving',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  reviewMessage,
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
                    const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(left: 8, bottom: 8), child: Text("Moving money between wallets", style: TextStyle(color: Colors.grey, fontSize: 13)))),

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
                                Expanded(child: Text(DateFormat.yMMMd().format(selectedDate), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)),
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
                                items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis))).toList(),
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
                      onPressed: () async {
                        final amt = double.tryParse(amountCtrl.text.trim());
                        if (amt == null || !amt.isFinite || amt <= 0) {
                          _showTransactionError('Enter a valid amount above zero.');
                          return;
                        }
                        if (wallets.isEmpty) {
                          _showTransactionError('Create a wallet first.');
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
                              'Available in $accountName: Rs. ${available.toStringAsFixed(0)}. Required: Rs. ${amt.toStringAsFixed(0)}. Add money to this wallet or enter a smaller amount.',
                              title: 'Insufficient balance',
                            );
                            return;
                          }
                        }

                        Expense? preferenceEntry;
                        if (transactionType == 'transfer') {
                          if (wallets.length < 2) {
                            _showTransactionError('Create at least two wallets to transfer money.');
                            return;
                          }
                          if (selectedWalletId == transferToWalletId) {
                            _showTransactionError('Choose two different wallets.');
                            return;
                          }
                          final available = ref
                              .read(walletProvider.notifier)
                              .getBalanceForWallet(selectedWalletId);
                          if (amt > available) {
                            _showTransactionError(
                              'Available in the source wallet: Rs. ${available.toStringAsFixed(0)}. Enter a smaller amount or add money first.',
                              title: 'Insufficient balance',
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
                              'The source wallet no longer has enough money for this transfer.',
                              title: 'Transfer not saved',
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
                              _showTransactionError('Enter a transaction title.');
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
                                'Check the selected wallet balance and try again.',
                                title: 'Transaction not saved',
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
                              _showTransactionError('This transaction no longer exists.');
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
                              'Money was moved between the selected wallets.',
                            );
                          } else if (transactionType == 'income') {
                            _showIncomeMessage(
                              'The income was added to the selected wallet.',
                            );
                          } else {
                            _showExpenseMessage(
                              'The expense was saved to the selected wallet.',
                            );
                          }
                        }
                        if (preferenceEntry != null) {
                          unawaited(
                            _rememberSmartEntryPreference(preferenceEntry),
                          );
                        }
                        unawaited(_refreshSmartEntryReminders());
                      },
                      child: Text(transactionType == 'transfer' ? "Complete Transfer" : "Save Transaction", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  )
                ],
              ),
            ),
          ),
        )
    );
  }

  void _showTransactionError(
      String message, {
        String title = 'Unable to continue',
      }) {
    _showTopMessage(
      title: title,
      message: message,
      tone: TransactionMessageTone.error,
    );
  }

  void _showTransactionSuccess(
      String message, {
        String title = 'Completed',
        String? actionLabel,
        Future<void> Function()? onAction,
      }) {
    _showTopMessage(
      title: title,
      message: message,
      tone: TransactionMessageTone.success,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  void _showTransactionInfo(
      String message, {
        String title = 'Information',
      }) {
    _showTopMessage(
      title: title,
      message: message,
      tone: TransactionMessageTone.info,
    );
  }

  void _showExpenseMessage(String message, {String title = 'Expense saved'}) {
    _showTopMessage(
      title: title,
      message: message,
      tone: TransactionMessageTone.expense,
    );
  }

  void _showIncomeMessage(String message, {String title = 'Income added'}) {
    _showTopMessage(
      title: title,
      message: message,
      tone: TransactionMessageTone.income,
    );
  }

  void _showTransferMessage(
    String message, {
    String title = 'Transfer completed',
    String? actionLabel,
    Future<void> Function()? onAction,
  }) {
    _showTopMessage(
      title: title,
      message: message,
      tone: TransactionMessageTone.transfer,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  void _showDeletionMessage(
    String message, {
    String title = 'Moved to Trash',
    String? actionLabel,
    Future<void> Function()? onAction,
  }) {
    _showTopMessage(
      title: title,
      message: message,
      tone: TransactionMessageTone.deletion,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  void _showTopMessage({
    required String title,
    required String message,
    required TransactionMessageTone tone,
    String? actionLabel,
    Future<void> Function()? onAction,
  }) {
    if (!mounted) return;
    _feedback.show(
      context,
      title: title,
      message: message,
      tone: tone,
      actionLabel: actionLabel,
      onAction: onAction,
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
          child: Center(child: Text(label, style: TextStyle(color: isActive ? color : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12))),
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

  Future<void> _openIncomeAccounts() async {
    _dismissKeyboard();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const IncomeAccountsScreen()),
    );
    if (mounted) _queuePersistentNotificationUpdate();
  }


}

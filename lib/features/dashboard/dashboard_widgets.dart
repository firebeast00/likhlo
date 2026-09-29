part of '../../screens/home_screen.dart';

extension _DashboardWidgetMethods on _HomeScreenState {
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
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Set up your first money',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Your total balance automatically equals all wallet balances.',
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
                label: const Text('Add first income'),
                onPressed: () => _showAddOrEditModal(initialType: 'income'),
              ),
              ActionChip(
                avatar: const Icon(Icons.account_balance_wallet_outlined, size: 17),
                label: const Text('Set wallet balance'),
                onPressed: _openIncomeAccounts,
              ),
              ActionChip(
                avatar: const Icon(Icons.auto_awesome_rounded, size: 17),
                label: const Text('Try Smart Entry'),
                onPressed: () {
                  _smartInputCtrl.text = '5000 salary JazzCash mein add karo';
                  _smartInputCtrl.selection = TextSelection.collapsed(
                    offset: _smartInputCtrl.text.length,
                  );
                  _showTransactionInfo(
                    'Review the example, then tap Send.',
                    title: 'Smart Entry example ready',
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
      final emptyState = Center(child: Padding(padding: const EdgeInsets.only(top: 40.0), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.receipt_long_rounded, size: 50, color: Colors.grey.withValues(alpha: 0.3)), const SizedBox(height: 12), Text("No transactions here yet.", style: TextStyle(color: Colors.grey.shade500, fontSize: 13))])));
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
            "Today's Spend: Rs. ${todaySpend.toStringAsFixed(0)}",
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
                            ? 'Move Transfer to Trash?'
                            : 'Move Transaction to Trash?',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isTransfer
                            ? 'Both linked wallet entries will move together and can be restored.'
                            : "Move '${e.title}' to Trash? It can be restored for 30 days.",
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
                              child: const Text('Cancel'),
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
                              child: const Text('Move to Trash'),
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
            result.reason ?? 'The entry could not be moved to Trash.',
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
          "'${e.title}' can be restored from Trash.",
          title: isTransfer ? 'Transfer moved to Trash' : 'Moved to Trash',
          actionLabel: 'Undo',
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
              _showTransactionInfo('The entry was restored.', title: 'Restored');
            }
          },
        );
      },
      child: GestureDetector(
        onTap: isTransfer ? null : () => _showAddOrEditModal(existing: e),
        child: Container(
            margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(18), border: Border.all(color: isDark ? primaryColor.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.12), width: 1.2)),
            child: Row(
              children: [
                Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: (isTransfer ? Colors.blue : (isIncome ? Colors.green : eColor)).withValues(alpha: 0.15), shape: BoxShape.circle), child: Icon(displayIcon, color: isTransfer ? Colors.blue : (isIncome ? Colors.green : eColor), size: 20)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Row(children: [Icon(Icons.schedule_rounded, size: 11, color: Colors.grey.shade500), const SizedBox(width: 4), Text(DateFormat.MMMEd().format(e.date), style: TextStyle(fontSize: 11, color: Colors.grey.shade500))]),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text("$amountSign Rs. ${e.amount.toStringAsFixed(0)}", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: amountColor)),
              ],
            )
        ),
      ),
    );
  }

  Widget _buildCategoryTabsWidget(List<String> categories, Color primaryColor, bool isDark) {
    return Container(
      height: 40, margin: const EdgeInsets.only(top: 4, bottom: 8),
      child: ListView(
          controller: _categoryScrollCtrl, scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [_buildTab('All', 0, isDark, primaryColor), ...List.generate(categories.length, (i) => _buildTab(categories[i], i + 1, isDark, primaryColor)), _buildAddCategoryBtn(primaryColor, isDark)]
      ),
    );
  }

  Widget _buildAddCategoryBtn(Color primaryColor, bool isDark) {
    return GestureDetector(
      onTap: _showAddCategoryDialog,
      child: Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 16), decoration: BoxDecoration(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20), border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300, width: 1.2)), child: Row(children: [Icon(Icons.add_rounded, size: 16, color: isDark ? Colors.white70 : Colors.black87), const SizedBox(width: 4), Text("New", style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold, fontSize: 12))])),
    );
  }

  Widget _buildTab(String label, int index, bool isDark, Color primaryColor) {
    bool isSelected = _selectedCategoryTab == label;
    return GestureDetector(
        onTap: () => _selectCategory(label, index),
        onLongPress: label == 'All' ? null : () => _confirmDeleteCategory(label),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isSelected ? primaryColor : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
            border: isSelected ? null : Border.all(color: isDark ? primaryColor.withValues(alpha: 0.25) : Colors.grey.withValues(alpha: 0.15), width: 1.2),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87), fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, fontSize: 12)),
                if (isSelected && label != 'All') ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _confirmDeleteCategory(label),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.close_rounded, size: 14, color: Colors.white),
                    ),
                  ),
                ],
              ],
            ),
          ),
        )
    );
  }

  Widget _buildSmartInputBar(
      Color primaryColor,
      bool isDark,
      List<Wallet> wallets,
      ) {
    final cardColor = Theme.of(context).cardColor;
    final inputColor = isDark
        ? Colors.white.withValues(alpha: 0.055)
        : primaryColor.withValues(alpha: 0.045);
    final defaultAccountLabel = _smartEntryDefaultAccountLabel(wallets);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _isListening
              ? Colors.red.withValues(alpha: 0.7)
              : primaryColor.withValues(alpha: isDark ? 0.24 : 0.12),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: (_isListening ? Colors.red : primaryColor)
                      .withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _isListening
                      ? Icons.graphic_eq_rounded
                      : Icons.auto_awesome_rounded,
                  color: _isListening ? Colors.red : primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: InkWell(
                  onTap: _isListening
                      ? null
                      : _showSmartEntryAccountPicker,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isListening ? 'Listening now' : 'Smart Entry',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isListening
                              ? 'Speak naturally — it saves automatically'
                              : defaultAccountLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _isListening
                                ? Colors.grey.shade500
                                : primaryColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_isListening)
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                )
              else
                IconButton(
                  tooltip: 'Select default Smart Entry wallet',
                  visualDensity: VisualDensity.compact,
                  onPressed: _showSmartEntryAccountPicker,
                  icon: Icon(
                    Icons.tune_rounded,
                    color: primaryColor,
                    size: 20,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 54,
            decoration: BoxDecoration(
              color: inputColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: TextField(
              controller: _smartInputCtrl,
              textInputAction: TextInputAction.done,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              onSubmitted: _processNLP,
              decoration: InputDecoration(
                hintText: _isListening
                    ? 'Listening…'
                    : ref.watch(settingsProvider).smartEntryLanguage == 'romanUrdu'
                        ? 'Misal: 500 biryani par kharch kiya'
                        : 'e.g. 500 biryani from JazzCash',
                hintStyle: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                contentPadding:
                const EdgeInsets.only(left: 15, top: 17, bottom: 17),
                suffixIconConstraints:
                const BoxConstraints(minHeight: 40),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Scan receipt',
                      visualDensity: VisualDensity.compact,
                      constraints:
                      const BoxConstraints.tightFor(width: 38, height: 40),
                      onPressed:
                      _isScanningReceipt ? null : _scanReceiptIntoInput,
                      icon: _isScanningReceipt
                          ? SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: primaryColor,
                        ),
                      )
                          : Icon(
                        Icons.document_scanner_outlined,
                        size: 20,
                        color: primaryColor,
                      ),
                    ),
                    IconButton(
                      tooltip:
                      _isListening ? 'Stop listening' : 'Voice input',
                      visualDensity: VisualDensity.compact,
                      constraints:
                      const BoxConstraints.tightFor(width: 38, height: 40),
                      onPressed: _listenForExpense,
                      icon: Icon(
                        _isListening
                            ? Icons.stop_circle_rounded
                            : Icons.mic_none_rounded,
                        size: 21,
                        color: _isListening ? Colors.red : primaryColor,
                      ),
                    ),
                    Container(
                      width: 34,
                      height: 34,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        tooltip: 'Save Smart Entry',
                        padding: EdgeInsets.zero,
                        onPressed: () =>
                            _processNLP(_smartInputCtrl.text),
                        icon: const Icon(
                          Icons.arrow_upward_rounded,
                          size: 19,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _smartEntryDefaultAccountLabel(List<Wallet> wallets) {
    final selected = _selectedSmartEntryWallet(wallets);
    return selected == null
        ? 'Default wallet: Automatic (Cash → JazzCash) · Tap to change'
        : 'Default wallet: ${selected.name} · Tap to change';
  }

  Wallet? _selectedSmartEntryWallet(List<Wallet> wallets) {
    final selectedId = _smartEntryDefaultWalletId;
    if (selectedId == null) return null;
    for (final wallet in wallets) {
      if (wallet.id == selectedId) return wallet;
    }
    return null;
  }

  Future<void> _showSmartEntryAccountPicker() async {
    _dismissKeyboard();
    final wallets = ref.read(walletProvider);
    if (wallets.isEmpty) {
      _showTransactionError(
        'Create a wallet before selecting a Smart Entry default.',
        title: 'No wallets',
      );
      return;
    }

    final walletNotifier = ref.read(walletProvider.notifier);
    final selectedId = _selectedSmartEntryWallet(wallets)?.id;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Default Smart Entry wallet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(sheetContext)
                            .colorScheme
                            .primaryContainer,
                        child: Icon(
                          Icons.auto_awesome_rounded,
                          color: Theme.of(sheetContext)
                              .colorScheme
                              .primary,
                        ),
                      ),
                      title: const Text(
                        'Automatic',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'Use Cash first, then JazzCash',
                      ),
                      trailing: selectedId == null
                          ? const Icon(Icons.check_circle_rounded)
                          : null,
                      onTap: () async {
                        await Hive.box('preferences')
                            .delete(_smartEntryDefaultAccountKey);
                        if (!mounted) return;
                        setState(() => _smartEntryDefaultWalletId = null);
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }
                      },
                    ),
                    const Divider(height: 1),
                    for (final wallet in wallets)
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Color(wallet.colorValue)
                              .withValues(alpha: 0.14),
                          child: Icon(
                            _walletIcon(wallet),
                            color: Color(wallet.colorValue),
                            size: 20,
                          ),
                        ),
                        title: Text(
                          wallet.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          '${wallet.isBackup ? 'Reserve wallet' : 'Wallet'} · Rs. ${walletNotifier.getBalanceForWallet(wallet.id).toStringAsFixed(0)}',
                        ),
                        trailing: selectedId == wallet.id
                            ? const Icon(Icons.check_circle_rounded)
                            : null,
                        onTap: () async {
                          await Hive.box('preferences').put(
                            _smartEntryDefaultAccountKey,
                            wallet.id,
                          );
                          if (!mounted) return;
                          setState(
                                () => _smartEntryDefaultWalletId = wallet.id,
                          );
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Wallet> _resolvedHomeWallets(List<Wallet> wallets) {
    if (wallets.isEmpty) return const [];

    final walletsById = {for (final wallet in wallets) wallet.id: wallet};
    final savedSelection = _homeVisibleWalletIds
        .where(walletsById.containsKey)
        .take(4)
        .map((id) => walletsById[id]!)
        .toList(growable: false);
    if (savedSelection.isNotEmpty) return savedSelection;

    int defaultPriority(Wallet wallet) {
      final type = wallet.walletType.toLowerCase();
      final id = wallet.id.toLowerCase();
      final name = wallet.name.toLowerCase().replaceAll(' ', '');
      if (type == 'cash' || id == 'default_cash' || name == 'cashinhand') {
        return 0;
      }
      if (type == 'jazzcash' ||
          id == 'default_jazzcash' ||
          name == 'jazzcash') {
        return 1;
      }
      return 2;
    }

    final defaults = wallets
        .where((wallet) => defaultPriority(wallet) < 2)
        .toList(growable: false)
      ..sort((a, b) => defaultPriority(a).compareTo(defaultPriority(b)));
    if (defaults.isNotEmpty) {
      return defaults.take(4).toList(growable: false);
    }

    final fallbackCount = wallets.length < 2 ? wallets.length : 2;
    return wallets.take(fallbackCount).toList(growable: false);
  }

  Future<void> _showHomeWalletPicker() async {
    _dismissKeyboard();
    final wallets = ref.read(walletProvider);
    if (wallets.isEmpty) {
      _showTransactionError(
        'Create a wallet before choosing daily wallets.',
        title: 'No wallets',
      );
      return;
    }

    final walletNotifier = ref.read(walletProvider.notifier);
    final selectedIds = <String>{
      ..._resolvedHomeWallets(wallets).map((wallet) => wallet.id),
    };

    final savedIds = await showModalBottomSheet<List<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.78,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Daily wallets',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Choose up to 4 wallets for quick Home tracking.',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${selectedIds.length}/4',
                          style: TextStyle(
                            color: Theme.of(sheetContext).colorScheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: wallets.length,
                      itemBuilder: (context, index) {
                        final wallet = wallets[index];
                        final isSelected = selectedIds.contains(wallet.id);
                        final selectionLimitReached =
                            !isSelected && selectedIds.length >= 4;
                        final balance =
                        walletNotifier.getBalanceForWallet(wallet.id);

                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: selectionLimitReached
                              ? null
                              : (checked) {
                            setSheetState(() {
                              if (checked == true) {
                                selectedIds.add(wallet.id);
                              } else {
                                selectedIds.remove(wallet.id);
                              }
                            });
                          },
                          secondary: CircleAvatar(
                            backgroundColor: Color(wallet.colorValue)
                                .withValues(alpha: 0.14),
                            child: Icon(
                              _walletIcon(wallet),
                              color: Color(wallet.colorValue),
                              size: 20,
                            ),
                          ),
                          title: Text(
                            wallet.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            '${wallet.isBackup ? 'Reserve wallet' : 'Wallet'} · Rs. ${balance.toStringAsFixed(0)}',
                          ),
                          controlAffinity: ListTileControlAffinity.trailing,
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: selectedIds.isEmpty
                            ? null
                            : () => Navigator.pop(
                          sheetContext,
                          selectedIds.toList(growable: false),
                        ),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Save daily wallets'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (savedIds == null || !mounted) return;
    await Hive.box('preferences').put(_homeVisibleWalletsKey, savedIds);
    if (!mounted) return;
    setState(() => _homeVisibleWalletIds = savedIds);
  }

  Widget _buildHeroCard(
      double totalAvailable,
      double spent,
      List<Wallet> wallets,
      Color primary,
      ) {
    final visibleWallets = _resolvedHomeWallets(wallets);
    final darkerPrimary = Color.lerp(
      primary,
      Colors.black,
      Theme.of(context).brightness == Brightness.dark ? 0.12 : 0.18,
    )!;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, darkerPrimary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Total available',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Choose daily wallets',
                onPressed: _showHomeWalletPicker,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                icon: const Icon(
                  Icons.tune_rounded,
                  color: Colors.white,
                  size: 19,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'Rs. ${totalAvailable.toStringAsFixed(0)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.8,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildBalanceMetric(
                  label: 'Spent this month',
                  value: 'Rs. ${spent.toStringAsFixed(0)}',
                  onTap: () => _changeSection(AppSection.stats),
                  semanticHint: 'Open monthly statistics',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildBalanceMetric(
                  label: 'All wallets',
                  value: '${wallets.length}',
                  onTap: _openIncomeAccounts,
                  semanticHint: 'Open wallet accounts',
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Daily wallets',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${visibleWallets.length} of ${wallets.length} shown',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          if (visibleWallets.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Text(
                'No wallets yet',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                ),
              ),
            )
          else
            SizedBox(
              height: 62,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: visibleWallets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 9),
                itemBuilder: (context, index) =>
                    _buildAccountPill(visibleWallets[index]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBalanceMetric({
    required String label,
    required String value,
    VoidCallback? onTap,
    String? semanticHint,
  }) {
    return Semantics(
      button: onTap != null,
      label: label,
      value: value,
      hint: semanticHint,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.68),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 12,
                    color: Colors.white.withValues(alpha: 0.62),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccountPill(Wallet wallet) {
    final balance =
    ref.read(walletProvider.notifier).getBalanceForWallet(wallet.id);

    return Container(
      width: 158,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Color(wallet.colorValue).withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _walletIcon(wallet),
              color: Colors.white,
              size: 15,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  wallet.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Rs. ${balance.toStringAsFixed(0)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (wallet.isBackup)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(
                Icons.shield_outlined,
                color: Colors.white54,
                size: 13,
              ),
            ),
        ],
      ),
    );
  }

  IconData _walletIcon(Wallet wallet) {
    if (wallet.isBackup) return Icons.shield_outlined;
    switch (wallet.walletType.toLowerCase()) {
      case 'jazzcash':
        return Icons.phone_android_rounded;
      case 'bank':
        return Icons.account_balance_outlined;
      case 'cash':
        return Icons.payments_outlined;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }

  Future<void> _pickBudgetMonth() async {
    _dismissKeyboard();
    var selectedYear = _focusedMonth.year;
    final selected = await showDialog<DateTime>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Select month and year'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: selectedYear,
                  decoration: const InputDecoration(
                    labelText: 'Year',
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
              child: const Text('Cancel'),
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

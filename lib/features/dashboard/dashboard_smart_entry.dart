part of '../../screens/home_screen.dart';

extension _DashboardSmartEntryMethods on _HomeScreenState {
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
                                  ? 'Choose entry to delete'
                                  : repeating
                                  ? 'Choose entry to repeat'
                                  : 'Choose entry to edit',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Several entries match your command.',
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

  Future<void> _handleSmartEntryTransferCommand(
      ParsedSmartEntryCommand command,
      ) async {
    if (command.amount <= 0) {
      _showTransactionError(
        "Include an amount, for example: 'transfer 500 Cash to JazzCash'.",
        title: 'Transfer amount required',
      );
      return;
    }

    final wallets = ref.read(walletProvider);
    if (wallets.length < 2) {
      _showTransactionError(
        'Create at least two wallets before making a transfer.',
        title: 'Two wallets required',
      );
      return;
    }

    final walletNotifier = ref.read(walletProvider.notifier);
    final accounts = wallets
        .map(
          (wallet) => SmartEntryAccount(
        id: wallet.id,
        name: wallet.name,
        type: wallet.walletType,
        availableBalance:
        walletNotifier.getBalanceForWallet(wallet.id),
        isBackup: wallet.isBackup,
      ),
    )
        .toList(growable: false);
    final resolution = resolveSmartEntryTransferAccounts(
      command.rawInput,
      accounts,
    );
    if (resolution == null) {
      _showTransactionError(
        "Name both wallets, for example: 'transfer 500 Cash to JazzCash'.",
        title: 'Source and destination required',
      );
      return;
    }

    final transferConfidence = const ConfidenceEvaluator().evaluate(
      TransferCommand(
        parsed: command,
        source: SmartInputSource.typed,
      ),
      context: ConfidenceContext(
        hasExactAmount: command.amount > 0 &&
            (command.confidenceByField['amount'] ?? 0) >= 0.9,
        hasResolvedTransferSource: true,
        hasResolvedTransferDestination: true,
        transferDirectionConfidence: resolution.confidence,
      ),
    );
    if (!transferConfidence.canAutoExecute) {
      _showTransactionError(
        'I found both wallets but the transfer direction is not clear. Say “Cash se JazzCash me” or “Cash to JazzCash”.',
        title: 'Confirm transfer direction',
      );
      return;
    }

    final source = wallets.firstWhere(
          (wallet) => wallet.id == resolution.sourceAccountId,
    );
    final destination = wallets.firstWhere(
          (wallet) => wallet.id == resolution.destinationAccountId,
    );
    if (source.id == destination.id) {
      _showTransactionError(
        'Choose two different wallets.',
        title: 'Invalid transfer',
      );
      return;
    }

    final available = walletNotifier.getBalanceForWallet(source.id);
    if (command.amount > available + 0.000001) {
      _showTransactionError(
        'Available in ${source.name}: Rs. ${available.toStringAsFixed(0)}. '
            'Required: Rs. ${command.amount.toStringAsFixed(0)}.',
        title: 'Insufficient balance',
      );
      return;
    }

    final transferId = const Uuid().v4();
    final transferEntries = [
      Expense(
        id: '${transferId}_out',
        title: coreTransactionTitle('Transfer to ${destination.name}'),
        amount: command.amount,
        date: command.date,
        category: 'Transfer',
        colorValue: Colors.blue.toARGB32(),
        type: 'expense',
        walletId: source.id,
      ),
      Expense(
        id: '${transferId}_in',
        title: coreTransactionTitle('Transfer from ${source.name}'),
        amount: command.amount,
        date: command.date,
        category: 'Transfer',
        colorValue: Colors.blue.toARGB32(),
        type: 'income',
        walletId: destination.id,
      ),
    ];
    final execution = await ref
        .read(transactionExecutorProvider)
        .execute(CreateTransferCommand(
      outgoing: transferEntries.first,
      incoming: transferEntries.last,
    ));
    if (!mounted) return;
    if (!execution.succeeded) {
      _showTransactionError(
        'The source wallet changed or no longer has enough money.',
        title: 'Transfer not saved',
      );
      return;
    }

    _smartInputCtrl.clear();
    final transferAmount = command.amount.toStringAsFixed(
      command.amount == command.amount.truncateToDouble() ? 0 : 2,
    );
    _showTransferMessage(
      'Rs. $transferAmount · ${source.name} → ${destination.name}',
      title: 'Transfer completed',
      actionLabel: 'Undo',
      onAction: () async {
        await ref
            .read(transactionExecutorProvider)
            .execute(DeleteTransferCommand(transferId));
        if (!mounted) return;
        _showTransactionInfo(
          'The transfer was reversed.',
          title: 'Transfer undone',
        );
      },
    );
    unawaited(HapticFeedback.lightImpact());
  }

  Future<void> _handleSmartEntryRepeatCommand(
      ParsedSmartEntryCommand command,
      ) async {
    final wallets = ref.read(walletProvider);
    final walletNotifier = ref.read(walletProvider.notifier);
    final accounts = wallets
        .map(
          (wallet) => SmartEntryAccount(
        id: wallet.id,
        name: wallet.name,
        type: wallet.walletType,
        availableBalance: walletNotifier.getBalanceForWallet(wallet.id),
        isBackup: wallet.isBackup,
      ),
    )
        .toList(growable: false);
    final mentionedIds = findMentionedSmartEntryAccountIds(
      command.rawInput,
      accounts,
    );
    if (mentionedIds.length > 1) {
      _showTransactionError(
        'Mention only one wallet when selecting an entry to repeat.',
        title: 'Multiple wallets detected',
      );
      return;
    }

    final walletId = mentionedIds.isEmpty ? null : mentionedIds.single;
    SmartEntryAccount? mentionedAccount;
    for (final account in accounts) {
      if (account.id == walletId) mentionedAccount = account;
    }
    final allEntries = ref
        .read(expenseProvider)
        .allExpenses
        .toList(growable: false);
    final match = matchSmartEntryTransaction(
      command: command,
      entries: allEntries.map(
            (entry) => SmartEntryTransaction(
          id: entry.id,
          title: entry.title,
          amount: entry.amount,
          category: entry.category,
          type: entry.type,
          date: entry.date,
          walletId: entry.walletId,
        ),
      ),
      walletId: walletId,
      ignoredTitlePhrases: mentionedAccount == null
          ? const []
          : [mentionedAccount.name, mentionedAccount.type],
    );
    if (match.status == SmartEntryMatchStatus.notFound) {
      _showTransactionError(
        'No safe matching entry was found. Add a title, amount, date, or wallet.',
        title: 'Entry not found',
      );
      return;
    }

    Expense? source;
    if (match.status == SmartEntryMatchStatus.unique) {
      final id = match.matches.single.id;
      for (final entry in allEntries) {
        if (entry.id == id) source = entry;
      }
    } else {
      source = await _showSmartEntryMatchPicker(
        match.matches,
        deleting: false,
        repeating: true,
      );
    }
    if (source == null || !mounted) return;

    final repeated = source.copyWith(
      id: const Uuid().v4(),
      date: DateTime.now(),
      title: coreTransactionTitle(source.title),
    );
    final execution = await ref
        .read(transactionExecutorProvider)
        .execute(CreateTransactionCommand(
      repeated,
      action: TransactionAction.repeat,
    ));
    if (!mounted) return;
    if (!execution.succeeded) {
      _showTransactionError(
        source.type == 'expense'
            ? 'The original wallet does not have enough balance to repeat this expense.'
            : 'The original wallet is no longer available.',
        title: 'Entry not repeated',
      );
      return;
    }

    _smartInputCtrl.clear();
    _showTopMessage(
      title: source.type == 'income' ? 'Income repeated' : 'Expense repeated',
      message: '${repeated.title} — Rs. ${repeated.amount.toStringAsFixed(0)}',
      tone: source.type == 'income'
          ? TransactionMessageTone.income
          : TransactionMessageTone.expense,
      actionLabel: 'Undo',
      onAction: () async {
        await ref
            .read(transactionExecutorProvider)
            .execute(DeleteTransactionCommand(repeated.id));
        if (!mounted) return;
        _showTransactionInfo(
          'The repeated entry was removed.',
          title: 'Repeat undone',
        );
      },
    );
    unawaited(_rememberSmartEntryPreference(repeated));
    unawaited(HapticFeedback.lightImpact());
  }

  void _handleSmartEntryQuery(ParsedSmartEntryCommand command) {
    final metric = command.queryMetric;
    if (metric == null) {
      _showTransactionInfo(
        "Ask something like 'how much did I spend this month?'",
        title: 'Question needs more detail',
      );
      return;
    }

    final wallets = ref.read(walletProvider);
    final walletNotifier = ref.read(walletProvider.notifier);
    final accounts = wallets
        .map(
          (wallet) => SmartEntryAccount(
        id: wallet.id,
        name: wallet.name,
        type: wallet.walletType,
        availableBalance: walletNotifier.getBalanceForWallet(wallet.id),
        isBackup: wallet.isBackup,
      ),
    )
        .toList(growable: false);
    final mentionedIds = findMentionedSmartEntryAccountIds(
      command.rawInput,
      accounts,
    );
    if (mentionedIds.length > 1) {
      _showTransactionError(
        'Mention one wallet at a time for a precise answer.',
        title: 'Multiple wallets detected',
      );
      return;
    }

    if (metric == SmartEntryQueryMetric.balance) {
      if (mentionedIds.isEmpty) {
        final total = wallets.fold<double>(
          0,
              (sum, wallet) => sum + walletNotifier.getBalanceForWallet(wallet.id),
        );
        _showTransactionInfo(
          'Rs. ${total.toStringAsFixed(0)} across ${wallets.length} wallet${wallets.length == 1 ? '' : 's'}.',
          title: 'Total wallet balance',
        );
      } else {
        final wallet = wallets.firstWhere(
              (item) => item.id == mentionedIds.single,
        );
        final balance = walletNotifier.getBalanceForWallet(wallet.id);
        _showTransactionInfo(
          'Rs. ${balance.toStringAsFixed(0)} available.',
          title: '${wallet.name} balance',
        );
      }
      _smartInputCtrl.clear();
      return;
    }

    var entries = ref
        .read(expenseProvider)
        .allExpenses
        .where((entry) => entry.category != 'Transfer')
        .where((entry) => matchesSmartEntryTimeRange(
      entry.date,
      command.timeRange,
    ));
    if (mentionedIds.isNotEmpty) {
      final walletId = mentionedIds.single;
      entries = entries.where((entry) => entry.walletId == walletId);
    }
    final hasCategory = command.category != 'General' &&
        command.confidenceByField['category']! >= 0.8;
    if (hasCategory) {
      entries = entries.where((entry) => entry.category == command.category);
    } else {
      final title = _smartQueryTitle(command.title);
      if (title.isNotEmpty) {
        entries = entries.where(
              (entry) => entry.title.toLowerCase().contains(title.toLowerCase()),
        );
      }
    }
    final matching = entries.toList(growable: false);
    final income = matching
        .where((entry) => entry.type == 'income')
        .fold<double>(0, (sum, entry) => sum + entry.amount);
    final spending = matching
        .where((entry) => entry.type == 'expense')
        .fold<double>(0, (sum, entry) => sum + entry.amount);
    final period = _smartTimeRangeLabel(command.timeRange);
    final subject = hasCategory ? ' · ${command.category}' : '';

    switch (metric) {
      case SmartEntryQueryMetric.spending:
        _showTransactionInfo(
          '${matching.where((entry) => entry.type == 'expense').length} expense${matching.where((entry) => entry.type == 'expense').length == 1 ? '' : 's'}$subject.',
          title: 'Rs. ${spending.toStringAsFixed(0)} spent · $period',
        );
        break;
      case SmartEntryQueryMetric.income:
        _showTransactionInfo(
          '${matching.where((entry) => entry.type == 'income').length} income entr${matching.where((entry) => entry.type == 'income').length == 1 ? 'y' : 'ies'}$subject.',
          title: 'Rs. ${income.toStringAsFixed(0)} received · $period',
        );
        break;
      case SmartEntryQueryMetric.net:
        _showTransactionInfo(
          'Income Rs. ${income.toStringAsFixed(0)} · Expenses Rs. ${spending.toStringAsFixed(0)}.',
          title: 'Net Rs. ${(income - spending).toStringAsFixed(0)} · $period',
        );
        break;
      case SmartEntryQueryMetric.transactionCount:
        final type = command.entryTypeFilter;
        final count = type == null
            ? matching.length
            : matching.where((entry) => entry.type == type).length;
        _showTransactionInfo(
          '${type == null ? 'Income and expense' : type == 'income' ? 'Income' : 'Expense'} records$subject.',
          title: '$count transactions · $period',
        );
        break;
      case SmartEntryQueryMetric.balance:
        break;
    }
    _smartInputCtrl.clear();
  }

  void _handleSmartEntrySearch(ParsedSmartEntryCommand command) {
    final category = command.category != 'General' &&
        command.confidenceByField['category']! >= 0.8
        ? command.category
        : 'All';
    var query = _smartQueryTitle(command.title);
    if (category != 'All' &&
        query.toLowerCase() == category.toLowerCase()) {
      query = '';
    }
    ref.read(appNavigationProvider.notifier).openDashboard();
    setState(() {
      _activePrimaryTab = PrimaryLedgerTab.main;
      _isSearching = true;
      _searchQuery = query;
      _selectedCategoryTab = category;
      _smartEntryTypeFilter = command.entryTypeFilter;
      _smartEntrySearchRange = command.timeRange;
      _smartEntrySearchAllHistory = true;
    });
    _primaryTabsController.select(PrimaryLedgerTab.main);
    _smartInputCtrl.clear();
    _showTransactionInfo(
      'Close search to return to the normal monthly view.',
      title: 'Transaction filters applied',
    );
  }

  Future<void> _handleSmartEntryNavigation(
      ParsedSmartEntryCommand command,
      ) async {
    final target = command.navigationTarget;
    if (target == null) {
      _showTransactionInfo(
        'Try Home, Stats, Wallets, Udhaar, Settings, or About.',
        title: 'Screen not recognized',
      );
      return;
    }
    _smartInputCtrl.clear();
    if (target == 'Wallets') {
      await _openIncomeAccounts();
      return;
    }
    if (target == 'Dashboard' || target == 'Home' || target == 'Main') {
      _openPrimaryLedgerTab(PrimaryLedgerTab.main);
      return;
    }
    if (target == 'Udhaar' || target == 'Udhar') {
      _openPrimaryLedgerTab(PrimaryLedgerTab.udhar);
      return;
    }
    final section = AppSection.fromLabel(target);
    if (section != null) {
      _changeSection(section);
      return;
    }
    _showTransactionInfo(
      'Try Home, Stats, Wallets, Udhaar, Settings, or About.',
      title: 'Screen not recognized',
    );
  }

  String _smartQueryTitle(String value) {
    final normalized = value.trim();
    const generic = {
      '',
      'Transaction',
      'Quick Expense',
      'Income Allowance',
      'Income / Allowance',
    };
    return generic.contains(normalized) ? '' : normalized;
  }

  String _smartTimeRangeLabel(SmartEntryTimeRange range) {
    switch (range) {
      case SmartEntryTimeRange.today:
        return 'today';
      case SmartEntryTimeRange.yesterday:
        return 'yesterday';
      case SmartEntryTimeRange.thisWeek:
        return 'this week';
      case SmartEntryTimeRange.lastWeek:
        return 'last week';
      case SmartEntryTimeRange.thisMonth:
        return 'this month';
      case SmartEntryTimeRange.lastMonth:
        return 'last month';
      case SmartEntryTimeRange.allTime:
        return 'all time';
    }
  }

  Future<void> _handleSmartEntryMutationCommand(
      SmartInputPlan plan,
      ) async {
    final command = plan.parsed;
    final mutation = plan.command as MutationCommand;
    final deleting = mutation.deleting;
    if (!deleting && mutation.patch.isEmpty) {
      _showTransactionError(
        "Say what to change, for example: 'change burger amount to 600' or 'headphones ka naam Kurch karo'.",
        title: 'Change required',
      );
      return;
    }
    if (mutation.patch.amount != null && mutation.patch.amount! <= 0) {
      _showTransactionError(
        'The new amount must be greater than zero.',
        title: 'Invalid amount',
      );
      return;
    }

    final wallets = ref.read(walletProvider);
    final walletNotifier = ref.read(walletProvider.notifier);
    final smartAccounts = wallets
        .map(
          (wallet) => SmartEntryAccount(
        id: wallet.id,
        name: wallet.name,
        type: wallet.walletType,
        availableBalance:
        walletNotifier.getBalanceForWallet(wallet.id),
        isBackup: wallet.isBackup,
      ),
    )
        .toList(growable: false);
    final mentionedWalletIds = findMentionedSmartEntryAccountIds(
      command.rawInput,
      smartAccounts,
    );
    if (mentionedWalletIds.length > 1) {
      _showTransactionError(
        'Mention only one wallet so the correct entry can be identified.',
        title: 'Multiple wallets detected',
      );
      return;
    }

    final mentionedWalletId = mentionedWalletIds.isEmpty
        ? null
        : mentionedWalletIds.single;
    SmartEntryAccount? mentionedAccount;
    if (mentionedWalletId != null) {
      for (final account in smartAccounts) {
        if (account.id == mentionedWalletId) {
          mentionedAccount = account;
          break;
        }
      }
    }

    final allEntries = ref
        .read(expenseProvider)
        .allExpenses
        .toList(growable: false);
    final match = matchSmartEntryTransaction(
      command: command,
      entries: allEntries.map(
            (entry) => SmartEntryTransaction(
          id: entry.id,
          title: entry.title,
          amount: entry.amount,
          category: entry.category,
          type: entry.type,
          date: entry.date,
          walletId: entry.walletId,
        ),
      ),
      walletId: mentionedWalletId,
      ignoredTitlePhrases: mentionedAccount == null
          ? const []
          : [
        mentionedAccount.name,
        mentionedAccount.type,
        'cash in hand',
        'jazz cash',
        'jazzcash',
      ],
      selectorTitle: mutation.selector.title,
      selectorAmount: mutation.selector.amount,
      selectorDate: mutation.selector.date,
    );

    if (match.status == SmartEntryMatchStatus.notFound) {
      _showTransactionError(
        deleting
            ? 'No safe matching entry was found. Add a title, amount, date, or wallet.'
            : 'No safe matching entry was found. Name the entry you want to edit.',
        title: 'Entry not found',
      );
      return;
    }

    if (match.status == SmartEntryMatchStatus.unique) {
      final confidence = const ConfidenceEvaluator().evaluate(
        plan.command,
        context: ConfidenceContext(
          hasUniqueTarget: true,
          targetConfidence: match.confidence,
        ),
      );
      if (!confidence.canAutoExecute) {
        _showTransactionError(
          'The matching entry is not certain enough to change automatically. Add its amount, date, or wallet.',
          title: 'Review target entry',
        );
        return;
      }
    }

    Expense? target;
    if (match.status == SmartEntryMatchStatus.unique) {
      final targetId = match.matches.single.id;
      for (final entry in allEntries) {
        if (entry.id == targetId) {
          target = entry;
          break;
        }
      }
    } else {
      target = await _showSmartEntryMatchPicker(
        match.matches,
        deleting: deleting,
      );
    }
    if (target == null || !mounted) return;

    if (deleting) {
      if (target.type == 'income') {
        final available =
        walletNotifier.getBalanceForWallet(target.walletId);
        if (available + 0.000001 < target.amount) {
          _showTransactionError(
            'Deleting this income would make the wallet balance negative.',
            title: 'Income cannot be deleted',
          );
          return;
        }
      }

      final deleteResult = await ref
          .read(transactionExecutorProvider)
          .execute(DeleteTransactionCommand(target.id));
      if (!mounted) return;
      if (!deleteResult.succeeded) {
        _showTransactionError(
          'The entry changed before it could be deleted. Try again.',
          title: 'Entry not deleted',
        );
        return;
      }

      _smartInputCtrl.clear();
      final deletedEntry = target;
      final deletedAmount =
      deletedEntry.amount.toStringAsFixed(0);
      _showDeletionMessage(
        '${deletedEntry.title} — Rs. $deletedAmount',
        title: 'Entry moved to Trash',
        actionLabel: 'Undo',
        onAction: () async {
          final restoreResult = await ref
              .read(transactionExecutorProvider)
              .execute(RestoreTransactionCommand(deletedEntry.id));
          if (!mounted) return;
          if (restoreResult.succeeded) {
            _showTransactionInfo(
              'The deleted entry was restored.',
              title: 'Deletion undone',
            );
          } else {
            _showTransactionError(
              'The entry could not be restored because the wallet changed.',
              title: 'Undo failed',
            );
          }
        },
      );
      unawaited(HapticFeedback.lightImpact());
      return;
    }

    final originalEntry = target;
    String? updatedCategory = mutation.patch.category;
    if (updatedCategory != null) {
      final categories = ref.read(categoryProvider);
      final matches = categories.where(
            (category) =>
        category.toLowerCase() == updatedCategory!.toLowerCase(),
      );
      if (matches.isEmpty) {
        _showTransactionError(
          'Choose an existing category: ${categories.join(', ')}.',
          title: 'Category not found',
        );
        return;
      }
      updatedCategory = matches.first;
    }
    final updatedEntry = originalEntry.copyWith(
      amount: mutation.patch.amount,
      title: mutation.patch.title == null
          ? null
          : coreTransactionTitle(mutation.patch.title!),
      category: updatedCategory,
      date: mutation.patch.date,
      walletId: mutation.patch.walletId,
    );
    if (updatedEntry.amount == originalEntry.amount &&
        updatedEntry.title == originalEntry.title &&
        updatedEntry.category == originalEntry.category &&
        updatedEntry.date == originalEntry.date &&
        updatedEntry.walletId == originalEntry.walletId) {
      _showTransactionInfo(
        'The entry already has these details.',
        title: 'No change needed',
      );
      return;
    }

    final updateResult = await ref
        .read(transactionExecutorProvider)
        .execute(UpdateTransactionCommand(
      existingId: originalEntry.id,
      updated: updatedEntry,
    ));
    if (!mounted) return;
    if (!updateResult.succeeded) {
      _showTransactionError(
        'The wallet cannot support this change, or the entry changed. Review its balance and try again.',
        title: 'Entry not updated',
      );
      return;
    }

    _smartInputCtrl.clear();
    _showTransactionSuccess(
      '${updatedEntry.title} · Rs. ${updatedEntry.amount.toStringAsFixed(0)} · ${updatedEntry.category}',
      title: 'Entry updated',
      actionLabel: 'Undo',
      onAction: () async {
        final restoreResult = await ref
            .read(transactionExecutorProvider)
            .execute(UpdateTransactionCommand(
          existingId: originalEntry.id,
          updated: originalEntry,
        ));
        if (!mounted) return;
        if (restoreResult.succeeded) {
          _showTransactionInfo(
            'The previous amount was restored.',
            title: 'Edit undone',
          );
        } else {
          _showTransactionError(
            'The previous amount could not be restored because the wallet changed.',
            title: 'Undo failed',
          );
        }
      },
    );
    unawaited(HapticFeedback.lightImpact());
  }

  Future<bool> _processNLP(
      String text, {
        SmartInputSource source = SmartInputSource.typed,
      }) async {
    _dismissKeyboard();
    final normalized = text.trim();
    if (normalized.isEmpty) return false;

    final categories = ref.read(categoryProvider);
    final plan = ref.read(smartEntryControllerProvider).parse(
      normalized,
      categories,
      source: source,
      accounts: _parsingAccounts(),
    );
    _debugSmartInputPlan(plan);
    final command = plan.parsed;
    final canonicalInput = plan.normalizedText;
    if (!command.intent.isTransactionAddition) {
      if (command.intent == SmartEntryIntent.deleteEntry ||
          command.intent == SmartEntryIntent.editEntry) {
        await _handleSmartEntryMutationCommand(plan);
        return _smartInputCtrl.text.trim().isEmpty;
      }

      String message;
      String title;
      switch (command.intent) {
        case SmartEntryIntent.transfer:
          await _handleSmartEntryTransferCommand(command);
          return _smartInputCtrl.text.trim().isEmpty;
        case SmartEntryIntent.repeatEntry:
          await _handleSmartEntryRepeatCommand(command);
          return _smartInputCtrl.text.trim().isEmpty;
        case SmartEntryIntent.query:
          _handleSmartEntryQuery(command);
          return _smartInputCtrl.text.trim().isEmpty;
        case SmartEntryIntent.searchEntries:
          _handleSmartEntrySearch(command);
          return _smartInputCtrl.text.trim().isEmpty;
        case SmartEntryIntent.navigate:
          await _handleSmartEntryNavigation(command);
          return _smartInputCtrl.text.trim().isEmpty;
        case SmartEntryIntent.unknown:
          title = 'Command not recognized';
          message = 'Try an expense or income command with an amount.';
          break;
        case SmartEntryIntent.deleteEntry:
        case SmartEntryIntent.editEntry:
        case SmartEntryIntent.addExpense:
        case SmartEntryIntent.addIncome:
          return false;
      }
      _showTransactionInfo(message, title: title);
      return false;
    }

    final result = command.toLegacyMap();
    final learnedPreference = _learnedPreferenceFor(command.title);
    if (result['type'] == 'expense' &&
        result['category'] == 'General' &&
        learnedPreference != null &&
        categories.contains(learnedPreference.category)) {
      result['category'] = learnedPreference.category;
    }
    final amount = result['amount'];
    if (amount is! num || !amount.isFinite || amount <= 0) {
      _showTransactionError(
        "Include an amount, for example: '500 biryani' or '1.5k petrol from JazzCash'.",
        title: 'Amount not detected',
      );
      return false;
    }

    final wallets = ref.read(walletProvider);
    if (wallets.isEmpty) {
      _showTransactionError(
        'Create a Cash or JazzCash wallet before using Smart Entry.',
        title: 'Wallet required',
      );
      return false;
    }

    final type = result['type'] == 'income' ? 'income' : 'expense';
    final amountValue = amount.toDouble();
    final walletNotifier = ref.read(walletProvider.notifier);
    final smartAccounts = wallets
        .map(
          (wallet) => SmartEntryAccount(
        id: wallet.id,
        name: wallet.name,
        type: wallet.walletType,
        availableBalance:
        walletNotifier.getBalanceForWallet(wallet.id),
        isBackup: wallet.isBackup,
      ),
    )
        .toList(growable: false);
    final mentionedWalletId =
    findMentionedSmartEntryAccountId(canonicalInput, smartAccounts);
    final configuredDefaultWallet =
    _selectedSmartEntryWallet(wallets);
    String? learnedWalletId;
    if (mentionedWalletId == null && configuredDefaultWallet == null) {
      final candidateId = learnedPreference?.walletId;
      if (candidateId != null &&
          wallets.any((wallet) => wallet.id == candidateId)) {
        learnedWalletId = candidateId;
      }
    }
    final resolvedWalletId = resolveSmartEntryAccount(
      input: canonicalInput,
      accounts: smartAccounts,
      transactionType: type,
      amount: amountValue,
      preferredAccountId: configuredDefaultWallet?.id ?? learnedWalletId,
    );

    final semanticConfidence = const ConfidenceEvaluator().evaluate(
      plan.command,
      context: ConfidenceContext(
        hasResolvedWallet: resolvedWalletId != null,
        hasExactAmount:
        (command.confidenceByField['amount'] ?? 0) >= 0.9,
      ),
    );
    assert(() {
      debugPrint(
        '[SmartEntry confidence] '
            'disposition=${semanticConfidence.disposition} '
            'score=${semanticConfidence.score.toStringAsFixed(3)} '
            'reasons=${semanticConfidence.reasons.join(' | ')}',
      );
      return true;
    }());

    if (!plan.requiresAsrReview &&
        semanticConfidence.canAutoExecute &&
        shouldAutoSaveSmartEntry(
          result,
          hasResolvedWallet: resolvedWalletId != null,
          semanticConfidence: semanticConfidence.score,
        )) {
      final wallet = wallets.firstWhere(
            (item) => item.id == resolvedWalletId,
      );
      final entry = Expense(
        id: const Uuid().v4(),
        title: _smartEntryTitle(result, wallet, type),
        amount: amountValue,
        category: type == 'income'
            ? 'Income / Allowance'
            : result['category']?.toString() ?? 'General',
        date: result['date'] is DateTime
            ? result['date'] as DateTime
            : DateTime.now(),
        colorValue:
        Color(ref.read(settingsProvider).profileColorValue).toARGB32(),
        type: type,
        walletId: resolvedWalletId!,
      );

      final execution = await ref
          .read(transactionExecutorProvider)
          .execute(CreateTransactionCommand(entry));
      if (!mounted) return false;
      if (!execution.succeeded) {
        _showTransactionError(
          'The selected wallet changed or no longer has enough balance. Try the entry again.',
          title: 'Smart Entry not saved',
        );
        return false;
      }

      _smartInputCtrl.clear();
      FocusScope.of(context).unfocus();
      _showTopMessage(
        title: type == 'income' ? 'Income added' : 'Expense saved',
        message:
            '${entry.title} — Rs. ${entry.amount.toStringAsFixed(0)} · ${wallet.name}',
        tone: type == 'income'
            ? TransactionMessageTone.income
            : TransactionMessageTone.expense,
        actionLabel: 'Undo',
        onAction: () async {
          final deleteResult = await ref
              .read(transactionExecutorProvider)
              .execute(DeleteTransactionCommand(entry.id));
          if (!mounted) return;
          if (deleteResult.succeeded) {
            _showTransactionInfo(
              'The instant Smart Entry was removed.',
              title: 'Entry undone',
            );
          }
        },
      );
      unawaited(_rememberSmartEntryPreference(entry));
      unawaited(HapticFeedback.lightImpact());
      return true;
    }

    final defaultAccounts = smartAccounts.where((account) {
      final accountType = account.type.toLowerCase();
      return !account.isBackup &&
          (accountType == 'cash' || accountType == 'jazzcash');
    }).toList(growable: false);
    final defaultsAreEmpty = defaultAccounts.isEmpty ||
        defaultAccounts.every((account) => account.availableBalance <= 0);
    final reviewMessage = plan.requiresAsrReview
        ? 'Voice recognition corrected a similar-sounding financial word. Verify the title and amount before saving.'
        : resolvedWalletId != null &&
        !semanticConfidence.canAutoExecute
        ? 'Review the detected title, amount, category, date, and wallet before saving.'
        : mentionedWalletId != null
        ? 'The named wallet cannot cover this expense. Choose another wallet before saving.'
        : configuredDefaultWallet != null
        ? 'Your default wallet, ${configuredDefaultWallet.name}, cannot cover this expense. Choose another funded account.'
        : learnedWalletId != null
        ? 'The wallet previously used for this entry cannot cover it. Choose another funded wallet.'
        : defaultsAreEmpty
        ? 'Cash and JazzCash are empty. Choose the wallet that should receive or pay this entry.'
        : 'Cash and JazzCash cannot cover this amount. Choose another funded wallet.';

    final confirmed = await _showAddOrEditModal(
      prefilledAmount:
      amountValue == amountValue.truncateToDouble()
          ? amountValue.toStringAsFixed(0)
          : amountValue.toStringAsFixed(2),
      prefilledTitle: result['title']?.toString(),
      prefilledCategory: result['category']?.toString(),
      prefilledDate: result['date'] is DateTime
          ? result['date'] as DateTime
          : DateTime.now(),
      preselectedWalletId: mentionedWalletId ??
          configuredDefaultWallet?.id ??
          learnedWalletId,
      initialType: type,
      reviewMessage: reviewMessage,
    );

    if (confirmed == true && mounted) {
      _smartInputCtrl.clear();
      if (type == 'income') {
        _showIncomeMessage('The Smart Entry was saved to the selected wallet.');
      } else {
        _showExpenseMessage('The Smart Entry was saved to the selected wallet.');
      }
    }
    if (mounted) FocusScope.of(context).unfocus();
    return confirmed == true && mounted;
  }

  void _debugSmartInputPlan(SmartInputPlan plan) {
    assert(() {
      final smartCommand = plan.command;
      var selector = 'none';
      var patch = 'none';
      if (smartCommand is MutationCommand) {
        selector = '{title: ${smartCommand.selector.title}, '
            'amount: ${smartCommand.selector.amount}, '
            'date: ${smartCommand.selector.date}, '
            'type: ${smartCommand.selector.transactionType}}';
        patch = '{title: ${smartCommand.patch.title}, '
            'amount: ${smartCommand.patch.amount}, '
            'category: ${smartCommand.patch.category}, '
            'date: ${smartCommand.patch.date}, '
            'wallet: ${smartCommand.patch.walletId}}';
      }
      debugPrint(
        '[SmartEntry parse] original="${plan.originalText}" '
            'normalized="${plan.normalizedText}" '
            'intent=${plan.parsed.intent.wireName} '
            'selector=$selector patch=$patch '
            'amount=${plan.parsed.amount} title="${plan.parsed.title}" '
            'confidence=${plan.parsed.confidence.toStringAsFixed(3)} '
            'requiresAsrReview=${plan.requiresAsrReview}',
      );
      return true;
    }());
  }

  String _smartEntryTitle(
      Map<String, dynamic> result,
      Wallet wallet,
      String type,
      ) {
    var title = result['title']?.toString().trim() ?? '';
    final removable = <String>[
      wallet.name,
      wallet.walletType,
      'cash in hand',
      'jazz cash',
      'jazzcash',
    ];

    for (final phrase in removable) {
      final normalized = phrase.trim();
      if (normalized.isEmpty) continue;
      title = title.replaceAll(
        RegExp(
          '\\b${RegExp.escape(normalized)}\\b',
          caseSensitive: false,
        ),
        ' ',
      );
    }
    title = title
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'^(From|Via|Using)\s+', caseSensitive: false), '');

    if (title.isEmpty || title.toLowerCase() == 'quick expense') {
      if (type == 'income') return 'Income Allowance';
      final category = result['category']?.toString().trim() ?? '';
      final fallback = category.isEmpty || category.toLowerCase() == 'general'
          ? 'Quick Expense'
          : category;
      return coreTransactionTitle(fallback);
    }
    return coreTransactionTitle(title);
  }


}

part of '../../screens/home_screen.dart';

extension _DashboardSmartEntryQueryMethods on _HomeScreenState {
  Future<void> _handleSmartEntryRepeatCommand(
      ParsedSmartEntryCommand command,
      ) async {
    final wallets = ref.read(walletProvider);
    final accounts = wallets
        .map(
          (wallet) => SmartEntryAccount(
        id: wallet.id,
        name: wallet.name,
        type: wallet.walletType,
        availableBalance: ref.read(walletBalanceProvider(wallet.id)),
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

  Future<void> _handleSmartEntryUdharQuery(
    SmartEntryQueryMetric metric,
  ) async {
    if (!Hive.isBoxOpen('debts')) {
      await Hive.openBox<DebtEntry>('debts');
    }
    if (!mounted) return;

    final active = Hive.box<DebtEntry>('debts')
        .values
        .where(
          (entry) => entry.deletedAt == null && entry.settledAt == null,
        )
        .toList(growable: false);

    final receivableEntries =
        active.where((entry) => entry.type == 'lent').toList(growable: false);
    final payableEntries = active
        .where((entry) => entry.type == 'borrowed')
        .toList(growable: false);
    final receivable = receivableEntries.fold<double>(
      0,
      (sum, entry) => sum + entry.amount,
    );
    final payable = payableEntries.fold<double>(
      0,
      (sum, entry) => sum + entry.amount,
    );

    if (metric == SmartEntryQueryMetric.udharReceivable) {
      _showTransactionInfo(
        '${receivableEntries.length} active record${receivableEntries.length == 1 ? '' : 's'}.',
        title: 'Rs. ${receivable.toStringAsFixed(0)} to receive',
      );
      return;
    }
    if (metric == SmartEntryQueryMetric.udharPayable) {
      _showTransactionInfo(
        '${payableEntries.length} active record${payableEntries.length == 1 ? '' : 's'}.',
        title: 'Rs. ${payable.toStringAsFixed(0)} to pay',
      );
      return;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final overdue = active.where((entry) {
      final due = entry.dueDate;
      if (due == null) return false;
      final dueDay = DateTime(due.year, due.month, due.day);
      return dueDay.isBefore(today);
    }).length;

    _showTransactionInfo(
      'To receive Rs. ${receivable.toStringAsFixed(0)} · '
      'To pay Rs. ${payable.toStringAsFixed(0)} · '
      '${active.length} active · $overdue overdue.',
      title: 'Udhar net Rs. ${(receivable - payable).toStringAsFixed(0)}',
    );
  }

  Future<void> _handleSmartEntryAppControl(
    ParsedSmartEntryCommand command,
  ) async {
    final action = command.appAction;
    if (action == null) {
      _showTransactionInfo(
        'Try dark mode, monthly PDF, scan receipt, reminders, spoken confirmations, backup, language, or app lock.',
        title: 'App control not recognized',
      );
      return;
    }

    _smartInputCtrl.clear();

    if (action == SmartEntryAppAction.scanReceipt) {
      await _scanReceiptIntoInput();
      return;
    }

    if (action == SmartEntryAppAction.openDrawer) {
      final scaffold = Scaffold.maybeOf(context);
      if (scaffold != null && scaffold.hasDrawer) {
        scaffold.openDrawer();
        _announceVoiceMessage('App menu opened.');
      } else {
        _showTransactionInfo(
          'The app menu is not available on this screen.',
          title: 'Menu unavailable',
        );
      }
      return;
    }

    if (action == SmartEntryAppAction.themeColorChange) {
      final selection = _themeColorSelection(command.rawInput);
      ref
          .read(settingsProvider.notifier)
          .updateProfileColor(selection.key);
      if (!mounted) return;
      _showTransactionInfo(
        selection.value == 'Random'
            ? 'A new theme color was selected.'
            : '${selection.value} theme color is now active.',
        title: selection.value == 'Random'
            ? 'Theme color changed'
            : '${selection.value} theme',
      );
      return;
    }

    if (action == SmartEntryAppAction.clearSearchFilters) {
      final hadFilters = _isSearching ||
          _searchQuery.isNotEmpty ||
          _selectedCategoryTab != 'All' ||
          _smartEntryTypeFilter != null ||
          _smartEntrySearchRange != null ||
          _smartEntrySearchAllHistory;
      setState(() {
        _isSearching = false;
        _searchQuery = '';
        _selectedCategoryTab = 'All';
        _smartEntryTypeFilter = null;
        _smartEntrySearchRange = null;
        _smartEntrySearchAllHistory = false;
      });
      _searchQueryNotifier.value = '';
      _categorySelectionNotifier.value = 'All';
      _showTransactionInfo(
        hadFilters
            ? 'Search and transaction filters were cleared.'
            : 'No transaction filters are active.',
        title: hadFilters ? 'Filters cleared' : 'Nothing to clear',
      );
      return;
    }

    if (action == SmartEntryAppAction.runMonthlyPlanCommand) {
      ref.read(appActionProvider.notifier).request(
        AppActionType.runMonthlyPlanCommand,
        month: parseReferencedMonth(command.rawInput),
        text: command.rawInput,
      );
      _changeSection(AppSection.budget);
      return;
    }

    AppActionType? delegatedAction;
    switch (action) {
      case SmartEntryAppAction.openMonthlyPdf:
        delegatedAction = AppActionType.openMonthlyPdf;
        break;
      case SmartEntryAppAction.openBackup:
        delegatedAction = AppActionType.openBackup;
        break;
      case SmartEntryAppAction.persistentQuickEntryOn:
        delegatedAction = AppActionType.persistentQuickEntryOn;
        break;
      case SmartEntryAppAction.persistentQuickEntryOff:
        delegatedAction = AppActionType.persistentQuickEntryOff;
        break;
      case SmartEntryAppAction.smartRemindersOn:
        delegatedAction = AppActionType.smartRemindersOn;
        break;
      case SmartEntryAppAction.smartRemindersOff:
        delegatedAction = AppActionType.smartRemindersOff;
        break;
      case SmartEntryAppAction.spokenConfirmationsOn:
        delegatedAction = AppActionType.spokenConfirmationsOn;
        break;
      case SmartEntryAppAction.spokenConfirmationsOff:
        delegatedAction = AppActionType.spokenConfirmationsOff;
        break;
      case SmartEntryAppAction.smartEntryLanguageRomanUrdu:
        delegatedAction = AppActionType.smartEntryLanguageRomanUrdu;
        break;
      case SmartEntryAppAction.smartEntryLanguageEnglish:
        delegatedAction = AppActionType.smartEntryLanguageEnglish;
        break;
      case SmartEntryAppAction.appLockOn:
        delegatedAction = AppActionType.appLockOn;
        break;
      case SmartEntryAppAction.appLockOff:
        delegatedAction = AppActionType.appLockOff;
        break;
      case SmartEntryAppAction.darkModeOn:
      case SmartEntryAppAction.darkModeOff:
      case SmartEntryAppAction.darkModeToggle:
      case SmartEntryAppAction.themeColorChange:
      case SmartEntryAppAction.openDrawer:
      case SmartEntryAppAction.scanReceipt:
      case SmartEntryAppAction.runMonthlyPlanCommand:
      case SmartEntryAppAction.clearSearchFilters:
        delegatedAction = null;
        break;
    }
    if (delegatedAction != null) {
      ref.read(appActionProvider.notifier).request(
        delegatedAction,
        month: delegatedAction == AppActionType.openMonthlyPdf
            ? resolveMonthlyPdfTargetMonth(command.rawInput)
            : null,
        spokenFeedback: _isProcessingVoiceCommand,
      );
      _changeSection(AppSection.settings);
      return;
    }

    final settings = ref.read(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final currentlyDark = settings.themeMode == 'dark';

    late final bool enableDark;
    switch (action) {
      case SmartEntryAppAction.darkModeOn:
        enableDark = true;
        break;
      case SmartEntryAppAction.darkModeOff:
        enableDark = false;
        break;
      case SmartEntryAppAction.darkModeToggle:
        enableDark = !currentlyDark;
        break;
      case SmartEntryAppAction.themeColorChange:
      case SmartEntryAppAction.openDrawer:
      case SmartEntryAppAction.openMonthlyPdf:
      case SmartEntryAppAction.scanReceipt:
      case SmartEntryAppAction.openBackup:
      case SmartEntryAppAction.persistentQuickEntryOn:
      case SmartEntryAppAction.persistentQuickEntryOff:
      case SmartEntryAppAction.smartRemindersOn:
      case SmartEntryAppAction.smartRemindersOff:
      case SmartEntryAppAction.spokenConfirmationsOn:
      case SmartEntryAppAction.spokenConfirmationsOff:
      case SmartEntryAppAction.smartEntryLanguageRomanUrdu:
      case SmartEntryAppAction.smartEntryLanguageEnglish:
      case SmartEntryAppAction.appLockOn:
      case SmartEntryAppAction.appLockOff:
      case SmartEntryAppAction.runMonthlyPlanCommand:
      case SmartEntryAppAction.clearSearchFilters:
        return;
    }

    if (currentlyDark != enableDark) {
      notifier.updateThemeMode(enableDark ? 'dark' : 'light');
    }
    if (!mounted) return;
    _showTransactionInfo(
      enableDark
          ? 'Dark mode is now enabled.'
          : 'Light mode is now enabled.',
      title: enableDark ? 'Dark mode on' : 'Dark mode off',
    );
  }

  Future<void> _handleSmartEntryQuery(ParsedSmartEntryCommand command) async {
    final metric = command.queryMetric;
    if (metric == null) {
      _showTransactionInfo(
        "Ask something like 'how much did I spend this month?'",
        title: 'Question needs more detail',
      );
      return;
    }

    if (metric == SmartEntryQueryMetric.udharSummary ||
        metric == SmartEntryQueryMetric.udharReceivable ||
        metric == SmartEntryQueryMetric.udharPayable) {
      await _handleSmartEntryUdharQuery(metric);
      _smartInputCtrl.clear();
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
        availableBalance: ref.read(walletBalanceProvider(wallet.id)),
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
        final total = ref.read(totalAvailableProvider);
        _showTransactionInfo(
          'Rs. ${total.toStringAsFixed(0)} across ${wallets.length} wallet${wallets.length == 1 ? '' : 's'}.',
          title: 'Total wallet balance',
        );
      } else {
        final wallet = wallets.firstWhere(
              (item) => item.id == mentionedIds.single,
        );
        final balance = ref.read(walletBalanceProvider(wallet.id));
        _showTransactionInfo(
          'Rs. ${balance.toStringAsFixed(0)} available.',
          title: '${wallet.name} balance',
        );
      }
      _smartInputCtrl.clear();
      return;
    }

    final referencedMonth = _resolveSmartQueryMonth(command.rawInput);
    var entries = ref
        .read(expenseProvider)
        .allExpenses
        .where((entry) => entry.category != 'Transfer');
    if (referencedMonth != null) {
      entries = entries.where(
        (entry) =>
            entry.date.year == referencedMonth.year &&
            entry.date.month == referencedMonth.month,
      );
    } else {
      entries = entries.where(
        (entry) => matchesSmartEntryTimeRange(
          entry.date,
          command.timeRange,
        ),
      );
    }
    if (mentionedIds.isNotEmpty) {
      final walletId = mentionedIds.single;
      entries = entries.where((entry) => entry.walletId == walletId);
    }
    final hasCategory = command.category != 'General' &&
        command.confidenceByField['category']! >= 0.8;
    if (hasCategory) {
      entries = entries.where((entry) => entry.category == command.category);
    } else if (metric != SmartEntryQueryMetric.summary) {
      final title = _smartQueryTitleWithoutMonth(
        command.title,
        referencedMonth,
      );
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
    final period = referencedMonth == null
        ? _smartTimeRangeLabel(command.timeRange)
        : DateFormat.yMMMM().format(referencedMonth);
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
      case SmartEntryQueryMetric.summary:
        final expenseEntries =
            matching.where((entry) => entry.type == 'expense').toList();
        final byCategory = <String, double>{};
        for (final entry in expenseEntries) {
          byCategory.update(
            entry.category,
            (value) => value + entry.amount,
            ifAbsent: () => entry.amount,
          );
        }
        MapEntry<String, double>? topCategory;
        for (final entry in byCategory.entries) {
          if (topCategory == null || entry.value > topCategory.value) {
            topCategory = entry;
          }
        }
        final topText = topCategory == null
            ? 'No expense category yet.'
            : 'Top: ${topCategory.key} Rs. ${topCategory.value.toStringAsFixed(0)}.';
        _showTransactionInfo(
          'Income Rs. ${income.toStringAsFixed(0)} · Spent Rs. ${spending.toStringAsFixed(0)} · '
          'Net Rs. ${(income - spending).toStringAsFixed(0)} · '
          '${matching.length} entr${matching.length == 1 ? 'y' : 'ies'}. $topText',
          title: 'Financial summary · $period',
        );
        break;
      case SmartEntryQueryMetric.balance:
      case SmartEntryQueryMetric.udharSummary:
      case SmartEntryQueryMetric.udharReceivable:
      case SmartEntryQueryMetric.udharPayable:
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
    _searchQueryNotifier.value = query;
    _categorySelectionNotifier.value = category;
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
        'Try Home, Wallets, Udhaar, Monthly Plan, Stats, Settings, Trash, or About.',
        title: 'Screen not recognized',
      );
      return;
    }
    _smartInputCtrl.clear();
    if (target == 'Wallets') {
      _announceVoiceMessage('Opening Wallets.');
      await _openIncomeAccounts();
      return;
    }
    if (target == 'Dashboard' || target == 'Home' || target == 'Main') {
      _openPrimaryLedgerTab(PrimaryLedgerTab.main);
      _announceVoiceMessage('Dashboard opened.');
      return;
    }
    if (target == 'Udhaar' || target == 'Udhar') {
      _openPrimaryLedgerTab(PrimaryLedgerTab.udhar);
      _announceVoiceMessage('Udhar opened.');
      if (RegExp(r'\b(udhar|udhaar|debt|loan)\b')
              .hasMatch(command.rawInput.toLowerCase()) &&
          RegExp(r'\d').hasMatch(command.rawInput)) {
        _showTransactionInfo(
          'This was not saved as a normal expense. Use Quick Udhar here to review and save the debt entry.',
          title: 'Udhar command detected',
        );
      }
      return;
    }
    final section = AppSection.fromLabel(target);
    if (section != null) {
      final requestedMonth = parseReferencedMonth(command.rawInput);
      if (section == AppSection.stats && requestedMonth != null) {
        ref.read(appActionProvider.notifier).request(
          AppActionType.openStatsMonth,
          month: requestedMonth,
          spokenFeedback: _isProcessingVoiceCommand,
        );
      } else if (section == AppSection.budget && requestedMonth != null) {
        ref.read(appActionProvider.notifier).request(
          AppActionType.openMonthlyPlan,
          month: requestedMonth,
        );
      }
      _changeSection(section);
      if (section != AppSection.stats || requestedMonth == null) {
        _announceVoiceMessage('Opening ${section.label}.');
      }
      return;
    }
    _showTransactionInfo(
      'Try Home, Wallets, Udhaar, Monthly Plan, Stats, Settings, Trash, or About.',
      title: 'Screen not recognized',
    );
  }

  MapEntry<int, String> _themeColorSelection(String input) {
    const palette = <String, int>{
      'Blue': 0xFF3B82F6,
      'Emerald': 0xFF10B981,
      'Amber': 0xFFF59E0B,
      'Red': 0xFFEF4444,
      'Violet': 0xFF8B5CF6,
      'Pink': 0xFFEC4899,
      'Teal': 0xFF009688,
      'Slate': 0xFF0F172A,
    };
    final text = input.toLowerCase();
    const aliases = <String, String>{
      'blue': 'Blue',
      'green': 'Emerald',
      'emerald': 'Emerald',
      'orange': 'Amber',
      'amber': 'Amber',
      'yellow': 'Amber',
      'red': 'Red',
      'violet': 'Violet',
      'purple': 'Violet',
      'pink': 'Pink',
      'teal': 'Teal',
      'slate': 'Slate',
      'black': 'Slate',
    };
    for (final alias in aliases.entries) {
      if (RegExp('\\b${RegExp.escape(alias.key)}\\b').hasMatch(text)) {
        final label = alias.value;
        return MapEntry(palette[label]!, label);
      }
    }

    final current = ref.read(settingsProvider).profileColorValue;
    final alternatives = palette.entries
        .where((entry) => entry.value != current)
        .toList(growable: false);
    final pool = alternatives.isEmpty
        ? palette.entries.toList(growable: false)
        : alternatives;
    final index = DateTime.now().microsecondsSinceEpoch.remainder(pool.length);
    final selected = pool[index];
    return MapEntry(selected.value, 'Random');
  }

  DateTime? _resolveSmartQueryMonth(String input) {
    final parsed = parseReferencedMonth(input);
    if (parsed == null) return null;

    final now = DateTime.now();
    final current = DateTime(now.year, now.month);
    final hasExplicitYear = RegExp(r'\b20\d{2}\b').hasMatch(input);
    final hasNamedMonth = RegExp(
      r'\b(january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sept|sep|october|oct|november|nov|december|dec)\b',
      caseSensitive: false,
    ).hasMatch(input);
    if (!hasExplicitYear &&
        hasNamedMonth &&
        isReferencedMonthAfter(parsed, current)) {
      return DateTime(parsed.year - 1, parsed.month);
    }
    return parsed;
  }

  String _smartQueryTitleWithoutMonth(
    String value,
    DateTime? referencedMonth,
  ) {
    var normalized = _smartQueryTitle(value);
    if (referencedMonth == null || normalized.isEmpty) return normalized;
    normalized = normalized
        .replaceAll(
          RegExp(
            r'\b(january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sept|sep|october|oct|november|nov|december|dec)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\b20\d{2}\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return normalized;
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


}

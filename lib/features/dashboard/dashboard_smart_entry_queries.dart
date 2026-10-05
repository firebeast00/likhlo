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
        AppMessage('mention_only_one_wallet_when_selecting_an_entry__e76615'),
        title: AppMessage('multiple_wallets_detected_e80229'),
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
        AppMessage('no_safe_matching_entry_was_found_add_a_title_amo_c374ba'),
        title: AppMessage('entry_not_found_998d95'),
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
            ? AppMessage('the_original_wallet_does_not_have_enough_balance_7dc949')
            : AppMessage('the_original_wallet_is_no_longer_available_44ee95'),
        title: AppMessage('entry_not_repeated_ce59a0'),
      );
      return;
    }

    _smartInputCtrl.clear();
    _showTopMessage(
      title: source.type == 'income' ? AppMessage('income_repeated_de54da') : AppMessage('expense_repeated_96bebf'),
      message: AppMessage('rs_361275', {'p0': repeated.title, 'p1': repeated.amount.toStringAsFixed(0)}),
      tone: source.type == 'income'
          ? TransactionMessageTone.income
          : TransactionMessageTone.expense,
      actionLabel: AppMessage('undo_39fc72'),
      onAction: () async {
        await ref
            .read(transactionExecutorProvider)
            .execute(DeleteTransactionCommand(repeated.id));
        if (!mounted) return;
        _showTransactionInfo(
          AppMessage('the_repeated_entry_was_removed_d5e791'),
          title: AppMessage('repeat_undone_981d9c'),
          announce: false,
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
        AppMessage('active_record_d88f50', {'p0': receivableEntries.length, 'p1': AppEnglishSuffix(receivableEntries.length == 1 ? '' : 's')}),
        title: AppMessage('rs_to_receive_fb9fc2', {'p0': receivable.toStringAsFixed(0)}),
      );
      return;
    }
    if (metric == SmartEntryQueryMetric.udharPayable) {
      _showTransactionInfo(
        AppMessage('active_record_d88f50', {'p0': payableEntries.length, 'p1': AppEnglishSuffix(payableEntries.length == 1 ? '' : 's')}),
        title: AppMessage('rs_to_pay_346fb7', {'p0': payable.toStringAsFixed(0)}),
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
      AppMessage('to_receive_rs_to_pay_rs_active_overdue_ed8440', {'p0': receivable.toStringAsFixed(0), 'p1': payable.toStringAsFixed(0), 'p2': active.length, 'p3': overdue}),
      title: AppMessage('udhar_net_rs_c3ca07', {'p0': (receivable - payable).toStringAsFixed(0)}),
    );
  }

  Future<void> _handleSmartEntryAppControl(
    ParsedSmartEntryCommand command,
  ) async {
    final action = command.appAction;
    if (action == null) {
      _showTransactionInfo(
        AppMessage('try_dark_mode_monthly_pdf_scan_receipt_reminders_a70d88'),
        title: AppMessage('app_control_not_recognized_031b39'),
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
        _announceVoiceMessage(AppMessage('app_menu_opened_1299a3'));
      } else {
        _showTransactionInfo(
          AppMessage('the_app_menu_is_not_available_on_this_screen_d11d51'),
          title: AppMessage('menu_unavailable_cbb15e'),
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
            ? AppMessage('a_new_theme_color_was_selected_177be3')
            : AppMessage('theme_color_is_now_active_713f50', {'p0': selection.value}),
        title: selection.value == 'Random'
            ? AppMessage('theme_color_changed_4b05d6')
            : AppMessage('theme_1a3211', {'p0': selection.value}),
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
            ? AppMessage('search_and_transaction_filters_were_cleared_5b0ca8')
            : AppMessage('no_transaction_filters_are_active_97e05d'),
        title: hadFilters ? AppMessage('filters_cleared_4849be') : AppMessage('nothing_to_clear_ec219a'),
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
        spokenFeedback: true,
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
          ? AppMessage('dark_mode_is_now_enabled_d0531a')
          : AppMessage('light_mode_is_now_enabled_38fa87'),
      title: enableDark ? AppMessage('dark_mode_on_44cf93') : AppMessage('dark_mode_off_d3b1a8'),
    );
  }

  Future<void> _handleSmartEntryQuery(ParsedSmartEntryCommand command) async {
    final metric = command.queryMetric;
    if (metric == null) {
      _showTransactionInfo(
        AppMessage('ask_something_like_how_much_did_i_spend_this_mon_d4b5b9'),
        title: AppMessage('question_needs_more_detail_0deb52'),
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
        AppMessage('mention_one_wallet_at_a_time_for_a_precise_answe_1b73fb'),
        title: AppMessage('multiple_wallets_detected_e80229'),
      );
      return;
    }

    if (metric == SmartEntryQueryMetric.balance) {
      if (mentionedIds.isEmpty) {
        final total = ref.read(totalAvailableProvider);
        _showTransactionInfo(
          AppMessage('rs_across_wallet_d86033', {'p0': total.toStringAsFixed(0), 'p1': wallets.length, 'p2': AppEnglishSuffix(wallets.length == 1 ? '' : 's')}),
          title: AppMessage('total_wallet_balance_dc1cda'),
        );
      } else {
        final wallet = wallets.firstWhere(
              (item) => item.id == mentionedIds.single,
        );
        final balance = ref.read(walletBalanceProvider(wallet.id));
        _showTransactionInfo(
          AppMessage('rs_available_69ca43', {'p0': balance.toStringAsFixed(0)}),
          title: AppMessage('balance_bc2b71', {'p0': wallet.name}),
        );
      }
      _smartInputCtrl.clear();
      return;
    }

    final referencedMonth = _resolveSmartQueryMonth(command.rawInput);
    final hasCategory = command.category != 'General' &&
        (command.confidenceByField['category'] ?? 0) >= 0.8;
    final matching = selectSmartEntryQueryEntries(
      ref.read(expenseProvider).allExpenses,
      command,
      referencedMonth: referencedMonth,
      walletId: mentionedIds.isEmpty ? null : mentionedIds.single,
    );
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
          AppMessage('expense_2a0b6d', {'p0': matching.where((entry) => entry.type == 'expense').length, 'p1': AppEnglishSuffix(matching.where((entry) => entry.type == 'expense').length == 1 ? '' : 's'), 'p2': subject}),
          title: AppMessage('rs_spent_3fb486', {'p0': spending.toStringAsFixed(0), 'p1': AppLabel(period)}),
        );
        break;
      case SmartEntryQueryMetric.income:
        _showTransactionInfo(
          AppMessage('income_entr_596b1b', {'p0': matching.where((entry) => entry.type == 'income').length, 'p1': AppEnglishSuffix(matching.where((entry) => entry.type == 'income').length == 1 ? 'y' : 'ies'), 'p2': subject}),
          title: AppMessage('rs_received_91524c', {'p0': income.toStringAsFixed(0), 'p1': AppLabel(period)}),
        );
        break;
      case SmartEntryQueryMetric.net:
        _showTransactionInfo(
          AppMessage('income_rs_expenses_rs_bf056a', {'p0': income.toStringAsFixed(0), 'p1': spending.toStringAsFixed(0)}),
          title: AppMessage('net_rs_692f91', {'p0': (income - spending).toStringAsFixed(0), 'p1': AppLabel(period)}),
        );
        break;
      case SmartEntryQueryMetric.transactionCount:
        final type = command.entryTypeFilter;
        final count = type == null
            ? matching.length
            : matching.where((entry) => entry.type == type).length;
        _showTransactionInfo(
          AppMessage('records_eab69c', {'p0': type == null ? 'Income and expense' : type == 'income' ? 'Income' : 'Expense', 'p1': subject}),
          title: AppMessage('transactions_3cd4cc', {'p0': count, 'p1': AppLabel(period)}),
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
          AppMessage('income_rs_spent_rs_net_rs_entr_032470', {'p0': income.toStringAsFixed(0), 'p1': spending.toStringAsFixed(0), 'p2': (income - spending).toStringAsFixed(0), 'p3': matching.length, 'p4': AppEnglishSuffix(matching.length == 1 ? 'y' : 'ies'), 'p5': AppLabel(topText)}),
          title: AppMessage('financial_summary_e8c7e7', {'p0': AppLabel(period)}),
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
      AppMessage('close_search_to_return_to_the_normal_monthly_vie_aaab1c'),
      title: AppMessage('transaction_filters_applied_2e8692'),
    );
  }

  Future<void> _handleSmartEntryNavigation(
      ParsedSmartEntryCommand command,
      ) async {
    final target = command.navigationTarget;
    if (target == null) {
      _showTransactionInfo(
        AppMessage('try_home_wallets_udhaar_monthly_plan_stats_setti_4c294f'),
        title: AppMessage('screen_not_recognized_946e3d'),
      );
      return;
    }
    _smartInputCtrl.clear();
    if (target == 'Wallets') {
      _announceVoiceMessage(AppMessage('opening_wallets_a26f50'));
      await _openIncomeAccounts();
      return;
    }
    if (target == 'Dashboard' || target == 'Home' || target == 'Main') {
      _openPrimaryLedgerTab(PrimaryLedgerTab.main);
      _announceVoiceMessage(AppMessage('dashboard_opened_004ce9'));
      return;
    }
    if (target == 'Udhaar' || target == 'Udhar') {
      _openPrimaryLedgerTab(PrimaryLedgerTab.udhar);
      _announceVoiceMessage(AppMessage('udhar_opened_558358'));
      if (RegExp(r'\b(udhar|udhaar|debt|loan)\b')
              .hasMatch(command.rawInput.toLowerCase()) &&
          RegExp(r'\d').hasMatch(command.rawInput)) {
        _showTransactionInfo(
          AppMessage('this_was_not_saved_as_a_normal_expense_use_quick_02786f'),
          title: AppMessage('udhar_command_detected_6ba7b1'),
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
        _announceVoiceMessage(AppMessage('opening_7e01ca', {'p0': AppLabel(section.label)}));
      }
      return;
    }
    _showTransactionInfo(
      AppMessage('try_home_wallets_udhaar_monthly_plan_stats_setti_4c294f'),
      title: AppMessage('screen_not_recognized_946e3d'),
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

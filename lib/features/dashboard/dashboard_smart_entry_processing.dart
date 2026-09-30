part of '../../screens/home_screen.dart';

extension _DashboardSmartEntryProcessingMethods on _HomeScreenState {
  Future<bool> _processNLP(
      String text, {
        SmartInputSource source = SmartInputSource.typed,
      }) async {
    _dismissKeyboard();
    final normalized = text.trim();
    if (normalized.isEmpty) return false;

    final categories = ref.read(categoryProvider);

    if (source == SmartInputSource.typed || source == SmartInputSource.voice) {
      final wallets = ref.read(walletProvider);
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

      final batchAttempt = ref.read(smartEntryBatchControllerProvider).tryBuild(
            rawText: normalized,
            categories: categories,
            source: source,
            accounts: accounts,
            preferredAccountId: _selectedSmartEntryWallet(wallets)?.id,
          );

      if (batchAttempt.status == SmartEntryBatchStatus.poisoned) {
        _showTransactionError(
          batchAttempt.reason ??
              'One of the detected entries could not be safely interpreted. Nothing was saved.',
          title: 'Multiple entries not saved',
        );
        return false;
      }

      if (batchAttempt.status == SmartEntryBatchStatus.ready &&
          batchAttempt.draft != null) {
        if (wallets.isEmpty) {
          _showTransactionError(
            'Create a Cash or JazzCash wallet before using Smart Entry.',
            title: 'Wallet required',
          );
          return false;
        }

        final confirmed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => BatchTransactionReviewScreen(
              draft: batchAttempt.draft!,
            ),
          ),
        );
        if (!mounted) return false;

        if (confirmed == true) {
          _smartInputCtrl.clear();
          FocusScope.of(context).unfocus();
          _showTransactionSuccess(
            'The reviewed entries were saved together.',
            title: 'Entries saved',
          );
          unawaited(HapticFeedback.lightImpact());
          return true;
        }
        return false;
      }
    }

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
          await _handleSmartEntryQuery(command);
          return _smartInputCtrl.text.trim().isEmpty;
        case SmartEntryIntent.searchEntries:
          _handleSmartEntrySearch(command);
          return _smartInputCtrl.text.trim().isEmpty;
        case SmartEntryIntent.navigate:
          await _handleSmartEntryNavigation(command);
          return _smartInputCtrl.text.trim().isEmpty;
        case SmartEntryIntent.appControl:
          await _handleSmartEntryAppControl(command);
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

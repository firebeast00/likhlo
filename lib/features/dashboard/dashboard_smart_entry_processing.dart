part of '../../screens/home_screen.dart';

extension _DashboardSmartEntryProcessingMethods on _HomeScreenState {
  static const _voiceCategoryAliasKey = 'home_voice_category_aliases_v1';

  Map<String, String> _readVoiceCategoryAliases() {
    try {
      final stored = Hive.box('preferences').get(_voiceCategoryAliasKey);
      if (stored is! Map) return const {};
      return {for (final entry in stored.entries.take(100))
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String};
    } catch (_) {
      return const {};
    }
  }

  Future<void> _rememberVoiceCategoryAlias(String heard, String category) async {
    final key = SpeechCategoryMatcher.aliasKey(heard);
    if (key.isEmpty || key.length > 80) return;
    final aliases = Map<String, String>.of(_readVoiceCategoryAliases())..remove(key);
    if (aliases.length >= 100) aliases.remove(aliases.keys.first);
    aliases[key] = category;
    try {
      await Hive.box('preferences').put(_voiceCategoryAliasKey, aliases);
      _speechCacheKey = null;
    } catch (_) {
      // Learning failure must never block or alter the confirmed transaction.
    }
  }

  Future<bool> _processNLP(
      String text, {
        SmartInputSource source = SmartInputSource.typed,
        SmartInputPlan? preparedVoicePlan,
      }) async {
    _dismissKeyboard();
    final normalized = text.trim();
    if (normalized.isEmpty) return false;

    final categories = ref.read(categoryProvider);
    final voicePlan = source == SmartInputSource.voice
        ? preparedVoicePlan ?? ref.read(smartEntryControllerProvider).parse(
            normalized, categories, source: source, accounts: _parsingAccounts(),
            enableHomeExpenseCategories: true,
            enableRomanUrduCategories: AppLanguage.read() == AppLanguage.romanUrdu,
            voiceCategoryAliases: _readVoiceCategoryAliases())
        : null;
    final expenseCategory = voicePlan != null ? voicePlan.expenseCategory
        : ref.read(smartEntryControllerProvider).resolveHomeExpenseCategory(
            normalized, categories, source: source, accounts: _parsingAccounts(),
            enableRomanUrduCategories: AppLanguage.read() == AppLanguage.romanUrdu);
    final categoryReview = expenseCategory?.needsClarification == true
        ? expenseCategory : null;
    if (expenseCategory?.needsClarification == true) {
      final recoverMissing = voicePlan != null &&
          const HomeCategorySpeechPolicy().canRecoverCategory(voicePlan);
      if (source != SmartInputSource.voice ||
          (!expenseCategory!.canConfirmVoice && !recoverMissing)) {
        _showTransactionInfo(expenseCategory!.issue!, title: 'Choose a category');
        return false;
      }
      final pending = expenseCategory!;
      VoiceDiagnosticsService.instance.stage('category_matching', {
        'raw_text': normalized, 'requested_names': pending.requestedNames,
        'suggestions': pending.suggestions,
        'suggestion_scores': pending.suggestionScores,
        'slot_state': recoverMissing ? 'missing' : 'unknown',
        'parsing_text': pending.cleanedText,
        'matched_phrases': pending.matchedPhrases,
      });
      // Keep uncertainty attached to the draft. The existing entry sheet
      // reviews category, amount and wallet together; no preceding dialog.
    }

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
            rawText: expenseCategory?.cleanedText ?? normalized,
            categories: categories,
            source: source,
            accounts: accounts,
            preferredAccountId: _selectedSmartEntryWallet(wallets)?.id,
          );

      if (batchAttempt.status == SmartEntryBatchStatus.poisoned) {
        _showTransactionError(
          batchAttempt.reason ??
              AppMessage('one_of_the_detected_entries_could_not_be_safely__876c93'),
          title: AppMessage('multiple_entries_not_saved_4eb2b6'),
        );
        return false;
      }

      if (batchAttempt.status == SmartEntryBatchStatus.ready &&
          batchAttempt.draft != null) {
        if (wallets.isEmpty) {
          _showTransactionError(
            AppMessage('create_a_cash_or_jazzcash_wallet_before_using_sm_8358f6'),
            title: AppMessage('wallet_required_2f5332'),
          );
          return false;
        }

        VoiceDiagnosticsService.instance.stage('parse', {'intent': 'batch', 'raw_text': normalized,
          'entry_count': batchAttempt.draft!.entries.length,
          'entries': batchAttempt.draft!.entries.map((entry) => {
            'title': entry.title, 'amount': entry.amount, 'category': entry.category,
            'type': entry.type, 'wallet_id': entry.walletId, 'date': entry.date,
            'source_text': entry.sourceText, 'confidence': entry.confidence,
          }).toList()});
        VoiceDiagnosticsService.instance.awaitingConfirmation(reason: 'batch_review');
        final diagnosticId = VoiceDiagnosticsService.instance.currentId;
        final confirmed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => BatchTransactionReviewScreen(
              draft: batchAttempt.draft!,
              diagnosticId: diagnosticId,
            ),
          ),
        );
        if (!mounted) return false;

        if (confirmed == true) {
          _smartInputCtrl.clear();
          FocusScope.of(context).unfocus();
          _showTransactionSuccess(
            AppMessage('the_reviewed_entries_were_saved_together_e40eed'),
            title: AppMessage('entries_saved_9ed5ce'),
            announce: false,
          );
          unawaited(HapticFeedback.lightImpact());
          return true;
        }
        return false;
      }
    }

    final plan = voicePlan ?? ref.read(smartEntryControllerProvider).parse(
      normalized,
      categories,
      source: source,
      accounts: _parsingAccounts(),
      expenseCategory: expenseCategory,
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
        plan.expenseCategory == null &&
        result['category'] == 'General' &&
        learnedPreference != null &&
        categories.contains(learnedPreference.category)) {
      result['category'] = learnedPreference.category;
    }
    final amount = result['amount'];
    if (amount is! num || !amount.isFinite || amount <= 0) {
      _showTransactionError(
        AppMessage('include_an_amount_for_example_500_biryani_or_1_5_011d46'),
        title: AppMessage('amount_not_detected_d9d89a'),
      );
      return false;
    }

    final wallets = ref.read(walletProvider);
    if (wallets.isEmpty) {
      _showTransactionError(
        AppMessage('create_a_cash_or_jazzcash_wallet_before_using_sm_8358f6'),
        title: AppMessage('wallet_required_2f5332'),
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
    VoiceDiagnosticsService.instance.stage('confidence', {
      'score': semanticConfidence.score, 'disposition': semanticConfidence.disposition.name,
      'reasons': semanticConfidence.reasons, 'requires_asr_review': plan.requiresAsrReview,
      'resolved_wallet_id': resolvedWalletId,
      'category_resolution': expenseCategory?.resolution,
      'category_requires_review': categoryReview != null,
    });
    assert(() {
      debugPrint(
        '[SmartEntry confidence] '
            'disposition=${semanticConfidence.disposition} '
            'score=${semanticConfidence.score.toStringAsFixed(3)} '
            'reasons=${semanticConfidence.reasons.join(' | ')}',
      );
      return true;
    }());

    if (categoryReview == null && !plan.requiresAsrReview &&
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
          AppMessage('the_selected_wallet_changed_or_no_longer_has_eno_34f20d'),
          title: AppMessage('smart_entry_not_saved_b8ec80'),
        );
        return false;
      }

      _smartInputCtrl.clear();
      FocusScope.of(context).unfocus();
      _showTopMessage(
        title: type == 'income' ? AppMessage('income_added_fa12b0') : AppMessage('expense_saved_a7f2ed'),
        message:
            AppMessage('rs_370e31', {'p0': entry.title, 'p1': entry.amount.toStringAsFixed(0), 'p2': wallet.name}),
        tone: type == 'income'
            ? TransactionMessageTone.income
            : TransactionMessageTone.expense,
        actionLabel: AppMessage('undo_39fc72'),
        onAction: () async {
          final deleteResult = await ref
              .read(transactionExecutorProvider)
              .execute(DeleteTransactionCommand(entry.id));
          if (!mounted) return;
          if (deleteResult.succeeded) {
            _showTransactionInfo(
              AppMessage('the_instant_smart_entry_was_removed_0941a9'),
              title: AppMessage('entry_undone_60fe48'),
              announce: false,
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
        : categoryReview != null && resolvedWalletId != null &&
        semanticConfidence.canAutoExecute
        ? AppStrings.current.text('expense_category_choose')
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

    VoiceDiagnosticsService.instance.awaitingConfirmation(reason: reviewMessage);
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
      voiceCategoryReview: categoryReview == null ? null : voicePlan,
    );

    if (confirmed == true && mounted) {
      _smartInputCtrl.clear();
      if (type == 'income') {
        _showIncomeMessage(AppMessage('the_smart_entry_was_saved_to_the_selected_wallet_a313b9'));
      } else {
        _showExpenseMessage(AppMessage('the_smart_entry_was_saved_to_the_selected_wallet_a313b9'));
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

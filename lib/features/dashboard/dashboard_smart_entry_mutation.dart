part of '../../screens/home_screen.dart';

extension _DashboardSmartEntryMutationMethods on _HomeScreenState {
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
              announce: false,
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
      announce: false,
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
            announce: false,
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


}

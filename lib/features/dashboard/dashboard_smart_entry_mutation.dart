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
        AppMessage('say_what_to_change_for_example_change_burger_amo_64942a'),
        title: AppMessage('change_required_76a96b'),
      );
      return;
    }
    if (mutation.patch.amount != null && mutation.patch.amount! <= 0) {
      _showTransactionError(
        AppMessage('the_new_amount_must_be_greater_than_zero_10e92d'),
        title: AppMessage('invalid_amount_a2f6ca'),
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
        AppMessage('mention_only_one_wallet_so_the_correct_entry_can_ab7e95'),
        title: AppMessage('multiple_wallets_detected_e80229'),
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
            ? AppMessage('no_safe_matching_entry_was_found_add_a_title_amo_c374ba')
            : AppMessage('no_safe_matching_entry_was_found_name_the_entry__ed32d9'),
        title: AppMessage('entry_not_found_998d95'),
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
          AppMessage('the_matching_entry_is_not_certain_enough_to_chan_0675f1'),
          title: AppMessage('review_target_entry_6a2f72'),
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
            AppMessage('deleting_this_income_would_make_the_wallet_balan_993f82'),
            title: AppMessage('income_cannot_be_deleted_3705f4'),
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
          AppMessage('the_entry_changed_before_it_could_be_deleted_try_063808'),
          title: AppMessage('entry_not_deleted_20151f'),
        );
        return;
      }

      _smartInputCtrl.clear();
      final deletedEntry = target;
      final deletedAmount =
      deletedEntry.amount.toStringAsFixed(0);
      _showDeletionMessage(
        AppMessage('rs_361275', {'p0': deletedEntry.title, 'p1': deletedAmount}),
        title: AppMessage('entry_moved_to_trash_4ff9bd'),
        actionLabel: AppMessage('undo_39fc72'),
        onAction: () async {
          final restoreResult = await ref
              .read(transactionExecutorProvider)
              .execute(RestoreTransactionCommand(deletedEntry.id));
          if (!mounted) return;
          if (restoreResult.succeeded) {
            _showTransactionInfo(
              AppMessage('the_deleted_entry_was_restored_c688ef'),
              title: AppMessage('deletion_undone_1d6e39'),
              announce: false,
            );
          } else {
            _showTransactionError(
              AppMessage('the_entry_could_not_be_restored_because_the_wall_f5ba51'),
              title: AppMessage('undo_failed_2311b4'),
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
          AppMessage('choose_an_existing_category_e42e1e', {'p0': categories.join(', ')}),
          title: AppMessage('category_not_found_19c290'),
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
        AppMessage('the_entry_already_has_these_details_2b9c79'),
        title: AppMessage('no_change_needed_8a26a1'),
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
        AppMessage('the_wallet_cannot_support_this_change_or_the_ent_dccbfc'),
        title: AppMessage('entry_not_updated_4104d8'),
      );
      return;
    }

    _smartInputCtrl.clear();
    _showTransactionSuccess(
      AppMessage('rs_03d36d', {'p0': updatedEntry.title, 'p1': updatedEntry.amount.toStringAsFixed(0), 'p2': updatedEntry.category}),
      title: AppMessage('entry_updated_53550c'),
      announce: false,
      actionLabel: AppMessage('undo_39fc72'),
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
            AppMessage('the_previous_amount_was_restored_dc306f'),
            title: AppMessage('edit_undone_c701f8'),
            announce: false,
          );
        } else {
          _showTransactionError(
            AppMessage('the_previous_amount_could_not_be_restored_becaus_d3b46f'),
            title: AppMessage('undo_failed_2311b4'),
          );
        }
      },
    );
    unawaited(HapticFeedback.lightImpact());
  }


}

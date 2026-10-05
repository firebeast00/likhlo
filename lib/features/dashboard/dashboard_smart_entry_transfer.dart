part of '../../screens/home_screen.dart';

extension _DashboardSmartEntryTransferMethods on _HomeScreenState {
  Future<void> _handleSmartEntryTransferCommand(
      ParsedSmartEntryCommand command,
      ) async {
    if (command.amount <= 0) {
      _showTransactionError(
        AppMessage('include_an_amount_for_example_transfer_500_cash__529a65'),
        title: AppMessage('transfer_amount_required_954377'),
      );
      return;
    }

    final wallets = ref.read(walletProvider);
    if (wallets.length < 2) {
      _showTransactionError(
        AppMessage('create_at_least_two_wallets_before_making_a_tran_955aed'),
        title: AppMessage('two_wallets_required_b3126b'),
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
        AppMessage('name_both_wallets_for_example_transfer_500_cash__f77376'),
        title: AppMessage('source_and_destination_required_3885f6'),
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
        AppMessage('i_found_both_wallets_but_the_transfer_direction__2e2ccb'),
        title: AppMessage('confirm_transfer_direction_c1e278'),
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
        AppMessage('choose_two_different_wallets_32b992'),
        title: AppMessage('invalid_transfer_d8d151'),
      );
      return;
    }

    final available = walletNotifier.getBalanceForWallet(source.id);
    if (command.amount > available + 0.000001) {
      _showTransactionError(
        AppMessage('available_in_rs_required_rs_9a7b7b', {'p0': source.name, 'p1': available.toStringAsFixed(0), 'p2': command.amount.toStringAsFixed(0)}),
        title: AppMessage('insufficient_balance_1a1823'),
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
        AppMessage('the_source_wallet_changed_or_no_longer_has_enoug_8a6366'),
        title: AppMessage('transfer_not_saved_ff0de3'),
      );
      return;
    }

    _smartInputCtrl.clear();
    final transferAmount = command.amount.toStringAsFixed(
      command.amount == command.amount.truncateToDouble() ? 0 : 2,
    );
    _showTransferMessage(
      AppMessage('rs_b100db', {'p0': transferAmount, 'p1': source.name, 'p2': destination.name}),
      title: AppMessage('transfer_completed_9fca88'),
      actionLabel: AppMessage('undo_39fc72'),
      onAction: () async {
        await ref
            .read(transactionExecutorProvider)
            .execute(DeleteTransferCommand(transferId));
        if (!mounted) return;
        _showTransactionInfo(
          AppMessage('the_transfer_was_reversed_6d1d88'),
          title: AppMessage('transfer_undone_e53f3d'),
          announce: false,
        );
      },
    );
    unawaited(HapticFeedback.lightImpact());
  }


}

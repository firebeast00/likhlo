part of '../../screens/home_screen.dart';

extension _DashboardSmartEntryTransferMethods on _HomeScreenState {
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


}

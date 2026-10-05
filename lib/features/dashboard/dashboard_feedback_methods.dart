part of '../../screens/home_screen.dart';

extension _DashboardFeedbackMethods on _HomeScreenState {
  void _announceVoiceMessage(Object message) {
    if (!mounted || !_isProcessingVoiceCommand) return;
    unawaited(AudioFeedbackService().announceMessage(message));
  }

  void _showTransactionError(
      Object message, {
        Object title = 'Unable to continue',
      }) {
    _showTopMessage(
      title: title,
      message: message,
      tone: TransactionMessageTone.error,
    );
  }

  void _showTransactionSuccess(
      Object message, {
        Object title = 'Completed',
        Object? actionLabel,
        Future<void> Function()? onAction,
        bool announce = true,
      }) {
    _showTopMessage(
      title: title,
      message: message,
      tone: TransactionMessageTone.success,
      actionLabel: actionLabel,
      onAction: onAction,
      announce: announce,
    );
  }

  void _showTransactionInfo(
      Object message, {
        Object title = 'Information',
        bool announce = true,
      }) {
    _showTopMessage(
      title: title,
      message: message,
      tone: TransactionMessageTone.info,
      announce: announce,
    );
  }

  void _showExpenseMessage(Object message, {Object title = 'Expense saved'}) {
    _showTopMessage(
      title: title,
      message: message,
      tone: TransactionMessageTone.expense,
    );
  }

  void _showIncomeMessage(Object message, {Object title = 'Income added'}) {
    _showTopMessage(
      title: title,
      message: message,
      tone: TransactionMessageTone.income,
    );
  }

  void _showTransferMessage(
    Object message, {
    Object title = 'Transfer completed',
    Object? actionLabel,
    Future<void> Function()? onAction,
  }) {
    _showTopMessage(
      title: title,
      message: message,
      tone: TransactionMessageTone.transfer,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  void _showDeletionMessage(
    Object message, {
    Object title = 'Moved to Trash',
    Object? actionLabel,
    Future<void> Function()? onAction,
  }) {
    _showTopMessage(
      title: title,
      message: message,
      tone: TransactionMessageTone.deletion,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  void _showTopMessage({
    required Object title,
    required Object message,
    required TransactionMessageTone tone,
    Object? actionLabel,
    Future<void> Function()? onAction,
    bool announce = true,
  }) {
    if (!mounted) return;
    _feedback.show(
      context,
      title: AppStrings.current.display(title),
      message: AppStrings.current.display(message),
      tone: tone,
      actionLabel: actionLabel == null ? null : AppStrings.current.display(actionLabel),
      onAction: onAction,
    );
    // Saved ledger entries already announce through TransactionExecutor.
    if (announce &&
        tone != TransactionMessageTone.expense &&
        tone != TransactionMessageTone.income &&
        tone != TransactionMessageTone.transfer &&
        tone != TransactionMessageTone.deletion) {
      unawaited(AudioFeedbackService().announceNotification(
        title: title,
        message: message,
      ));
    }
  }


}

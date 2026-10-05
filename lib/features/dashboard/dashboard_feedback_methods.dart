part of '../../screens/home_screen.dart';

extension _DashboardFeedbackMethods on _HomeScreenState {
  void _announceVoiceMessage(String message) {
    if (!mounted || !_isProcessingVoiceCommand) return;
    unawaited(AudioFeedbackService().announceMessage(message));
  }

  void _showTransactionError(
      String message, {
        String title = 'Unable to continue',
      }) {
    _showTopMessage(
      title: title,
      message: message,
      tone: TransactionMessageTone.error,
    );
  }

  void _showTransactionSuccess(
      String message, {
        String title = 'Completed',
        String? actionLabel,
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
      String message, {
        String title = 'Information',
        bool announce = true,
      }) {
    _showTopMessage(
      title: title,
      message: message,
      tone: TransactionMessageTone.info,
      announce: announce,
    );
  }

  void _showExpenseMessage(String message, {String title = 'Expense saved'}) {
    _showTopMessage(
      title: title,
      message: message,
      tone: TransactionMessageTone.expense,
    );
  }

  void _showIncomeMessage(String message, {String title = 'Income added'}) {
    _showTopMessage(
      title: title,
      message: message,
      tone: TransactionMessageTone.income,
    );
  }

  void _showTransferMessage(
    String message, {
    String title = 'Transfer completed',
    String? actionLabel,
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
    String message, {
    String title = 'Moved to Trash',
    String? actionLabel,
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
    required String title,
    required String message,
    required TransactionMessageTone tone,
    String? actionLabel,
    Future<void> Function()? onAction,
    bool announce = true,
  }) {
    if (!mounted) return;
    _feedback.show(
      context,
      title: title,
      message: message,
      tone: tone,
      actionLabel: actionLabel,
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

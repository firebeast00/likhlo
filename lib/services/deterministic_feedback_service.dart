enum FinancialFeedbackAction { expense, income, transfer, edit, delete, repeat }

class FinancialFeedbackData {
  final FinancialFeedbackAction action;
  final String title;
  final double amount;
  final String? source;
  final String? destination;

  const FinancialFeedbackData({
    required this.action,
    required this.title,
    required this.amount,
    this.source,
    this.destination,
  });
}

/// Produces fixed finance-safe confirmation text. No LLM or ASR output is
/// allowed to invent or alter the committed amount, title, or wallet names.
class DeterministicFeedbackService {
  const DeterministicFeedbackService();

  String message(FinancialFeedbackData data) {
    final amount = _formatAmount(data.amount);
    switch (data.action) {
      case FinancialFeedbackAction.expense:
        return '${data.title}, $amount rupees expense saved.';
      case FinancialFeedbackAction.income:
        return '${data.title}, $amount rupees income added.';
      case FinancialFeedbackAction.transfer:
        return '$amount rupees transferred from ${data.source ?? 'source wallet'} to ${data.destination ?? 'destination wallet'}.';
      case FinancialFeedbackAction.edit:
        return '${data.title} updated to $amount rupees.';
      case FinancialFeedbackAction.delete:
        return '${data.title}, $amount rupees entry deleted.';
      case FinancialFeedbackAction.repeat:
        return '${data.title}, $amount rupees entry repeated.';
    }
  }

  String _formatAmount(double value) {
    return value == value.truncateToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }
}

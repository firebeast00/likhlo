import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/services/deterministic_feedback_service.dart';

void main() {
  const feedback = DeterministicFeedbackService();

  test('speaks confirmed transfer names and amount', () {
    expect(
      feedback.message(const FinancialFeedbackData(
        action: FinancialFeedbackAction.transfer,
        title: 'Transfer', amount: 5000,
        source: 'JazzCash', destination: 'Cash',
      )),
      '5000 rupees transferred from JazzCash to Cash.',
    );
  });

  test('never invents wallet names absent from committed details', () {
    expect(
      feedback.message(const FinancialFeedbackData(
        action: FinancialFeedbackAction.transfer,
        title: 'Transfer', amount: 5000,
      )),
      '5000 rupees transferred.',
    );
  });
}

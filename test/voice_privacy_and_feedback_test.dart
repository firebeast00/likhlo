import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/services/deterministic_feedback_service.dart';
import 'package:student_expense_manager/services/voice_privacy_service.dart';

void main() {
  test('voice diagnostics contain no transcript or financial text', () {
    const event = VoiceDiagnosticEvent(
      provider: 'device',
      outcome: 'timeout',
      durationMilliseconds: 3200,
      errorCategory: 'no_match',
    );
    final payload = event.toPrivacySafeMap();

    expect(payload.keys, isNot(contains('transcript')));
    expect(payload.keys, isNot(contains('audio')));
    expect(payload.keys, isNot(contains('amount')));
  });

  test('financial feedback is deterministic from committed values', () {
    final message = const DeterministicFeedbackService().message(
      const FinancialFeedbackData(
        action: FinancialFeedbackAction.transfer,
        title: 'Transfer',
        amount: 5000,
        source: 'JazzCash',
        destination: 'Bank Account',
      ),
    );

    expect(
      message,
      '5000 rupees transferred from JazzCash to Bank Account.',
    );
  });
}

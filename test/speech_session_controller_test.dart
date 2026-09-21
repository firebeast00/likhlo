import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/services/speech_session_controller.dart';

void main() {
  group('SpeechSessionController', () {
    test('ignores recognizer callbacks before a session starts', () {
      final controller = SpeechSessionController();

      final stopped = controller.onRecognizerStopped();
      final error = controller.onRecognizerError(retryable: true);

      expect(stopped.action, SpeechSessionAction.none);
      expect(error.action, SpeechSessionAction.none);
      expect(controller.state, SpeechSessionState.idle);
      expect(controller.retryCount, 0);
    });

    test('never executes a partial transcript when recognition stops', () {
      final controller = SpeechSessionController()..start();

      final partial = controller.recordTranscript(
        '500 biryani',
        isFinal: false,
      );
      final stopped = controller.onRecognizerStopped();

      expect(partial.action, SpeechSessionAction.none);
      expect(stopped.action, SpeechSessionAction.preserveDraft);
      expect(stopped.transcript, '500 biryani');
      expect(controller.state, SpeechSessionState.failed);
    });

    test('executes an explicit final transcript exactly once', () {
      final controller = SpeechSessionController()..start();

      final finalResult = controller.recordTranscript(
        '500 biryani',
        isFinal: true,
      );
      final stopped = controller.onRecognizerStopped();
      final duplicateFinal = controller.recordTranscript(
        '500 biryani',
        isFinal: true,
      );

      expect(finalResult.action, SpeechSessionAction.processFinal);
      expect(finalResult.transcript, '500 biryani');
      expect(stopped.action, SpeechSessionAction.none);
      expect(duplicateFinal.action, SpeechSessionAction.none);
    });

    test('allows only one controlled retry', () {
      final controller = SpeechSessionController()..start();
      controller.recordTranscript('500 bir', isFinal: false);

      final firstError = controller.onRecognizerError(retryable: true);
      final secondError = controller.onRecognizerError(retryable: true);

      expect(firstError.action, SpeechSessionAction.retry);
      expect(controller.retryCount, 1);
      expect(secondError.action, SpeechSessionAction.preserveDraft);
      expect(secondError.transcript, '500 bir');
    });

    test('an error without a transcript does not create work', () {
      final controller = SpeechSessionController(maxRetries: 0)..start();

      final decision = controller.onRecognizerError(retryable: true);

      expect(decision.action, SpeechSessionAction.none);
      expect(controller.state, SpeechSessionState.failed);
    });

    test('a final result is not downgraded by a later error', () {
      final controller = SpeechSessionController()..start();

      final finalResult = controller.recordTranscript(
        'salary 50000',
        isFinal: true,
      );
      final error = controller.onRecognizerError(retryable: true);

      expect(finalResult.action, SpeechSessionAction.processFinal);
      expect(error.action, SpeechSessionAction.none);
    });

    test('processing lifecycle is explicit', () {
      final controller = SpeechSessionController()..start();
      controller.recordTranscript('200 chai', isFinal: true);

      controller.markProcessing();
      expect(controller.state, SpeechSessionState.processing);

      controller.markCompleted();
      expect(controller.state, SpeechSessionState.completed);
    });
  });
}

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

    test('promotes the best transcript when recognition stops normally', () {
      final controller = SpeechSessionController()..start();

      final partial = controller.recordTranscript(
        '500 biryani',
        isFinal: false,
      );
      final stopped = controller.onRecognizerStopped();
      final duplicateStop = controller.onRecognizerStopped();

      expect(partial.action, SpeechSessionAction.none);
      expect(stopped.action, SpeechSessionAction.processFinal);
      expect(stopped.transcript, '500 biryani');
      expect(duplicateStop.action, SpeechSessionAction.none);
      expect(controller.state, SpeechSessionState.finalizing);
    });

    test('continues instead of executing an incomplete normal stop', () {
      final controller = SpeechSessionController(maxRetries: 2)..start();
      controller.recordTranscript('open', isFinal: false);

      final stopped = controller.onRecognizerStopped(isComplete: false);

      expect(stopped.action, SpeechSessionAction.retry);
      expect(stopped.transcript, isEmpty);
      expect(controller.latestDraft, isEmpty);
      expect(controller.state, SpeechSessionState.listening);
      expect(controller.retryCount, 1);
    });

    test('does not merge a failed attempt into the retry', () {
      final controller = SpeechSessionController(maxRetries: 2)..start();
      controller.recordTranscript('open', isFinal: false);
      controller.onRecognizerStopped(isComplete: false);

      final completed = controller.recordTranscript(
        'wallets',
        isFinal: true,
        isComplete: true,
      );

      expect(completed.action, SpeechSessionAction.processFinal);
      expect(completed.transcript, 'wallets');
      expect(controller.onRecognizerStopped().action, SpeechSessionAction.none);
    });

    test('a new mic attempt always starts with a clean draft', () {
      final controller = SpeechSessionController(maxRetries: 2)..start();
      controller.recordTranscript('open', isFinal: false);
      controller.start();

      final completed = controller.recordTranscript(
        'wallets',
        isFinal: true,
        isComplete: true,
      );

      expect(completed.action, SpeechSessionAction.processFinal);
      expect(completed.transcript, 'wallets');
    });

    test('retries an empty premature stop before failing visibly', () {
      final controller = SpeechSessionController(maxRetries: 1)..start();

      final firstStop = controller.onRecognizerStopped(
        isComplete: false,
        retryWhenEmpty: true,
      );
      final secondStop = controller.onRecognizerStopped(
        isComplete: false,
        retryWhenEmpty: true,
      );

      expect(firstStop.action, SpeechSessionAction.retry);
      expect(secondStop.action, SpeechSessionAction.none);
      expect(controller.state, SpeechSessionState.failed);
    });

    test('uses the latest recognizer segment after a retry', () {
      final controller = SpeechSessionController(maxRetries: 2)..start();
      controller.recordTranscript(
        'transfer 500 from cash',
        isFinal: false,
      );
      controller.onRecognizerStopped(isComplete: false);

      final completed = controller.recordTranscript(
        'cash to jazzcash',
        isFinal: true,
        isComplete: true,
      );

      expect(completed.transcript, 'cash to jazzcash');
    });

    test('stable partial only executes when semantic command is complete', () {
      final controller = SpeechSessionController()..start();
      controller.recordTranscript('open', isFinal: false);

      final incomplete = controller.onStableTranscript(isComplete: false);
      final complete = controller.onStableTranscript(isComplete: true);

      expect(incomplete.action, SpeechSessionAction.none);
      expect(complete.action, SpeechSessionAction.processFinal);
      expect(complete.transcript, 'open');
    });

    test('session deadline discards an incomplete draft without retrying', () {
      final controller = SpeechSessionController(maxRetries: 2)..start();
      controller.recordTranscript('transfer 500 from cash', isFinal: false);

      final expired = controller.onSessionExpired(isComplete: false);

      expect(expired.action, SpeechSessionAction.discardDraft);
      expect(expired.transcript, 'transfer 500 from cash');
      expect(controller.retryCount, 0);
      expect(controller.state, SpeechSessionState.failed);
    });

    test('a normal stop without any transcript creates no work', () {
      final controller = SpeechSessionController()..start();

      final stopped = controller.onRecognizerStopped();

      expect(stopped.action, SpeechSessionAction.none);
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
      controller.recordTranscript('500 bir', isFinal: false);
      final secondError = controller.onRecognizerError(retryable: true);

      expect(firstError.action, SpeechSessionAction.retry);
      expect(controller.retryCount, 1);
      expect(secondError.action, SpeechSessionAction.discardDraft);
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

  test('corrected cumulative partial replaces the older amount and title', () {
    final controller = SpeechSessionController()..start();
    controller.recordTranscript('transfer 500', isFinal: false);

    final completed = controller.recordTranscript(
      'transfer 5000 from jazzcash to cash',
      isFinal: true,
    );

    expect(completed.action, SpeechSessionAction.processFinal);
    expect(completed.transcript, 'transfer 5000 from jazzcash to cash');
  });
}

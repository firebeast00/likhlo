import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:student_expense_manager/features/voice/speech_network_recovery.dart';
import 'package:student_expense_manager/services/speech_session_controller.dart';
import 'package:student_expense_manager/services/speech_recognition_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('device provider forwards the offline request and keeps the selected locale', () async {
    const channel = MethodChannel('plugin.csdcorp.com/speech_to_text');
    final calls = <Map<dynamic, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'listen') calls.add(Map.from(call.arguments as Map));
      return true;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final provider = DeviceSpeechRecognitionProvider(speech: stt.SpeechToText.withMethodChannel());
    expect(await provider.initialize(onStatus: (_) {}, onError: (_) {}), isTrue);
    await provider.listen(options: const SpeechRecognitionListenOptions(localeId: 'ur_PK'),
      onResult: (_) async {});
    await provider.cancel();
    await provider.listen(options: const SpeechRecognitionListenOptions(localeId: 'ur_PK', onDevice: true),
      onResult: (_) async {});
    await provider.cancel();
    expect(calls.map((call) => call['onDevice']), [false, true]);
    expect(calls.map((call) => call['localeId']), ['ur_PK', 'ur_PK']);
  });

  for (final error in ['error_network', 'error_network_timeout', 'error_server']) {
    test('$error retries an empty device attempt once without a command', () {
      final recovery = SpeechNetworkRecovery();
      final session = SpeechSessionController(maxRetries: 1)..start();
      final retryable = recovery.tryOffline(error,
        isCloud: false, hasDraft: session.latestDraft.isNotEmpty,
        retryCount: session.retryCount);
      final decision = session.onRecognizerError(retryable: retryable);
      expect(decision.action, SpeechSessionAction.retry);
      expect(decision.transcript, isEmpty);
      expect(recovery.onDevice, isTrue);
      expect(recovery.tryOffline(error, isCloud: false, hasDraft: false,
        retryCount: session.retryCount), isFalse);
      final failure = session.onRecognizerError(retryable: false);
      expect(failure.action, SpeechSessionAction.none);
      expect(failure.transcript, isEmpty);
      expect(session.state, SpeechSessionState.failed);
      recovery.reset();
      expect(recovery.onDevice, isFalse);
    });
  }

  test('a draft, cloud provider, consumed retry and rate limit do not change recognition', () {
    for (final situation in [
      (cloud: true, draft: false, retries: 0, error: 'error_network'),
      (cloud: false, draft: true, retries: 0, error: 'error_network'),
      (cloud: false, draft: false, retries: 1, error: 'error_network'),
      (cloud: false, draft: false, retries: 0, error: 'error_too_many_requests'),
      (cloud: false, draft: false, retries: 0, error: 'error_language_unavailable'),
    ]) {
      final recovery = SpeechNetworkRecovery();
      expect(recovery.tryOffline(situation.error, isCloud: situation.cloud,
        hasDraft: situation.draft, retryCount: situation.retries), isFalse);
      expect(recovery.onDevice, isFalse);
    }
  });
}

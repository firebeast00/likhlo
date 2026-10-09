import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/services/local_nlp_service.dart';
import 'package:student_expense_manager/services/smart_command.dart';
import 'package:student_expense_manager/services/smart_input_engine.dart';
import 'package:student_expense_manager/services/speech_command_completeness.dart';
import 'package:student_expense_manager/services/speech_session_controller.dart';
import 'package:student_expense_manager/services/speech_timing_policy.dart';

class _SpeechClock {
  Duration now = Duration.zero;
  late final timing = SpeechTimingTracker(elapsed: () => now)..start();

  Duration? wait({bool complete = true, SpeechTimingKind kind = SpeechTimingKind.transaction}) =>
      timing.waitFor(isComplete: complete, kind: kind);

  void soundRange() {
    for (final level in [0.0, 1.0, 12.0, 11.0]) {
      timing.recordSoundLevel(level);
    }
  }
}

void main() {
  const accounts = [
    SmartEntryAccount(id: 'cash', name: 'Cash', type: 'cash', availableBalance: 10000),
    SmartEntryAccount(id: 'jazzcash', name: 'JazzCash', type: 'jazzcash', availableBalance: 10000),
  ];
  const categories = ['Food', 'Transport', 'Shopping', 'General'];
  for (final example in {
    '500 petrol': SmartEntryIntent.addExpense,
    '80 jama karo cash mein': SmartEntryIntent.addIncome,
    'delete burger': SmartEntryIntent.deleteEntry,
    'petrol wali entries dikhao': SmartEntryIntent.searchEntries,
  }.entries) {
    test('complete stable speech dispatches ${example.value.name} without native final', () {
      final plan = SmartInputEngine().parse(example.key, categories,
          source: SmartInputSource.voice, accounts: accounts);
      final completeness = const SpeechCommandCompletenessEvaluator()
          .evaluate(plan, accounts: accounts);
      expect(plan.parsed.intent, example.value);
      expect(completeness.isComplete, isTrue);
      final c = _SpeechClock();
      final session = SpeechSessionController()..start();
      c.timing.recordTranscript(example.key, isFinal: false);
      session.recordTranscript(example.key, isFinal: false);
      c.now = const Duration(seconds: 3);
      expect(c.wait(complete: completeness.isComplete), Duration.zero);
      expect(c.timing.hasFinalResult, isFalse);
      final decision = session.onStableTranscript(isComplete: completeness.isComplete);
      expect(decision.action, SpeechSessionAction.processFinal);
      expect(decision.transcript, example.key);
      // Endpoint acceptance changes when dispatch occurs, not its NLP intent.
      final submitted = SmartInputEngine().parse(decision.transcript, categories,
          source: SmartInputSource.voice, accounts: accounts);
      expect(submitted.parsed.intent, plan.parsed.intent);
      expect(submitted.parsed.amount, plan.parsed.amount);
      expect(submitted.requiresAsrReview, plan.requiresAsrReview);
      expect(submitted.parsed.clarificationReasons, plan.parsed.clarificationReasons);
    });
  }

  test('a same-text final upgrades a partial to the short final window', () {
    final c = _SpeechClock();
    c.timing.recordTranscript('500 biryani', isFinal: false);
    expect(c.wait(), const Duration(seconds: 3));
    c.now = const Duration(milliseconds: 500);
    expect(c.timing.recordTranscript('500 biryani', isFinal: true), isFalse);
    expect(c.wait(), const Duration(milliseconds: 100));
    c.now = const Duration(milliseconds: 600);
    expect(c.wait(), Duration.zero);
  });

  test('repeated partial callbacks do not extend the quiet window', () {
    final c = _SpeechClock();
    c.timing.recordTranscript('500 biryani', isFinal: false);
    c.now = const Duration(milliseconds: 1100);
    expect(c.timing.recordTranscript(' 500 biryani ', isFinal: false), isFalse);
    expect(c.wait(), const Duration(milliseconds: 1900));
  });

  test('a changed partial invalidates older final evidence', () {
    final c = _SpeechClock();
    c.timing.recordTranscript('500 biryani', isFinal: true);
    c.now = const Duration(milliseconds: 80);
    c.timing.recordTranscript('500 biryani from JazzCash', isFinal: false);
    expect(c.timing.hasFinalResult, isFalse);
    expect(c.wait(), const Duration(seconds: 3));
  });

  test('incomplete active speech is not expired by a quiet timer', () {
    final c = _SpeechClock();
    c.timing.recordTranscript('transfer 500 from', isFinal: false);
    c.now = const Duration(seconds: 20);
    expect(c.wait(complete: false), isNull);
  });

  test('an incomplete native final can finish promptly for review', () {
    final c = _SpeechClock();
    c.timing.recordTranscript('transfer 500 from', isFinal: true);
    expect(c.wait(complete: false), const Duration(milliseconds: 100));
  });

  test('native end without a final keeps result grace, not the long stability wait', () {
    final c = _SpeechClock();
    c.timing.recordTranscript('500 biryani', isFinal: false);
    c.timing.recordEnd();
    expect(c.wait(), const Duration(milliseconds: 200));
    expect(c.wait(complete: false), const Duration(milliseconds: 200));
    expect(c.timing.hasFinalResult, isFalse);
  });

  test('notListening leaves bounded grace for late corrected words', () {
    final c = _SpeechClock();
    c.timing.recordTranscript('500 biryani', isFinal: false);
    c.timing.recordEnd();
    c.now = const Duration(milliseconds: 100);
    c.timing.recordTranscript('500 biryani from cash', isFinal: false);
    expect(c.wait(), const Duration(milliseconds: 200));
    c.now = const Duration(milliseconds: 300);
    expect(c.wait(), Duration.zero);
  });

  test('repeated end callbacks do not restart result grace', () {
    final c = _SpeechClock();
    c.timing.recordEnd();
    c.now = const Duration(milliseconds: 150);
    c.timing.recordEnd();
    expect(c.wait(), const Duration(milliseconds: 50));
  });

  test('final words after native end remove the remaining result grace', () {
    final c = _SpeechClock();
    c.timing.recordEnd();
    c.now = const Duration(milliseconds: 50);
    c.timing.recordTranscript('500 biryani', isFinal: true);
    expect(c.wait(), Duration.zero);
  });

  test('ongoing sound holds a complete phrase even without new ASR words', () {
    final c = _SpeechClock();
    c.soundRange();
    c.timing.recordTranscript('500 biryani', isFinal: false);
    c.now = const Duration(milliseconds: 700);
    c.timing.recordSoundLevel(12);
    c.now = const Duration(milliseconds: 1200);
    expect(c.wait(), const Duration(milliseconds: 350));
  });

  test('query, transaction and extended commands have distinct quiet windows', () {
    final c = _SpeechClock();
    c.soundRange();
    c.timing.recordTranscript('a complete command', isFinal: false);
    expect(c.wait(kind: SpeechTimingKind.query), const Duration(milliseconds: 450));
    expect(c.wait(), const Duration(milliseconds: 850));
    expect(c.wait(kind: SpeechTimingKind.extended), const Duration(milliseconds: 1300));
  });

  test('flat and invalid sound levels retain conservative fallback', () {
    final c = _SpeechClock();
    for (final level in [double.nan, double.infinity, 5.0, 5.0, 5.0, 5.0]) {
      c.timing.recordSoundLevel(level);
    }
    c.timing.recordTranscript('500 biryani', isFinal: false);
    expect(c.timing.hasUsefulSoundLevels, isFalse);
    expect(c.wait(), const Duration(seconds: 3));
    expect(c.wait(kind: SpeechTimingKind.query), const Duration(milliseconds: 1200));
  });

  test('speech after a final result holds the short endpoint grace', () {
    final c = _SpeechClock();
    c.soundRange();
    c.timing.recordTranscript('500 biryani', isFinal: true);
    c.now = const Duration(milliseconds: 90);
    c.timing.recordSoundLevel(12);
    c.now = const Duration(milliseconds: 100);
    expect(c.wait(), const Duration(milliseconds: 90));
  });

  test('a restarted recognition cycle drops prior endpoint and sound evidence', () {
    final c = _SpeechClock();
    c.soundRange();
    c.timing.recordTranscript('500 biryani', isFinal: true);
    c.timing.recordEnd();
    c.now = const Duration(seconds: 1);
    c.timing.startCycle();
    expect(c.timing.hasFinalResult, isFalse);
    expect(c.timing.recognizerEnded, isFalse);
    expect(c.timing.hasUsefulSoundLevels, isFalse);
    expect(c.wait(complete: false), isNull);
  });

  test('diagnostics retain stage timestamps separately from endpoint flags', () {
    final c = _SpeechClock();
    c.now = const Duration(milliseconds: 600);
    c.timing.recordTranscript('500 biryani', isFinal: true);
    c.now = const Duration(milliseconds: 650);
    c.timing.recordEnd();
    expect(c.timing.timings['final_result_received'], 600);
    expect(c.timing.timings['recognizer_ended'], 650);
    expect(c.timing.timings['has_final_result'], isTrue);
    expect(c.timing.timings['recognizer_has_ended'], isTrue);
  });

  testWidgets('ended recognition processes before redundant cleanup finishes', (tester) async {
    final c = _SpeechClock();
    c.timing.recordTranscript('500 biryani', isFinal: true);
    c.timing.recordEnd();
    final cleanup = Completer<void>();
    var requestedResult = false;
    await reconcileSpeechEndpoint(
      timing: c.timing, cleanup: cleanup.future,
      finalResult: () { requestedResult = true; return Completer<void>().future; },
      isCurrent: () => true,
    );
    expect(cleanup.isCompleted, isFalse);
    expect(requestedResult, isFalse);
    cleanup.completeError(StateError('redundant cleanup failure'));
    await tester.pump();
  });

  testWidgets('native final does not wait for a slow stop response', (tester) async {
    final c = _SpeechClock();
    c.timing.recordTranscript('500 biryani', isFinal: true);
    final cleanup = Completer<void>();
    await reconcileSpeechEndpoint(
      timing: c.timing, cleanup: cleanup.future,
      finalResult: () => Completer<void>().future, isCurrent: () => true,
    );
    expect(cleanup.isCompleted, isFalse);
    cleanup.complete();
    await tester.pump();
  });

  testWidgets('late final during cleanup replaces the draft and executes once', (tester) async {
    final c = _SpeechClock();
    final session = SpeechSessionController()..start();
    session.recordTranscript('500 biryani', isFinal: false);
    c.timing.recordTranscript('500 biryani', isFinal: false);
    final cleanup = Completer<void>();
    final result = Completer<void>();
    var reconciled = false;
    final pending = reconcileSpeechEndpoint(
      timing: c.timing, cleanup: cleanup.future,
      finalResult: () => result.future, isCurrent: () => true,
    ).then((_) => reconciled = true);
    await tester.pump();
    expect(reconciled, isFalse);
    session.recordTranscript('500 biryani from JazzCash', isFinal: false);
    c.timing.recordTranscript(session.latestDraft, isFinal: true);
    result.complete();
    await pending;
    expect(cleanup.isCompleted, isFalse);
    final decision = session.recordTranscript(session.latestDraft, isFinal: true);
    expect(decision.action, SpeechSessionAction.processFinal);
    expect(decision.transcript, '500 biryani from JazzCash');
    expect(session.recordTranscript('5000 biryani', isFinal: true).action,
        SpeechSessionAction.none);
    cleanup.complete();
    await tester.pump();
  });

  testWidgets('elapsed endpoint grace is not paid again during reconciliation', (tester) async {
    final c = _SpeechClock();
    c.timing.recordEnd();
    c.now = const Duration(milliseconds: 200);
    final cleanup = Completer<void>();
    var requestedResult = false;
    await reconcileSpeechEndpoint(
      timing: c.timing, cleanup: cleanup.future,
      finalResult: () { requestedResult = true; return Completer<void>().future; },
      isCurrent: () => true,
    );
    expect(requestedResult, isFalse);
    cleanup.complete();
    await tester.pump();
  });

  testWidgets('missing native final has a bounded reconciliation wait', (tester) async {
    final c = _SpeechClock();
    c.timing.recordTranscript('500 biryani', isFinal: false);
    c.timing.recordEnd();
    var done = false;
    final pending = reconcileSpeechEndpoint(
      timing: c.timing, cleanup: Future<void>.value(),
      finalResult: () => Completer<void>().future, isCurrent: () => true,
    ).then((_) => done = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 199));
    expect(done, isFalse);
    c.now = const Duration(milliseconds: 200);
    await tester.pump(const Duration(milliseconds: 1));
    await pending;
    expect(done, isTrue);
    expect(c.timing.hasFinalResult, isFalse);
  });

  testWidgets('disposed sessions do not accept an endpoint after cleanup', (tester) async {
    final c = _SpeechClock();
    final cleanup = Completer<void>();
    var current = true;
    final pending = reconcileSpeechEndpoint(
      timing: c.timing, cleanup: cleanup.future,
      finalResult: () => Completer<void>().future, isCurrent: () => current,
    );
    current = false;
    cleanup.complete();
    await pending;
    expect(c.timing.recognizerEnded, isFalse);
  });

  testWidgets('late final wakes reconciliation before result grace expires', (tester) async {
    final c = _SpeechClock();
    c.timing.recordEnd();
    final result = Completer<void>();
    final pending = reconcileSpeechEndpoint(
      timing: c.timing, cleanup: Future<void>.value(),
      finalResult: () => result.future, isCurrent: () => true,
    );
    await tester.pump();
    c.timing.recordTranscript('500 biryani', isFinal: true);
    result.complete();
    await pending;
    expect(c.timing.hasFinalResult, isTrue);
  });

  testWidgets('active recognizer cleanup failure is surfaced to the caller', (tester) async {
    final c = _SpeechClock();
    final cleanup = Completer<void>();
    final pending = reconcileSpeechEndpoint(
      timing: c.timing, cleanup: cleanup.future,
      finalResult: () => Completer<void>().future, isCurrent: () => true,
    );
    final assertion = expectLater(pending, throwsStateError);
    cleanup.completeError(StateError('stop failed'));
    await assertion;
  });
}

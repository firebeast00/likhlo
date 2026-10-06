import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/services/voice_diagnostic_observer.dart';
import 'package:student_expense_manager/services/smart_input_engine.dart';
import 'package:student_expense_manager/services/smart_command.dart';
import 'package:student_expense_manager/services/udhar_input_service.dart';

void main() {
  const categories = ['General', 'Food', 'Transport', 'Education', 'Shopping'];
  tearDown(() { VoiceDiagnosticObserver.sink = null; VoiceDiagnosticObserver.enabled = false; });

  test('observer failure cannot change English, Roman Urdu or Urdu parser output', () {
    final engine = SmartInputEngine();
    for (final input in ['150 ka jute add karo', '500 biryani', 'Show me food expenses', '۵۰۰ بریانی', 'hello there']) {
      final baseline = engine.parse(input, categories, source: SmartInputSource.voice);
      VoiceDiagnosticObserver.enabled = true;
      VoiceDiagnosticObserver.sink = (_, __, ___) => throw StateError('diagnostic failure');
      final observed = VoiceDiagnosticObserver.run('command', () => engine.parse(input, categories, source: SmartInputSource.voice));
      expect(observed.normalizedText, baseline.normalizedText);
      final actual = observed.parsed.toLegacyMap()..remove('date');
      final expected = baseline.parsed.toLegacyMap()..remove('date');
      expect(actual, expected);
      expect(observed.parsed.date.year, baseline.parsed.date.year);
      expect(observed.parsed.date.month, baseline.parsed.date.month);
      expect(observed.parsed.date.day, baseline.parsed.date.day);
      expect(observed.requiresAsrReview, baseline.requiresAsrReview);
    }
  });
  test('only final command scope emits original text, rules, intent and fields', () {
    final events = <Map<String, dynamic>>[];
    VoiceDiagnosticObserver.enabled = true;
    VoiceDiagnosticObserver.sink = (id, stage, data) => events.add({'id': id, 'stage': stage, 'data': data});
    final engine = SmartInputEngine();
    engine.parse('150 ka jute add karo', categories); // Preliminary/typed.
    expect(events, isEmpty);
    VoiceDiagnosticObserver.run('voice-id', () => engine.parse('150 ka jute add karo', categories, source: SmartInputSource.voice));
    expect(events.map((e) => e['stage']), ['normalization', 'parse']);
    expect(events.first['data']['original'], '150 ka jute add karo');
    expect(events.last['data']['intent'], 'add_expense');
    expect(events.last['data']['amount'], 150);
  });
  test('Udhaar normalization and parser observers preserve person, amount and safety', () {
    const parser = UdharInputService();
    final baseline = parser.parse('Ali ko 500 udhar diya');
    VoiceDiagnosticObserver.enabled = true;
    VoiceDiagnosticObserver.sink = (_, __, ___) => throw StateError('diagnostic failure');
    final observed = VoiceDiagnosticObserver.run('debt', () => parser.parse('Ali ko 500 udhar diya'));
    expect(observed?.person, baseline?.person); expect(observed?.amount, baseline?.amount);
    expect(observed?.canSaveImmediately, baseline?.canSaveImmediately);
  });
}

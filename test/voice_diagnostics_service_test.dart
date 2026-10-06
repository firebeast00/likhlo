import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/services/voice_diagnostics_service.dart';

class MemoryDiagnosticStorage implements VoiceDiagnosticStorage {
  final values = <String, String>{};
  bool fail = false;
  @override
  Future<Map<String, String>> load() async {
    if (fail) throw StateError('disk unavailable');
    return Map.of(values);
  }
  @override
  Future<void> put(String id, String json) async {
    if (fail) throw StateError('disk unavailable');
    values[id] = json;
  }
  @override
  Future<void> delete(String id) async {
    if (fail) throw StateError('disk unavailable');
    values.remove(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryDiagnosticStorage storage;
  late VoiceDiagnosticsService service;
  late DateTime now;
  setUp(() async {
    now = DateTime.utc(2026, 10, 6);
    storage = MemoryDiagnosticStorage();
    service = VoiceDiagnosticsService(storage, enabled: true, clock: () => now);
    await service.initialize();
  });
  tearDown(() async { await service.flush(); service.dispose(); });
  String begin() => service.begin(entryPoint: 'test_microphone')!;

  test('default off captures no transcripts', () {
    final off = VoiceDiagnosticsService(storage);
    expect(off.begin(entryPoint: 'test'), isNull);
    off.event(null, 'recognition', {'text': 'secret'});
    expect(off.records, isEmpty);
    off.dispose();
  });
  test('preserves raw ASR separately from submitted and normalized input', () async {
    final id = begin();
    service.event(id, 'recognition', {'text': '  show rupay chai  ', 'is_final': true, 'confidence': null});
    service.submitted(id, 'show rupay chai');
    service.run(id, () => service.stage('normalization', {'normalized': '100 rupay chai', 'applied_rules': ['context_rule']}));
    service.finish(id, 'completed');
    await service.flush();
    final r = jsonDecode(storage.values[id]!);
    expect(r['raw_transcript'], '  show rupay chai  ');
    expect(r['submitted_transcript'], 'show rupay chai');
    expect(r['normalization']['normalized'], '100 rupay chai');
    expect(r['events'][0]['data']['confidence'], isNull);
  });
  test('completion survives late reset, errors, and submitted calls', () {
    final id = begin(); service.finish(id, 'completed');
    service.finish(id, 'failed'); service.finish(id, 'interrupted'); service.submitted(id, 'late');
    expect(service.record(id)!['outcome'], 'completed');
  });
  test('review may mark a completed save misunderstood', () async {
    final id = begin(); service.finish(id, 'completed');
    await service.review(id, assessment: 'wrong', failureStage: 'recognition', spoken: 'sau chai', expected: '100 expense for chai');
    expect(service.record(id)!['outcome'], 'completed');
    expect(service.record(id)!['review']['assessment'], 'wrong');
  });
  test('async scopes keep concurrent commands separate', () async {
    final a = begin(), b = begin();
    await Future.wait([
      service.run(a, () async { await Future<void>.delayed(Duration.zero); service.stage('parse', {'intent': 'query'}); }),
      service.run(b, () async { service.stage('parse', {'intent': 'add_expense'}); }),
    ]);
    service.stage('parse', {'intent': 'typed_unrelated'});
    expect(service.record(a)!['parse']['intent'], 'query');
    expect(service.record(b)!['parse']['intent'], 'add_expense');
    expect(service.currentId, isNull);
  });
  test('confirmation can be retried after rejection and then committed', () {
    final id = begin();
    service.run(id, () {
      service.awaitingConfirmation();
      service.stage('execution', {'status': 'rejected'});
      service.stage('execution', {'status': 'succeeded'});
    });
    service.finishProcessing(id, true);
    expect(service.record(id)!['outcome'], 'completed');
  });
  test('dismissed confirmation is cancellation rather than parse failure', () {
    final id = begin(); service.awaitingConfirmation(id: id);
    service.finishProcessing(id, false);
    expect(service.record(id)!['outcome'], 'cancelled');
  });
  test('unknown parse is not understood rather than completed', () {
    final id = begin(); service.run(id, () => service.stage('parse', {'intent': 'unknown'}));
    service.finishProcessing(id, false);
    expect(service.record(id)!['outcome'], 'not_understood');
  });
  test('TTS failure cannot change committed action outcome', () {
    final id = begin(); service.finish(id, 'completed');
    service.stage('tts', {'status': 'failed', 'completion_observed': false}, id: id);
    expect(service.record(id)!['outcome'], 'completed');
    expect(service.record(id)!['tts']['status'], 'failed');
  });
  test('disk failures do not throw or prevent command completion', () async {
    storage.fail = true; final id = begin();
    service.finish(id, 'completed'); await service.flush();
    expect(service.record(id)!['outcome'], 'completed');
    expect(service.storageError, isNotNull);
    storage.fail = false; await service.flush();
    expect(storage.values[id], isNotNull);
  });
  test('changed partials have bounded history and visible drop count', () {
    final id = begin();
    for (var i = 0; i < 150; i++) { service.event(id, 'recognition', {'text': 'partial $i', 'is_final': false}); }
    service.finish(id, 'incomplete');
    final r = service.record(id)!;
    expect((r['events'] as List).length, VoiceDiagnosticsService.maxEvents);
    expect(r['dropped_events'], greaterThan(0));
    expect(r['raw_transcript'], 'partial 149');
  });
  test('repeated partials are deduplicated while final flag is retained', () {
    final id = begin();
    for (var i = 0; i < 5; i++) { service.event(id, 'recognition', {'text': 'chai', 'is_final': false}); }
    service.event(id, 'recognition', {'text': 'chai', 'is_final': true});
    expect((service.record(id)!['events'] as List).length, 2);
  });
  test('restart recovers in-flight commands with unknown action outcome', () async {
    final id = begin(); await service.flush();
    final restarted = VoiceDiagnosticsService(storage, clock: () => now);
    await restarted.initialize();
    expect(restarted.record(id)!['outcome'], 'interrupted');
    expect(restarted.record(id)!['outcome_reason'], contains('action_unknown'));
    restarted.dispose();
  });
  test('age, count and byte retention delete only diagnostic records', () async {
    final old = begin(); service.finish(old, 'completed'); await service.flush();
    now = now.add(const Duration(days: 31));
    final fresh = begin(); service.finish(fresh, 'completed'); await service.flush();
    expect(service.record(old), isNull); expect(service.record(fresh), isNotNull);
    final limited = VoiceDiagnosticsService(storage, enabled: true, recordLimit: 1, byteLimit: 100000, clock: () => now);
    await limited.initialize();
    now = now.add(const Duration(seconds: 1));
    final second = limited.begin(entryPoint: 'test')!; await limited.flush();
    expect(limited.records.single['id'], second); limited.dispose();
    final tiny = VoiceDiagnosticsService(storage, byteLimit: 1, clock: () => now);
    await tiny.initialize(); await tiny.flush(); expect(tiny.records, isEmpty); tiny.dispose();
  });
  test('name masking and selection affect export only, metrics use reviewed records', () async {
    final a = begin(), b = begin();
    service.event(a, 'recognition', {'text': 'Ali ko 500 udhar diya'});
    service.run(a, () => service.stage('parse', {'intent': 'udhar_lent', 'person': 'Ali'}));
    await service.review(a, assessment: 'correct');
    final report = service.export(ids: [a], maskNames: true);
    expect(report['summary']['selected'], 1); expect(report['summary']['reviewed_accuracy'], 1);
    expect(jsonEncode(report['commands']), isNot(contains('Ali')));
    expect(service.record(a)!['raw_transcript'], contains('Ali'));
    expect(jsonEncode(report['commands']), isNot(contains(b)));
    expect(service.export(ids: [b])['summary']['reviewed_accuracy'], isNull);
  });
  test('cleared records cannot be resurrected by late callbacks', () async {
    final id = begin(); await service.flush(); await service.clear();
    service.event(id, 'recognition', {'text': 'late'}); service.finish(id, 'completed'); await service.flush();
    expect(service.records, isEmpty); expect(storage.values, isEmpty);
  });
  test('disabling capture stops further events and preserves reviewed history', () async {
    final id = begin(); await service.setEnabled(false);
    service.event(id, 'recognition', {'text': 'private after opt-out'});
    expect(service.begin(entryPoint: 'test'), isNull);
    expect(service.record(id)!['outcome'], 'interrupted');
    expect(jsonEncode(service.record(id)), isNot(contains('private after opt-out')));
  });
}

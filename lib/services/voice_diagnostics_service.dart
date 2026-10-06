import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'voice_diagnostic_observer.dart';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

/// Separate from the existing anonymous timing diagnostics. These records
/// contain transcripts and must only be captured with the tester's opt-in.
abstract interface class VoiceDiagnosticStorage {
  Future<Map<String, String>> load();
  Future<void> put(String id, String json);
  Future<void> delete(String id);
}

class HiveVoiceDiagnosticStorage implements VoiceDiagnosticStorage {
  Box<String>? _box;
  Future<Box<String>> _open() async =>
      _box ??= await Hive.openBox<String>('voice_command_diagnostics_v1');

  @override
  Future<Map<String, String>> load() async {
    final box = await _open();
    return {for (final key in box.keys) key.toString(): box.get(key)!};
  }

  @override
  Future<void> put(String id, String json) async => (await _open()).put(id, json);
  @override
  Future<void> delete(String id) async => (await _open()).delete(id);
}

Map<String, Map<String, dynamic>> _decodeRecords(Map<String, String> values) {
  final result = <String, Map<String, dynamic>>{};
  for (final item in values.entries) {
    try {
      final decoded = jsonDecode(item.value);
      if (decoded is Map && decoded['schema_version'] == 1) {
        result[item.key] = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // A damaged diagnostic never prevents opening the financial app.
    }
  }
  return result;
}

Map<String, String> _encodeRecords(Map<String, Map<String, dynamic>> values) =>
    values.map((key, value) => MapEntry(key, jsonEncode(value)));

String encodeVoiceDiagnosticExport(Map<String, dynamic> report) {
  final names = (report.remove('_masking_names') as List?)?.cast<String>();
  final mask = report.remove('_masking_enabled') == true;
  if (names != null && mask) report['commands'] = _maskValues(report['commands'], names);
  return const JsonEncoder.withIndent('  ').convert(report);
}

dynamic _maskValues(dynamic value, List<String> names) {
  if (names.isEmpty) return value;
  final labels = {for (var i = 0; i < names.length; i++) names[i].toLowerCase(): '[name_${i + 1}]'};
  final pattern = RegExp(names.map(RegExp.escape).join('|'), caseSensitive: false);
  dynamic visit(dynamic v) {
    if (v is String) return v.replaceAllMapped(pattern, (match) => labels[match.group(0)!.toLowerCase()]!);
    if (v is Map) return v.map((key, item) => MapEntry(key, visit(item)));
    if (v is List) return v.map(visit).toList();
    return v;
  }
  return visit(value);
}

dynamic _cloneValue(dynamic value) {
  if (value is Map) return value.map((key, item) => MapEntry(key, _cloneValue(item)));
  if (value is List) return value.map(_cloneValue).toList();
  return value;
}

class VoiceDiagnosticsService extends ChangeNotifier {
  static final instance = _createInstance();
  static VoiceDiagnosticsService _createInstance() {
    final service = VoiceDiagnosticsService(HiveVoiceDiagnosticStorage());
    VoiceDiagnosticObserver.sink = (id, name, data) => service.stage(name, data, id: id);
    return service;
  }
  static const enabledKey = VoiceDiagnosticObserver.enabledKey;
  static const historyKey = VoiceDiagnosticObserver.historyKey;
  static const retention = Duration(days: 30);
  static const maxRecords = 2000;
  static const maxBytes = 10 * 1024 * 1024;
  static const maxEvents = 120;
  static const maxTextLength = 2048;
  static const terminalOutcomes = {
    'completed', 'not_understood', 'blocked', 'failed', 'incomplete',
    'no_speech', 'cancelled', 'interrupted',
  };

  final VoiceDiagnosticStorage storage;
  final DateTime Function() clock;
  final int recordLimit;
  final int byteLimit;
  final bool useIsolates;
  final Map<String, Map<String, dynamic>> _records = {};
  final Map<String, int> _sizes = {};
  final Set<String> _dirty = {};
  final Set<String> _deleted = {};
  Future<void>? _initialization;
  Future<void> _writes = Future<void>.value();
  Timer? _flushTimer;
  bool _disposed = false;
  bool _enabled;
  String? storageError;
  int evictedRecords = 0;

  VoiceDiagnosticsService(this.storage, {
    DateTime Function()? clock,
    bool enabled = false,
    this.recordLimit = maxRecords,
    this.byteLimit = maxBytes,
    this.useIsolates = true,
  }) : clock = clock ?? DateTime.now, _enabled = enabled;

  bool get enabled => _enabled;
  String? get currentId => VoiceDiagnosticObserver.currentId;
  List<Map<String, dynamic>> get records {
    final sorted = _records.values.toList()
      ..sort((a, b) => (b['started_at'] as String).compareTo(a['started_at'] as String));
    // Screens and exporters never receive mutable store objects.
    return sorted.map((value) => _copy(value)).toList(growable: false);
  }

  int get recordCount => _records.length;
  List<Map<String, dynamic>> get summaries {
    final items = _records.values.map((r) => <String, dynamic>{
      for (final key in ['id', 'started_at', 'outcome', 'raw_transcript', 'submitted_transcript']) key: r[key],
      'review': {'assessment': r['review']['assessment']},
    }).toList()..sort((a, b) => (b['started_at'] as String).compareTo(a['started_at'] as String));
    return items;
  }

  Map<String, dynamic>? record(String id) =>
      _records[id] == null ? null : _copy(_records[id]!);

  static Map<String, dynamic> _copy(Map<String, dynamic> value) =>
      Map<String, dynamic>.from(_cloneValue(value) as Map);

  /// Called after the first frame; opening this box is not a startup dependency.
  void start() {
    try {
      if (Hive.isBoxOpen('preferences')) {
        _enabled = Hive.box('preferences').get(enabledKey, defaultValue: false) == true;
      }
      VoiceDiagnosticObserver.enabled = _enabled;
      if (_enabled || Hive.isBoxOpen('preferences') && Hive.box('preferences').get(historyKey) == true) unawaited(initialize());
    } catch (_) {
      storageError = 'preferences_unavailable';
    }
  }

  Future<void> initialize() => _initialization ??= _load();

  Future<void> _load() async {
    try {
      final values = await storage.load();
      final loaded = useIsolates ? await compute(_decodeRecords, values) : _decodeRecords(values);
      for (final entry in loaded.entries) {
        if (_deleted.contains(entry.key) || _records.containsKey(entry.key)) continue;
        final record = entry.value;
        // A killed process cannot tell us whether an in-flight action committed.
        if (!terminalOutcomes.contains(record['outcome'])) {
          record['outcome'] = 'interrupted';
          record['ended_at'] = clock().toUtc().toIso8601String();
          record['outcome_reason'] = 'recovered_after_process_exit_action_unknown';
          _dirty.add(entry.key);
        }
        _records[entry.key] = record;
        _sizes[entry.key] = utf8.encode(values[entry.key]!).length;
      }
      _prune();
      _notify();
      _scheduleFlush();
    } catch (_) {
      storageError = 'diagnostic_storage_unavailable';
      _notify();
    }
  }

  Future<void> setEnabled(bool value) async {
    // Preference errors are reported to this screen, never to a voice command.
    if (Hive.isBoxOpen('preferences')) {
      await Hive.box('preferences').put(enabledKey, value);
      if (value) await Hive.box('preferences').put(historyKey, true);
    }
    if (!value) {
      for (final id in _records.keys.toList()) {
        finish(id, 'interrupted', reason: 'capture_disabled');
      }
    }
    _enabled = value;
    if (identical(this, instance)) VoiceDiagnosticObserver.enabled = value;
    await initialize();
    _notify();
  }

  String? begin({required String entryPoint, Map<String, dynamic> context = const {}}) {
    if (!_enabled) return null;
    try {
      final id = const Uuid().v4();
      _records[id] = {
        'schema_version': 1,
        'id': id,
        'started_at': clock().toUtc().toIso8601String(),
        'entry_point': entryPoint,
        'context': _safe(context),
        'outcome': 'listening',
        'raw_transcript': '',
        'submitted_transcript': null,
        'events': <dynamic>[],
        'dropped_events': 0,
        'text_truncated': false,
        'review': {'assessment': 'unreviewed', 'failure_stage': null},
        'tts': {'status': 'not_requested', 'completion_observed': false},
      };
      _changed(id);
      _scheduleFlush(immediate: true);
      unawaited(initialize());
      return id;
    } catch (_) {
      return null;
    }
  }

  T run<T>(String? id, T Function() action) =>
      VoiceDiagnosticObserver.run(id, action);

  void event(String? id, String stage, Map<String, dynamic> data) {
    if (!_enabled || id == null) return;
    try {
      final record = _records[id];
      if (record == null) return;
      final events = record['events'] as List;
      final safe = _safe(data);
      if (stage == 'recognition') {
        final raw = safe['text'] as String? ?? '';
        record['raw_transcript'] = raw;
        if ((data['text'] as String? ?? '').length > maxTextLength) record['text_truncated'] = true;
        if (events.isNotEmpty && events.last is Map &&
            events.last['stage'] == stage && events.last['data']['text'] == raw &&
            events.last['data']['is_final'] == safe['is_final']) return;
      }
      final newEvent = {'at': clock().toUtc().toIso8601String(), 'stage': stage, 'data': safe};
      if (events.length >= maxEvents) {
        // Keep the start and most recent events, including terminal/error events.
        events.removeAt(1);
        record['dropped_events'] = (record['dropped_events'] as int) + 1;
      }
      events.add(newEvent);
      _changed(id);
    } catch (_) {
      // All observer APIs are failure-isolated from business logic.
    }
  }

  void stage(String stage, Map<String, dynamic> data, {String? id}) {
    id ??= currentId;
    if (!_enabled || id == null) return;
    try {
      final record = _records[id];
      if (record == null) return;
      record[stage] = _safe(data);
      event(id, stage, data);
    } catch (_) {}
  }

  void submitted(String? id, String transcript) {
    if (!_enabled || id == null || !_records.containsKey(id)) return;
    if (terminalOutcomes.contains(_records[id]!['outcome'])) return;
    if (transcript.length > maxTextLength) _records[id]!['text_truncated'] = true;
    _records[id]!['submitted_transcript'] = _text(transcript);
    _records[id]!['outcome'] = 'processing';
    _changed(id);
  }

  void awaitingConfirmation({String? id, String? reason}) {
    id ??= currentId;
    if (!_enabled || id == null || !_records.containsKey(id)) return;
    if (terminalOutcomes.contains(_records[id]!['outcome'])) return;
    _records[id]!['outcome'] = 'awaiting_confirmation';
    event(id, 'confirmation', {'status': 'awaiting', 'reason': reason});
  }

  /// First terminal result wins. Late recognizer resets cannot overwrite saves.
  void finish(String? id, String outcome, {String? reason}) {
    if (!_enabled || id == null) return;
    try {
      final record = _records[id];
      if (record == null || terminalOutcomes.contains(record['outcome'])) return;
      record['outcome'] = outcome;
      record['ended_at'] = clock().toUtc().toIso8601String();
      record['duration_ms'] = clock().difference(DateTime.parse(record['started_at'] as String)).inMilliseconds;
      record['outcome_reason'] = reason == null ? null : _text(reason);
      event(id, 'outcome', {'status': outcome, 'reason': reason});
      _scheduleFlush(immediate: true);
    } catch (_) {}
  }

  void finishProcessing(String? id, bool accepted) {
    final value = id == null ? null : _records[id];
    if (value == null) return;
    if ((value['execution'] as Map?)?['status'] == 'succeeded') {
      finish(id, 'completed', reason: 'execution_committed');
    } else if (value['outcome'] == 'awaiting_confirmation' && !accepted) {
      finish(id, 'cancelled', reason: 'confirmation_dismissed');
    } else {
      final unknown = (value['parse'] as Map?)?['intent'] == 'unknown';
      finish(id, accepted ? 'completed' : unknown ? 'not_understood' : 'blocked',
          reason: accepted ? 'handler_accepted' : 'handler_did_not_complete');
    }
  }

  Future<void> review(String id, {required String assessment,
    String? failureStage, String spoken = '', String expected = '', String notes = '',
  }) async {
    final record = _records[id];
    if (record == null) return;
    record['review'] = {
      'assessment': assessment, 'failure_stage': failureStage,
      'actually_spoken': _text(spoken), 'expected_result': _text(expected),
      'notes': _text(notes), 'reviewed_at': clock().toUtc().toIso8601String(),
    };
    _changed(id);
    await flush();
  }

  Future<void> remove(Iterable<String> ids) async {
    await initialize();
    for (final id in ids) {
      _records.remove(id);
      _sizes.remove(id);
      _dirty.remove(id);
      _deleted.add(id);
    }
    _notify();
    await flush();
  }

  Future<void> clear() async {
    await initialize();
    await remove(_records.keys.toList());
  }

  String _text(String text) => text.length <= maxTextLength ? text : text.substring(0, maxTextLength);
  dynamic _safeValue(dynamic value) {
    if (value is String) return _text(value);
    if (value is DateTime) return value.toIso8601String();
    if (value is num) return value.isFinite ? value : null;
    if (value == null || value is bool) return value;
    if (value is Map) return {for (final e in value.entries.take(40)) e.key.toString(): _safeValue(e.value)};
    if (value is Iterable) return value.take(40).map(_safeValue).toList();
    return _text(value.toString());
  }
  Map<String, dynamic> _safe(Map<String, dynamic> data) => Map<String, dynamic>.from(_safeValue(data) as Map);

  void _changed(String id) {
    _dirty.add(id);
    _scheduleFlush();
  }
  void _notify() {
    if (!_disposed) notifyListeners();
  }
  void _scheduleFlush({bool immediate = false}) {
    if (_disposed) return;
    if (!immediate && (_flushTimer?.isActive ?? false)) return;
    _flushTimer?.cancel();
    _flushTimer = Timer(immediate ? Duration.zero : const Duration(milliseconds: 400), () => unawaited(flush()));
  }

  void _prune() {
    final oldest = _records.keys.toList()
      ..sort((a, b) => (_records[a]!['started_at'] as String).compareTo(_records[b]!['started_at'] as String));
    var total = _sizes.values.fold<int>(0, (a, b) => a + b);
    for (final id in oldest) {
      final old = clock().difference(DateTime.parse(_records[id]!['started_at'] as String)) > retention;
      if (!old && _records.length <= recordLimit && total <= byteLimit) continue;
      total -= _sizes.remove(id) ?? 0;
      _records.remove(id);
      _dirty.remove(id);
      _deleted.add(id);
      evictedRecords++;
    }
  }

  Future<void> flush() {
    _flushTimer?.cancel();
    _writes = _writes.then((_) async {
      await initialize();
      try {
        final snapshots = {for (final id in _dirty) if (_records.containsKey(id)) id: _copy(_records[id]!)};
        _dirty.removeAll(snapshots.keys);
        final encoded = useIsolates ? await compute(_encodeRecords, snapshots) : _encodeRecords(snapshots);
        for (final entry in encoded.entries) {
          _sizes[entry.key] = utf8.encode(entry.value).length;
        }
        _prune();
        for (final id in _deleted.toList()) {
          await storage.delete(id);
          _deleted.remove(id);
        }
        for (final entry in encoded.entries) {
          if (_records.containsKey(entry.key)) await storage.put(entry.key, entry.value);
        }
        storageError = null;
      } catch (_) {
        _dirty.addAll(_records.keys);
        storageError = 'diagnostic_write_failed';
      }
      _notify();
    }).catchError((Object _) { storageError = 'diagnostic_write_failed'; });
    return _writes;
  }

  /// Redaction is explicit and best-effort. It never rewrites local evidence.
  Map<String, dynamic> export({required Iterable<String> ids,
    bool maskNames = true, bool deferMasking = false, Iterable<String> additionalNames = const [],
  }) {
    _prune();
    final selected = ids.map((id) => _records[id]).whereType<Map<String, dynamic>>().map(_copy).toList();
    final names = <String>{...additionalNames.where((s) => s.trim().isNotEmpty)};
    for (final value in selected) {
      for (final field in ['person', 'wallet_name', 'title']) {
        final name = (value['parse'] as Map?)?[field];
        if (name is String && name.trim().isNotEmpty) names.add(name);
      }
    }
    final ordered = names.toList()..sort((a, b) => b.length.compareTo(a.length));
    final reviewed = selected.where((r) => r['review']['assessment'] != 'unreviewed' && r['review']['assessment'] != 'unsure').toList();
    final correct = reviewed.where((r) => r['review']['assessment'] == 'correct').length;
    return {
      'schema_version': 1, 'exported_at': clock().toUtc().toIso8601String(),
      'app': {'name': 'Likhlo', 'version': const String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0+1'),
        'build_commit': const String.fromEnvironment('BUILD_COMMIT', defaultValue: 'unknown'),
        'nlp_version': 'english-roman-urdu-3ba06f0', 'diagnostics_version': 1,
        'os': Platform.operatingSystem, 'os_version': Platform.operatingSystemVersion},
      'privacy': {'audio_included': false, 'contains_transcripts': true,
        'name_masking': maskNames ? 'best_effort_review_required' : 'disabled_test_data_only'},
      'retention': {'days': 30, 'max_records': recordLimit, 'max_bytes': byteLimit,
        'evicted_this_session': evictedRecords, 'storage_error': storageError},
      'summary': {'selected': selected.length, 'reviewed_decisive': reviewed.length,
        'correct': correct, 'reviewed_accuracy': reviewed.isEmpty ? null : correct / reviewed.length,
        'review_coverage': selected.isEmpty ? 0.0 : reviewed.length / selected.length},
      if (deferMasking) '_masking_names': ordered,
      if (deferMasking) '_masking_enabled': maskNames,
      'commands': deferMasking || !maskNames ? selected : _maskValues(selected, ordered),
    };
  }

  @override
  void dispose() {
    _disposed = true;
    _flushTimer?.cancel();
    super.dispose();
  }
}

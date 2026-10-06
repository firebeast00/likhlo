import 'dart:async';

/// Pure Dart bridge: parsing and its command-line benchmarks keep working
/// without Flutter, Hive, plugins, or a diagnostics store.
class VoiceDiagnosticObserver {
  static const enabledKey = 'voice_transcript_diagnostics_enabled_v1';
  static const historyKey = 'voice_transcript_diagnostics_has_history_v1';
  static const _zoneKey = #voiceDiagnosticCommand;
  static void Function(String? id, String stage, Map<String, dynamic> data)? sink;
  static bool enabled = false;
  static String? get currentId => Zone.current[_zoneKey] as String?;
  static bool get active => enabled && currentId != null && sink != null;

  static T run<T>(String? id, T Function() action) =>
      runZoned(action, zoneValues: {_zoneKey: id});

  static void stage(String stage, Map<String, dynamic> data) {
    if (!active) return;
    try {
      sink?.call(currentId, stage, data);
    } catch (_) {}
  }
}

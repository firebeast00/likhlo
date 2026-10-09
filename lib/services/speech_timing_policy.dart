import 'dart:async';

/// Endpoint timing shared by Home and Udhaar. Sound levels are only a hint:
/// devices without a useful level range retain the conservative partial wait.
enum SpeechTimingKind { query, transaction, extended }

class SpeechTimingPolicy {
  static const finalGrace = Duration(milliseconds: 100);
  static const resultGrace = Duration(milliseconds: 200);
  static const queryQuiet = Duration(milliseconds: 450);
  static const transactionQuiet = Duration(milliseconds: 850);
  static const extendedQuiet = Duration(milliseconds: 1300);
  static const fallbackQuiet = Duration(seconds: 3);
  static const fallbackQueryQuiet = Duration(milliseconds: 1200);
}

/// Keep accepting result callbacks until native cleanup or its result grace
/// ends. An already final/ended recognizer must not add its cleanup latency to
/// processing; callers separately gate spoken feedback on [cleanup].
Future<void> reconcileSpeechEndpoint({
  required SpeechTimingTracker timing,
  required Future<void> cleanup,
  required Future<void> Function() finalResult,
  required bool Function() isCurrent,
}) async {
  if (timing.recognizerEnded || timing.hasFinalResult) {
    unawaited(cleanup.catchError((Object _) {}));
  } else {
    // A final result can arrive while stop() is still resolving. Keep its
    // correction, then proceed without waiting for the rest of native cleanup.
    await Future.any<void>([cleanup, finalResult()]);
    if (!isCurrent()) return;
    if (!timing.hasFinalResult) timing.recordEnd();
  }
  while (isCurrent() && !timing.hasFinalResult) {
    final remaining = timing.waitFor(
      isComplete: true, kind: SpeechTimingKind.transaction)!;
    if (remaining <= Duration.zero) return;
    var expired = false;
    await finalResult().timeout(remaining, onTimeout: () { expired = true; });
    if (expired) return;
  }
}

class SpeechTimingTracker {
  SpeechTimingTracker({Duration Function()? elapsed}) : _elapsed = elapsed {
    _clock.start();
  }

  final Duration Function()? _elapsed;
  final Stopwatch _clock = Stopwatch();
  final Map<String, int> _marks = {};
  Duration get elapsed => _elapsed?.call() ?? _clock.elapsed;
  String _transcript = '';
  Duration _changedAt = Duration.zero;
  Duration _voiceAt = Duration.zero;
  Duration? _endedAt;
  Duration? _finalAt;
  double? _floor;
  double? _peak;
  int _levelSamples = 0;

  bool get recognizerEnded => _endedAt != null;
  bool get hasFinalResult => _finalAt != null;
  bool get hasUsefulSoundLevels =>
      _levelSamples >= 4 && _floor != null && _peak! - _floor! >= 6;

  void start() {
    _clock.reset();
    _marks.clear();
    startCycle();
    mark('listen_requested');
  }

  void startCycle() {
    _transcript = '';
    _changedAt = elapsed;
    _voiceAt = elapsed;
    _endedAt = null;
    _finalAt = null;
    _floor = null;
    _peak = null;
    _levelSamples = 0;
  }

  void mark(String name) => _marks[name] = elapsed.inMilliseconds;

  /// A repeated partial does not restart the quiet window. A final with the
  /// same words still upgrades the endpoint evidence.
  bool recordTranscript(String text, {required bool isFinal}) {
    final cleaned = text.trim();
    final changed = cleaned.isNotEmpty && cleaned != _transcript;
    if (changed) {
      _transcript = cleaned;
      _changedAt = elapsed;
      if (!isFinal) _finalAt = null;
      mark('last_transcript_change');
    }
    if (isFinal && cleaned.isNotEmpty) {
      _finalAt ??= elapsed;
      mark('final_result_received');
    }
    return changed;
  }

  void recordEnd() {
    _endedAt ??= elapsed;
    mark('recognizer_ended');
  }

  void recordSoundLevel(double level) {
    if (!level.isFinite || recognizerEnded) return;
    _levelSamples++;
    if (_floor == null || level < _floor!) _floor = level;
    if (_peak == null || level > _peak!) _peak = level;
    // A relative threshold avoids treating Android and iOS levels as the
    // same unit. A noisy environment holds the command longer, not shorter.
    if (hasUsefulSoundLevels && level > _floor! + (_peak! - _floor!) * .35) {
      _voiceAt = elapsed;
      mark('last_voice_activity');
    }
  }

  Duration? waitFor({required bool isComplete, required SpeechTimingKind kind}) {
    if (!isComplete && !recognizerEnded && !hasFinalResult) return null;
    if (recognizerEnded) {
      if (hasFinalResult) return Duration.zero;
      final anchor = _changedAt > _endedAt! ? _changedAt : _endedAt!;
      return _remaining(SpeechTimingPolicy.resultGrace, anchor);
    }
    if (hasFinalResult) {
      final anchor = hasUsefulSoundLevels && _voiceAt > _finalAt!
          ? _voiceAt : _finalAt!;
      return _remaining(SpeechTimingPolicy.finalGrace, anchor);
    }
    final window = hasUsefulSoundLevels
        ? switch (kind) {
            SpeechTimingKind.query => SpeechTimingPolicy.queryQuiet,
            SpeechTimingKind.transaction => SpeechTimingPolicy.transactionQuiet,
            SpeechTimingKind.extended => SpeechTimingPolicy.extendedQuiet,
          }
        : kind == SpeechTimingKind.query
            ? SpeechTimingPolicy.fallbackQueryQuiet
            : SpeechTimingPolicy.fallbackQuiet;
    final anchor = hasUsefulSoundLevels && _voiceAt > _changedAt
        ? _voiceAt
        : _changedAt;
    return _remaining(window, anchor);
  }

  Duration _remaining(Duration window, Duration anchor) {
    final remaining = window - (elapsed - anchor);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Map<String, dynamic> get timings => {
        ..._marks,
        'elapsed_ms': elapsed.inMilliseconds,
        'sound_activity_hint_available': hasUsefulSoundLevels,
        'has_final_result': hasFinalResult,
        'recognizer_has_ended': recognizerEnded,
      };
}

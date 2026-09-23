enum SpeechSessionState {
  idle,
  listening,
  finalizing,
  processing,
  completed,
  failed,
}

enum SpeechSessionAction {
  none,
  processFinal,
  retry,
  discardDraft,
}

class SpeechSessionDecision {
  final SpeechSessionAction action;
  final String transcript;

  const SpeechSessionDecision(
    this.action, {
    this.transcript = '',
  });

  static const none = SpeechSessionDecision(SpeechSessionAction.none);
}

/// Keeps speech-recognition lifecycle events separate from financial actions.
///
/// An explicit final result is preferred. Some device recognizers emit only
/// partial callbacks and then end normally, so a normal stop promotes the best
/// available transcript through the same semantic validation pipeline. Error
/// callbacks discard partial text instead of executing or reusing it.
class SpeechSessionController {
  final int maxRetries;

  SpeechSessionState _state = SpeechSessionState.idle;
  String _latestDraft = '';
  String _finalTranscript = '';
  int _retryCount = 0;
  bool _decisionIssued = false;

  SpeechSessionController({this.maxRetries = 1}) : assert(maxRetries >= 0);

  SpeechSessionState get state => _state;
  String get latestDraft => _latestDraft;
  int get retryCount => _retryCount;

  void start() {
    _state = SpeechSessionState.listening;
    _latestDraft = '';
    _finalTranscript = '';
    _retryCount = 0;
    _decisionIssued = false;
  }

  SpeechSessionDecision recordTranscript(
    String transcript, {
    required bool isFinal,
    bool isComplete = true,
  }) {
    if (_decisionIssued ||
        (_state != SpeechSessionState.listening &&
            _state != SpeechSessionState.finalizing)) {
      return SpeechSessionDecision.none;
    }

    final normalized = _normalizeSpeech(transcript);
    if (normalized.isNotEmpty) {
      // Device recognizers normally send cumulative partials. Replacing the
      // draft avoids duplicated amounts/titles when a partial is corrected.
      _latestDraft = normalized;
    }
    if (!isFinal) return SpeechSessionDecision.none;

    if (normalized.isEmpty) {
      _state = SpeechSessionState.failed;
      _decisionIssued = true;
      return _discardDecision();
    }

    if (!isComplete) return _retryOrFail(retryWhenEmpty: false);

    _finalTranscript = _latestDraft;
    _state = SpeechSessionState.finalizing;
    return _emitFinal();
  }

  SpeechSessionDecision onRecognizerStopped({
    bool isComplete = true,
    bool retryWhenEmpty = false,
  }) {
    if (_decisionIssued) return SpeechSessionDecision.none;
    if (_state != SpeechSessionState.listening &&
        _state != SpeechSessionState.finalizing) {
      return SpeechSessionDecision.none;
    }
    if (_finalTranscript.isNotEmpty) return _emitFinal();
    if (!isComplete) {
      return _retryOrFail(retryWhenEmpty: retryWhenEmpty);
    }
    if (_latestDraft.isNotEmpty) {
      _finalTranscript = _latestDraft;
      _state = SpeechSessionState.finalizing;
      return _emitFinal();
    }

    _state = SpeechSessionState.failed;
    _decisionIssued = true;
    return _discardDecision();
  }

  SpeechSessionDecision onRecognizerError({required bool retryable}) {
    if (_decisionIssued) return SpeechSessionDecision.none;
    if (_state != SpeechSessionState.listening &&
        _state != SpeechSessionState.finalizing) {
      return SpeechSessionDecision.none;
    }
    if (_finalTranscript.isNotEmpty) return _emitFinal();

    if (retryable) return _retryOrFail(retryWhenEmpty: true);

    _state = SpeechSessionState.failed;
    _decisionIssued = true;
    return _discardDecision();
  }

  SpeechSessionDecision onStableTranscript({required bool isComplete}) {
    if (_decisionIssued ||
        (_state != SpeechSessionState.listening &&
            _state != SpeechSessionState.finalizing)) {
      return SpeechSessionDecision.none;
    }
    if (!isComplete || _latestDraft.isEmpty) {
      return SpeechSessionDecision.none;
    }

    _finalTranscript = _latestDraft;
    _state = SpeechSessionState.finalizing;
    return _emitFinal();
  }

  SpeechSessionDecision onSessionExpired({required bool isComplete}) {
    if (_decisionIssued ||
        (_state != SpeechSessionState.listening &&
            _state != SpeechSessionState.finalizing)) {
      return SpeechSessionDecision.none;
    }
    if (isComplete && _latestDraft.isNotEmpty) {
      _finalTranscript = _latestDraft;
      _state = SpeechSessionState.finalizing;
      return _emitFinal();
    }

    _state = SpeechSessionState.failed;
    _decisionIssued = true;
    return _discardDecision();
  }

  void markProcessing() {
    if (_state == SpeechSessionState.finalizing) {
      _state = SpeechSessionState.processing;
    }
  }

  void markCompleted() {
    if (_state == SpeechSessionState.processing) {
      _state = SpeechSessionState.completed;
    }
  }

  void markFailed() {
    _state = SpeechSessionState.failed;
    _decisionIssued = true;
  }

  void reset() {
    _state = SpeechSessionState.idle;
    _latestDraft = '';
    _finalTranscript = '';
    _retryCount = 0;
    _decisionIssued = false;
  }

  SpeechSessionDecision _emitFinal() {
    _decisionIssued = true;
    return SpeechSessionDecision(
      SpeechSessionAction.processFinal,
      transcript: _finalTranscript,
    );
  }

  SpeechSessionDecision _retryOrFail({required bool retryWhenEmpty}) {
    final canRetry = (_latestDraft.isNotEmpty || retryWhenEmpty) &&
        _retryCount < maxRetries;
    if (canRetry) {
      _retryCount++;
      _state = SpeechSessionState.listening;
      _latestDraft = '';
      _finalTranscript = '';
      return const SpeechSessionDecision(SpeechSessionAction.retry);
    }

    _state = SpeechSessionState.failed;
    _decisionIssued = true;
    return _discardDecision();
  }

  SpeechSessionDecision _discardDecision() {
    if (_latestDraft.isEmpty) return SpeechSessionDecision.none;
    return SpeechSessionDecision(
      SpeechSessionAction.discardDraft,
      transcript: _latestDraft,
    );
  }
}

String _normalizeSpeech(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ');
}

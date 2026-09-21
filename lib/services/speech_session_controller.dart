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
  preserveDraft,
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
/// Only an explicit final recognition result may produce [processFinal]. A
/// recognizer timeout, error, or stopped status can preserve a partial draft,
/// but can never promote that draft into an executable command.
class SpeechSessionController {
  final int maxRetries;

  SpeechSessionState _state = SpeechSessionState.idle;
  String _latestDraft = '';
  String _finalTranscript = '';
  int _retryCount = 0;
  bool _decisionIssued = false;

  SpeechSessionController({this.maxRetries = 1})
      : assert(maxRetries >= 0);

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
  }) {
    if (_decisionIssued ||
        (_state != SpeechSessionState.listening &&
            _state != SpeechSessionState.finalizing)) {
      return SpeechSessionDecision.none;
    }

    final normalized = transcript.trim();
    if (normalized.isNotEmpty) _latestDraft = normalized;
    if (!isFinal) return SpeechSessionDecision.none;

    if (normalized.isEmpty) {
      _state = SpeechSessionState.failed;
      _decisionIssued = true;
      return _draftDecision();
    }

    _finalTranscript = normalized;
    _state = SpeechSessionState.finalizing;
    return _emitFinal();
  }

  SpeechSessionDecision onRecognizerStopped() {
    if (_decisionIssued) return SpeechSessionDecision.none;
    if (_state != SpeechSessionState.listening &&
        _state != SpeechSessionState.finalizing) {
      return SpeechSessionDecision.none;
    }
    if (_finalTranscript.isNotEmpty) return _emitFinal();

    _state = SpeechSessionState.failed;
    _decisionIssued = true;
    return _draftDecision();
  }

  SpeechSessionDecision onRecognizerError({required bool retryable}) {
    if (_decisionIssued) return SpeechSessionDecision.none;
    if (_state != SpeechSessionState.listening &&
        _state != SpeechSessionState.finalizing) {
      return SpeechSessionDecision.none;
    }
    if (_finalTranscript.isNotEmpty) return _emitFinal();

    if (retryable && _retryCount < maxRetries) {
      _retryCount++;
      _state = SpeechSessionState.listening;
      _finalTranscript = '';
      return SpeechSessionDecision(
        SpeechSessionAction.retry,
        transcript: _latestDraft,
      );
    }

    _state = SpeechSessionState.failed;
    _decisionIssued = true;
    return _draftDecision();
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

  SpeechSessionDecision _draftDecision() {
    if (_latestDraft.isEmpty) return SpeechSessionDecision.none;
    return SpeechSessionDecision(
      SpeechSessionAction.preserveDraft,
      transcript: _latestDraft,
    );
  }
}

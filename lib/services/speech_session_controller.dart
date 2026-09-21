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
/// An explicit final result is preferred, but recognizer completion is not
/// treated as command completion. Incomplete segments are retained and joined
/// across a bounded number of listening cycles. Error callbacks preserve
/// partial text instead of executing it.
class SpeechSessionController {
  final int maxRetries;

  SpeechSessionState _state = SpeechSessionState.idle;
  String _committedTranscript = '';
  String _segmentTranscript = '';
  String _latestDraft = '';
  String _finalTranscript = '';
  int _retryCount = 0;
  bool _decisionIssued = false;

  SpeechSessionController({this.maxRetries = 1})
      : assert(maxRetries >= 0);

  SpeechSessionState get state => _state;
  String get latestDraft => _latestDraft;
  int get retryCount => _retryCount;

  String transcriptWithSegment(String transcript) =>
      mergeSpeechTranscripts(_committedTranscript, transcript);

  void start({String initialTranscript = ''}) {
    final initialDraft = initialTranscript.trim();
    _state = SpeechSessionState.listening;
    _committedTranscript = initialDraft;
    _segmentTranscript = '';
    _latestDraft = initialDraft;
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

    final normalized = transcript.trim();
    if (normalized.isNotEmpty) {
      _segmentTranscript = normalized;
      _latestDraft = mergeSpeechTranscripts(
        _committedTranscript,
        _segmentTranscript,
      );
    }
    if (!isFinal) return SpeechSessionDecision.none;

    if (_latestDraft.isEmpty) return _failWithDraft();
    if (!isComplete) return _continueOrPreserve();

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
    if (_finalTranscript.isNotEmpty && isComplete) return _emitFinal();
    if (_latestDraft.isNotEmpty && isComplete) {
      _finalTranscript = _latestDraft;
      _state = SpeechSessionState.finalizing;
      return _emitFinal();
    }
    if (_latestDraft.isNotEmpty || retryWhenEmpty) {
      return _continueOrPreserve();
    }

    return _failWithDraft();
  }

  /// Finalizes a command as soon as its meaning is complete and the partial
  /// transcript has remained stable for the UI's short debounce period.
  SpeechSessionDecision onStableTranscript({required bool isComplete}) {
    if (_decisionIssued || _state != SpeechSessionState.listening) {
      return SpeechSessionDecision.none;
    }
    if (!isComplete || _latestDraft.isEmpty) {
      return SpeechSessionDecision.none;
    }
    _finalTranscript = _latestDraft;
    _state = SpeechSessionState.finalizing;
    return _emitFinal();
  }

  /// Ends the whole voice session without starting another recognizer cycle.
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
    return _failWithDraft();
  }

  SpeechSessionDecision onRecognizerError({required bool retryable}) {
    if (_decisionIssued) return SpeechSessionDecision.none;
    if (_state != SpeechSessionState.listening &&
        _state != SpeechSessionState.finalizing) {
      return SpeechSessionDecision.none;
    }
    if (_finalTranscript.isNotEmpty) return _emitFinal();

    if (retryable && _retryCount < maxRetries) {
      return _continueListening();
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
    _committedTranscript = '';
    _segmentTranscript = '';
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

  SpeechSessionDecision _continueOrPreserve() {
    if (_retryCount < maxRetries) return _continueListening();
    return _failWithDraft();
  }

  SpeechSessionDecision _continueListening() {
    _retryCount++;
    _committedTranscript = _latestDraft;
    _segmentTranscript = '';
    _finalTranscript = '';
    _state = SpeechSessionState.listening;
    return SpeechSessionDecision(
      SpeechSessionAction.retry,
      transcript: _latestDraft,
    );
  }

  SpeechSessionDecision _failWithDraft() {
    _state = SpeechSessionState.failed;
    _decisionIssued = true;
    return _draftDecision();
  }
}

/// Joins recognizer segments while removing the repeated words Android often
/// includes at the boundary of a restarted listening cycle.
String mergeSpeechTranscripts(String previous, String next) {
  final left = previous.trim();
  final right = next.trim();
  if (left.isEmpty) return right;
  if (right.isEmpty) return left;

  final leftWords = left.split(RegExp(r'\s+'));
  final rightWords = right.split(RegExp(r'\s+'));
  final maximumOverlap = leftWords.length < rightWords.length
      ? leftWords.length
      : rightWords.length;
  var overlap = 0;
  for (var size = maximumOverlap; size > 0; size--) {
    var matches = true;
    for (var index = 0; index < size; index++) {
      final leftWord = leftWords[leftWords.length - size + index];
      final rightWord = rightWords[index];
      if (leftWord.toLowerCase() != rightWord.toLowerCase()) {
        matches = false;
        break;
      }
    }
    if (matches) {
      overlap = size;
      break;
    }
  }

  return [...leftWords, ...rightWords.skip(overlap)].join(' ');
}

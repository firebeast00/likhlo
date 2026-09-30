part of '../../screens/home_screen.dart';

extension _DashboardVoiceMethods on _HomeScreenState {
  Future<void> _listenForExpense() async {
    _dismissKeyboard();
    if (_isProcessingVoiceCommand) {
      _showTransactionInfo(
        'Your previous voice command is still being processed.',
        title: 'Please wait',
      );
      return;
    }
    if (_isListening) {
      await _finishSpeechSession(manual: true);
      unawaited(HapticFeedback.selectionClick());
      return;
    }

    _cancelSpeechTimers();
    _voiceEntry.session.reset();
    _handlingSpeechError = false;
    _restartingSpeech = false;
    _finalizingRecognizerStop = false;
    if (!_speechInitialized) {
      final available = await _voiceEntry.speech.initialize(
        onStatus: _handleSpeechStatus,
        onError: (error) => _handleSpeechError(error.message),
      );
      if (!mounted) return;
      if (!available) {
        _showTransactionError(
          'Speech recognition is not available. Enable the Google app or your phone\'s speech-recognition service, then allow microphone access.',
          title: 'Voice recognition unavailable',
        );
        return;
      }
      _speechInitialized = true;
    }

    final language = ref.read(settingsProvider).smartEntryLanguage;
    if (!_speechLocalesLoaded || _speechLocaleLanguage != language) {
      _speechLocaleCandidates = await _buildSpeechLocaleCandidates();
      _speechLocalesLoaded = true;
      _speechLocaleLanguage = language;
    }
    _speechLocaleCandidateIndex = 0;
    if (!mounted) return;

    _smartInputCtrl.clear();
    _voiceEntry.session.start();
    _speechDeadlineTimer = Timer(
      VoiceEntryController.sessionLimit,
          () => unawaited(_finishSpeechSession()),
    );
    setState(() => _isListening = true);
    unawaited(HapticFeedback.mediumImpact());
    await _startSpeechListening();
  }

  Future<List<String?>> _buildSpeechLocaleCandidates() async {
    final candidates = <String?>[];
    try {
      final locales = await _voiceEntry.speech.locales();
      final systemLocale = await _voiceEntry.speech.systemLocale();

      String normalize(String value) =>
          value.toLowerCase().replaceAll('-', '_');
      final added = <String>{};

      void addLocale(String? localeId) {
        if (localeId == null || localeId.trim().isEmpty) return;
        final normalized = normalize(localeId);
        if (added.add(normalized)) candidates.add(localeId);
      }

      final preferred = ref.read(settingsProvider).smartEntryLanguage == 'romanUrdu'
          ? ['ur_pk', 'ur', 'ur_in', 'en_pk', 'en_in']
          : ['en_pk', 'en_in', 'en_gb', 'en_us'];
      for (final preferredId in preferred) {
        for (final locale in locales) {
          if (normalize(locale.localeId) == preferredId) {
            addLocale(locale.localeId);
          }
        }
      }
      final systemId = systemLocale?.localeId;
      if (systemId != null && normalize(systemId).startsWith('en_')) {
        addLocale(systemId);
      }
      for (final locale in locales) {
        if (normalize(locale.localeId).startsWith('en_')) {
          addLocale(locale.localeId);
        }
      }
    } catch (error) {
      debugPrint('Speech locale lookup failed: $error');
    }

    candidates.add(null);
    return candidates.take(4).toList(growable: false);
  }

  Future<void> _startSpeechListening() async {
    if (!mounted) return;
    final localeId =
    _speechLocaleCandidates[_speechLocaleCandidateIndex];
    _recognizerReportedListening = false;
    _speechListenStartedAt = DateTime.now();
    _speechStartupTimer?.cancel();
    _speechStartupTimer = Timer(
      VoiceEntryController.startupGrace,
          () => unawaited(_handleSpeechStartupTimeout()),
    );

    try {
      await _voiceEntry.speech.listen(
        options: SpeechRecognitionListenOptions(
          localeId: localeId,
          partialResults: true,
          pauseFor: VoiceEntryController.pauseWindow,
          listenFor: VoiceEntryController.sessionLimit,
        ),
        onResult: (result) async {
          if (!mounted) return;
          if (_voiceEntry.session.state != SpeechSessionState.listening &&
              _voiceEntry.session.state != SpeechSessionState.finalizing) {
            return;
          }
          _markRecognizerActive();
          final words = result.text.trim();
          final completeness = _speechCompleteness(words);
          final decision = _voiceEntry.session.recordTranscript(
            words,
            // Some recognizers finalize a phrase during a pause. Let the
            // inactivity window decide when the full command has ended.
            isFinal: false,
            isComplete: completeness.isComplete,
          );
          final combinedWords = _voiceEntry.session.latestDraft;
          if (combinedWords.isNotEmpty) {
            _smartInputCtrl.value = TextEditingValue(
              text: combinedWords,
              selection: TextSelection.collapsed(
                offset: combinedWords.length,
              ),
            );
          }
          _traceSpeechEvent(
            result.isFinal ? 'result_final' : 'result_partial',
            transcript: combinedWords,
            completeness: completeness,
          );
          _scheduleStableSpeechFinalization(
            combinedWords,
            completeness,
            isFinal: result.isFinal,
          );
          await _applySpeechDecision(decision);
        },
      );
    } catch (error) {
      debugPrint('Speech listen failed: $error');
      if (!mounted || _handlingSpeechError) return;
      _handlingSpeechError = true;
      _voiceEntry.session.onRecognizerError(retryable: false);
      _cancelSpeechTimers();
      _smartInputCtrl.clear();
      setState(() => _isListening = false);
      _showTransactionError(
        'Voice recognition could not start. Check microphone permission and the phone\'s speech-recognition service.',
        title: 'Voice Log unavailable',
      );
    }
  }

  Iterable<SmartEntryAccount> _parsingAccounts() =>
      ref.read(walletProvider).map((wallet) => SmartEntryAccount(
        id: wallet.id,
        name: wallet.name,
        type: wallet.walletType,
        availableBalance: 0,
        isBackup: wallet.isBackup,
      ));

  SpeechCommandCompleteness _speechCompleteness(String transcript) {
    final normalized = transcript.trim();
    if (normalized.isEmpty) {
      return const SpeechCommandCompleteness.incomplete('empty_transcript');
    }
    try {
      final plan = ref.read(smartEntryControllerProvider).parse(
        normalized,
        ref.read(categoryProvider),
        source: SmartInputSource.voice,
        accounts: _parsingAccounts(),
      );
      final accounts = ref
          .read(walletProvider)
          .map(
            (wallet) => SmartEntryAccount(
          id: wallet.id,
          name: wallet.name,
          type: wallet.walletType,
          availableBalance: 0,
          isBackup: wallet.isBackup,
        ),
      )
          .toList(growable: false);
      return _voiceEntry.completeness.evaluate(
        plan,
        accounts: accounts,
      );
    } catch (error) {
      debugPrint('Speech completeness check failed: $error');
      return const SpeechCommandCompleteness.incomplete('parse_failed');
    }
  }

  void _scheduleStableSpeechFinalization(
    String transcript,
    SpeechCommandCompleteness completeness, {
    required bool isFinal,
  }) {
    if (transcript.isEmpty) {
      _speechStabilityTimer?.cancel();
      _speechStabilityTimer = null;
      _speechStableTranscript = '';
      _speechStableReason = '';
      return;
    }

    if (_speechStableTranscript == transcript &&
        _speechStableReason == completeness.reason &&
        (_speechStabilityTimer?.isActive ?? false)) {
      return;
    }

    _speechStabilityTimer?.cancel();
    _speechStableTranscript = transcript;
    _speechStableReason = completeness.reason;

    final fastReadOnly = completeness.isComplete &&
        const {
          'query_metric',
          'navigation_target',
          'app_control',
        }.contains(completeness.reason);
    final window = fastReadOnly
        ? VoiceEntryController.readOnlyStabilityWindow
        : VoiceEntryController.stabilityWindow;

    final stableTranscript = transcript;
    _speechStabilityTimer = Timer(window, () async {
      if (!mounted ||
          _restartingSpeech ||
          _voiceEntry.session.state != SpeechSessionState.listening ||
          _voiceEntry.session.latestDraft != stableTranscript) {
        return;
      }
      final currentCompleteness = _speechCompleteness(stableTranscript);
      final decision = _voiceEntry.session.onSessionExpired(
        isComplete: currentCompleteness.isComplete,
      );
      _traceSpeechEvent(
        'stable',
        transcript: stableTranscript,
        completeness: currentCompleteness,
      );
      _speechStableTranscript = '';
      _speechStableReason = '';
      if (decision.action != SpeechSessionAction.none) {
        await _stopRecognizerThenApply(decision);
      }
    });
  }

  Future<void> _finishSpeechSession({bool manual = false}) async {
    if (!mounted) return;
    final transcript = _voiceEntry.session.latestDraft;
    final completeness = _speechCompleteness(transcript);
    final decision = completeness.isComplete && transcript.isNotEmpty
        ? _voiceEntry.session.recordTranscript(transcript, isFinal: true)
        : _voiceEntry.session.onRecognizerError(retryable: false);
    _traceSpeechEvent(
      manual ? 'manual_stop' : 'session_deadline',
      transcript: transcript,
      completeness: completeness,
    );
    if (decision.action == SpeechSessionAction.none &&
        _voiceEntry.session.state != SpeechSessionState.failed) {
      return;
    }
    await _stopRecognizerThenApply(decision);
  }

  Future<void> _stopRecognizerThenApply(
      SpeechSessionDecision decision,
      ) async {
    _cancelSpeechTimers();
    _restartingSpeech = true;
    try {
      await _voiceEntry.speech.stop();
    } finally {
      _restartingSpeech = false;
    }
    if (!mounted) return;
    if (_isListening) setState(() => _isListening = false);
    await _applySpeechDecision(decision);
  }

  Future<void> _restartSpeechListening({bool advanceLocale = false}) async {
    if (!mounted || _restartingSpeech) return;
    _speechStabilityTimer?.cancel();
    _speechStartupTimer?.cancel();
    _restartingSpeech = true;
    try {
      await _voiceEntry.speech.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      if (advanceLocale &&
          _speechLocaleCandidateIndex + 1 <
              _speechLocaleCandidates.length) {
        _speechLocaleCandidateIndex++;
      }
    } finally {
      _restartingSpeech = false;
    }
    if (!mounted) return;
    _handlingSpeechError = false;
    if (!_isListening) setState(() => _isListening = true);
    _traceSpeechEvent(
      'restart',
      transcript: _voiceEntry.session.latestDraft,
      completeness: _speechCompleteness(_voiceEntry.session.latestDraft),
    );
    await _startSpeechListening();
  }

  void _cancelSpeechTimers() {
    _speechStabilityTimer?.cancel();
    _speechStabilityTimer = null;
    _speechStableTranscript = '';
    _speechStableReason = '';
    _speechDeadlineTimer?.cancel();
    _speechDeadlineTimer = null;
    _speechStartupTimer?.cancel();
    _speechStartupTimer = null;
  }

  void _markRecognizerActive() {
    _recognizerReportedListening = true;
    _speechStartupTimer?.cancel();
    _speechStartupTimer = null;
  }

  Future<void> _handleSpeechStartupTimeout() async {
    if (!mounted ||
        _restartingSpeech ||
        _recognizerReportedListening ||
        _voiceEntry.session.state != SpeechSessionState.listening) {
      return;
    }
    final transcript = _voiceEntry.session.latestDraft;
    final completeness = _speechCompleteness(transcript);
    final decision = completeness.isComplete && transcript.isNotEmpty
        ? _voiceEntry.session.recordTranscript(transcript, isFinal: true)
        : _voiceEntry.session.onRecognizerError(retryable: true);
    _traceSpeechEvent(
      'startup_timeout',
      transcript: transcript,
      completeness: completeness,
    );
    await _applySpeechDecision(decision);
  }

  void _traceSpeechEvent(
      String event, {
        required String transcript,
        required SpeechCommandCompleteness completeness,
      }) {
    assert(() {
      debugPrint(
        '[Voice session] time=${DateTime.now().toIso8601String()} '
            'event=$event state=${_voiceEntry.session.state.name} '
            'retry=${_voiceEntry.session.retryCount} '
            'complete=${completeness.isComplete} '
            'reason=${completeness.reason} transcript="$transcript"',
      );
      return true;
    }());
  }

  Future<void> _handleSpeechError(String errorMessage) async {
    if (!mounted || _handlingSpeechError) return;
    if (_voiceEntry.session.state != SpeechSessionState.listening &&
        _voiceEntry.session.state != SpeechSessionState.finalizing) {
      return;
    }
    debugPrint('STT Error: $errorMessage');
    _handlingSpeechError = true;

    final normalized = errorMessage.toLowerCase();
    final recoverableEnd = normalized.contains('error_speech_timeout') ||
        normalized.contains('error_no_match') ||
        normalized.contains('error_client');
    final languageFailure =
        normalized.contains('error_language_unavailable') ||
            normalized.contains('error_language_not_supported');
    final canTryAnotherLocale = languageFailure &&
        _speechLocaleCandidateIndex + 1 < _speechLocaleCandidates.length;
    final decision = _voiceEntry.session.onRecognizerError(
      retryable: recoverableEnd || canTryAnotherLocale,
    );

    if (decision.action == SpeechSessionAction.retry) {
      _smartInputCtrl.clear();
      await _restartSpeechListening(advanceLocale: canTryAnotherLocale);
      return;
    }

    _cancelSpeechTimers();
    setState(() => _isListening = false);

    if (decision.action == SpeechSessionAction.processFinal) {
      await _applySpeechDecision(decision);
      return;
    }

    _smartInputCtrl.clear();

    if (normalized.contains('error_client')) {
      _speechInitialized = false;
    }

    final networkFailure =
        normalized.contains('error_network') ||
            normalized.contains('error_server') ||
            normalized.contains('error_too_many_requests');

    if (networkFailure) {
      _showTransactionError(
        'Voice recognition needs an internet connection on this phone. Connect to the internet or install an offline English language in Google voice typing. Typed Smart Entry still works.',
        title: 'Voice service is offline',
      );
      return;
    }

    if (languageFailure) {
      _showTransactionError(
        'No working speech language was found. Enable the Google app, select English in Google voice typing, and download its offline language pack.',
        title: 'Speech language unavailable',
      );
      return;
    }

    _showTransactionError(
      'Voice Log stopped before it received a final result. Please say the full command again.',
      title: 'Voice Log stopped',
    );
  }

  Future<void> _applySpeechDecision(SpeechSessionDecision decision) async {
    if (!mounted) return;
    switch (decision.action) {
      case SpeechSessionAction.processFinal:
        if (_isProcessingVoiceCommand) return;
        _cancelSpeechTimers();
        setState(() => _isListening = false);
        _voiceEntry.session.markProcessing();
        _isProcessingVoiceCommand = true;
        try {
          await _processNLP(
            decision.transcript,
            source: SmartInputSource.voice,
          );
          _voiceEntry.session.markCompleted();
          _smartInputCtrl.clear();
          _voiceEntry.session.reset();
        } catch (error) {
          _voiceEntry.session.markFailed();
          _smartInputCtrl.clear();
          rethrow;
        } finally {
          _isProcessingVoiceCommand = false;
        }
        return;
      case SpeechSessionAction.discardDraft:
        _cancelSpeechTimers();
        setState(() => _isListening = false);
        _smartInputCtrl.clear();
        _voiceEntry.session.reset();
        _showTransactionError(
          'The voice command was incomplete. Please tap the microphone and say the full command again.',
          title: 'Voice command incomplete',
        );
        return;
      case SpeechSessionAction.none:
        if (_voiceEntry.session.state == SpeechSessionState.failed) {
          _cancelSpeechTimers();
          if (_isListening) setState(() => _isListening = false);
          _smartInputCtrl.clear();
          _voiceEntry.session.reset();
          _showTransactionError(
            'Voice recognition stopped before hearing any words. Tap the microphone and try again.',
            title: 'Voice stopped too soon',
          );
        }
        return;
      case SpeechSessionAction.retry:
        _smartInputCtrl.clear();
        await _restartSpeechListening();
        return;
    }
  }

  void _handleSpeechStatus(String status) {
    if (!mounted) return;
    if (status == 'listening') {
      _markRecognizerActive();
      return;
    }
    if (status != 'done' && status != 'notListening') return;
    if (_restartingSpeech) return;
    final startedAt = _speechListenStartedAt;
    final elapsed = startedAt == null
        ? null
        : DateTime.now().difference(startedAt);
    if (!_recognizerReportedListening &&
        elapsed != null &&
        elapsed < VoiceEntryController.prematureStatusGuard) {
      // Android may emit a stale `notListening` status while a new listen call
      // is still starting. The startup timer will retry if no real listening
      // status or transcript arrives.
      return;
    }
    _speechStartupTimer?.cancel();
    _speechStartupTimer = null;
    unawaited(_finalizeNormallyStoppedSpeech());
  }

  Future<void> _finalizeNormallyStoppedSpeech() async {
    // Several Android recognizers report `done` just before delivering their
    // final callback. Give it a chance to arrive. An incomplete transcript is
    // continued in a fresh recognizer cycle rather than promoted to a command.
    if (_finalizingRecognizerStop) return;
    _finalizingRecognizerStop = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!mounted || _restartingSpeech) return;
      final transcript = _voiceEntry.session.latestDraft;
      final completeness = _speechCompleteness(transcript);
      if (transcript.isNotEmpty) {
        _scheduleStableSpeechFinalization(
          transcript,
          completeness,
          isFinal: false,
        );
        return;
      }
      final decision = _voiceEntry.session.onRecognizerError(retryable: true);
      _traceSpeechEvent(
        'recognizer_stopped',
        transcript: transcript,
        completeness: completeness,
      );
      await _applySpeechDecision(decision);
    } finally {
      _finalizingRecognizerStop = false;
    }
  }


}

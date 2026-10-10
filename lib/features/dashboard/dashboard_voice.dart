part of '../../screens/home_screen.dart';

extension _DashboardVoiceMethods on _HomeScreenState {
  Future<void> _listenForExpense({String entryPoint = 'home_microphone'}) async {
    if (_voiceStarting || _recognizerCleanupPending) return;
    _voiceStarting = true;
    if (mounted) _smartInputUiRevision.value++;
    try {
      await _listenForExpenseImpl(entryPoint: entryPoint);
    } catch (error) {
      VoiceDiagnosticsService.instance.finish(_voiceDiagnosticId, 'failed', reason: 'voice_${error.runtimeType}');
      rethrow;
    } finally {
      _voiceStarting = false;
      if (mounted) _smartInputUiRevision.value++;
    }
  }

  Future<void> _listenForExpenseImpl({required String entryPoint}) async {
    _dismissKeyboard();
    if (_isProcessingVoiceCommand || _finalizingRecognizerStop) {
      _showTransactionInfo(
        AppMessage('your_previous_voice_command_is_still_being_proce_4be015'),
        title: AppMessage('please_wait_ee9e88'),
      );
      return;
    }
    if (_isListening) {
      await _finishSpeechSession(manual: true);
      unawaited(HapticFeedback.selectionClick());
      return;
    }

    await AudioFeedbackService().stop();
    if (!mounted) return;
    VoiceDiagnosticsService.instance.finish(_voiceDiagnosticId, 'interrupted', reason: 'new_attempt');
    _voiceDiagnosticId = VoiceDiagnosticsService.instance.begin(entryPoint: entryPoint, context: {
      'app_language': AppLanguage.read().name,
      'nlp_language': ref.read(settingsProvider).smartEntryLanguage,
      'provider': _voiceEntry.speech.id,
      'time_zone': DateTime.now().timeZoneName,
      'utc_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
    });
    _cancelSpeechTimers();
    _voiceEntry.session.reset();
    _speechNetworkRecovery.reset();
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
        VoiceDiagnosticsService.instance.finish(_voiceDiagnosticId, 'failed', reason: 'recognizer_unavailable');
        _showTransactionError(
          AppMessage('speech_recognition_is_not_available_enable_the_g_17bd68'),
          title: AppMessage('voice_recognition_unavailable_1fa909'),
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
    _speechTiming.start();
    _speechCacheKey = null;
    _speechDeadlineTimer = Timer(
      VoiceEntryController.sessionLimit,
          () => unawaited(_finishSpeechSession(deadline: true)),
    );
    _setListening(true);
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
    final attempt = ++_speechAttempt;
    _speechTiming.startCycle();
    _speechFinalResult = Completer<void>();
    final localeId =
    _speechLocaleCandidates[_speechLocaleCandidateIndex];
    VoiceDiagnosticsService.instance.event(_voiceDiagnosticId, 'recognizer_cycle', {
      'cycle': attempt, 'locale_requested': localeId,
      'on_device_requested': _speechNetworkRecovery.onDevice,
      'provider': _voiceEntry.speech.id,
    });
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
          onDevice: _speechNetworkRecovery.onDevice,
          pauseFor: VoiceEntryController.pauseWindow,
          listenFor: VoiceEntryController.sessionLimit,
        ),
        onSoundLevelChange: (level) {
          if (mounted && attempt == _speechAttempt && !_finalizingRecognizerStop) {
            _speechTiming.recordSoundLevel(level);
          }
        },
        onResult: (result) async {
          if (!mounted || attempt != _speechAttempt) return;
          if (_voiceEntry.session.state != SpeechSessionState.listening &&
              _voiceEntry.session.state != SpeechSessionState.finalizing) {
            return;
          }
          _markRecognizerActive();
          VoiceDiagnosticsService.instance.event(_voiceDiagnosticId, 'recognition', {
            'text': result.text, 'is_final': result.isFinal, 'provider': result.provider,
            'confidence': result.confidence, 'stability': result.stability,
            'detected_language': result.detectedLanguage, 'cycle': attempt,
          });
          final words = result.text.trim();
          final hadFinal = _speechTiming.hasFinalResult;
          final changed = _speechTiming.recordTranscript(words, isFinal: result.isFinal);
          if (changed && hadFinal && !result.isFinal) {
            _speechFinalResult = Completer<void>();
          }
          if (result.isFinal && words.isNotEmpty &&
              !(_speechFinalResult?.isCompleted ?? true)) {
            _speechFinalResult!.complete();
          }
          final completeness = _speechCompleteness(words);
          final decision = _voiceEntry.session.recordTranscript(
            words,
            // Retain the draft until the endpoint policy accepts it. The
            // actual final flag is tracked above and bypasses the long timer.
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
          _scheduleStableSpeechFinalization(completeness);
          await _applySpeechDecision(decision);
        },
      );
    } catch (error) {
      VoiceDiagnosticsService.instance.event(_voiceDiagnosticId, 'recognizer_error', {'error_type': error.runtimeType.toString(), 'phase': 'listen'});
      VoiceDiagnosticsService.instance.finish(_voiceDiagnosticId, 'failed', reason: 'listen_failed');
      debugPrint('Speech listen failed: $error');
      if (!mounted || _handlingSpeechError) return;
      _handlingSpeechError = true;
      _voiceEntry.session.onRecognizerError(retryable: false);
      _cancelSpeechTimers();
      _smartInputCtrl.clear();
      _setListening(false);
      _showTransactionError(
        AppMessage('voice_recognition_could_not_start_check_micropho_db2292'),
        title: AppMessage('voice_log_unavailable_9d7ecf'),
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

  String _speechContextKey(String text) {
    final now = DateTime.now();
    return '$text|${now.year}-${now.month}-${now.day}|'
        '${ref.read(categoryProvider).join('\u0000')}|'
        '${ref.read(walletProvider).map((w) => '${w.id}:${w.name}:${w.walletType}:${w.isBackup}').join('\u0000')}';
  }

  SpeechCommandCompleteness _speechCompleteness(String transcript) {
    final normalized = transcript.trim();
    if (normalized.isEmpty) {
      return const SpeechCommandCompleteness.incomplete('empty_transcript');
    }
    final key = _speechContextKey(normalized);
    if (key == _speechCacheKey && _speechCachedCompleteness != null) {
      return _speechCachedCompleteness!;
    }
    try {
      _speechTiming.mark('parse_started');
      final accounts = _parsingAccounts().toList(growable: false);
      final plan = ref.read(smartEntryControllerProvider).parse(
        normalized, ref.read(categoryProvider),
        source: SmartInputSource.voice, accounts: accounts,
        enableHomeExpenseCategories: true,
      );
      final result = plan.expenseCategory?.needsClarification == true
          ? const SpeechCommandCompleteness.incomplete('category_instruction_incomplete')
          : _voiceEntry.completeness.evaluate(plan, accounts: accounts);
      _speechCachedCompleteness = result;
      _speechCacheKey = key;
      _speechTiming.mark('parse_completed');
      return result;
    } catch (error) {
      debugPrint('Speech completeness check failed: $error');
      _speechCacheKey = null;
      return const SpeechCommandCompleteness.incomplete('parse_failed');
    }
  }

  SpeechTimingKind _speechTimingKind(SpeechCommandCompleteness completeness) {
    if (const {'query_metric', 'navigation_target', 'app_control', 'search_subject'}
        .contains(completeness.reason)) return SpeechTimingKind.query;
    if (completeness.reason.startsWith('transfer') ||
        RegExp(r'\b(and|aur|phir|then)\b').hasMatch(
            _voiceEntry.session.latestDraft.toLowerCase())) {
      return SpeechTimingKind.extended;
    }
    return SpeechTimingKind.transaction;
  }

  void _scheduleStableSpeechFinalization(SpeechCommandCompleteness completeness) {
    _speechStabilityTimer?.cancel();
    if (_finalizingRecognizerStop || _isProcessingVoiceCommand) return;
    final wait = _speechTiming.waitFor(
        isComplete: completeness.isComplete,
        kind: _speechTimingKind(completeness));
    // An incomplete active phrase is not a session deadline. Keep its draft
    // and the real deadline timer, allowing the user to continue speaking.
    if (wait == null) return;
    final attempt = _speechAttempt;
    _speechStabilityTimer = Timer(wait, () {
      if (!mounted || attempt != _speechAttempt || _restartingSpeech ||
          _finalizingRecognizerStop || _isProcessingVoiceCommand ||
          _voiceEntry.session.state != SpeechSessionState.listening) return;
      final current = _voiceEntry.session.latestDraft;
      final complete = _speechCompleteness(current);
      // Sound activity may have continued without a new ASR text callback.
      final remaining = _speechTiming.waitFor(
          isComplete: complete.isComplete, kind: _speechTimingKind(complete));
      if (remaining == null) return;
      if (remaining > Duration.zero) {
        _scheduleStableSpeechFinalization(complete);
        return;
      }
      _traceSpeechEvent('endpoint_ready', transcript: current, completeness: complete);
      unawaited(_finishSpeechSession());
    });
  }

  Future<void> _finishSpeechSession({bool manual = false, bool deadline = false}) async {
    if (!mounted || _finalizingRecognizerStop || _isProcessingVoiceCommand ||
        _voiceEntry.session.state != SpeechSessionState.listening) return;
    final attempt = _speechAttempt;
    _finalizingRecognizerStop = true;
    _cancelSpeechTimers();
    _setListening(false);
    _speechTiming.mark('finalization_started');
    try {
      _speechTiming.mark('cleanup_started');
      final id = _voiceDiagnosticId;
      _recognizerCleanupPending = true;
      final cleanup = Future<void>.sync(_voiceEntry.speech.stop);
      AudioFeedbackService.deferSpokenFeedbackUntil(cleanup);
      final observedCleanup = cleanup.then((_) {
        if (mounted && attempt == _speechAttempt) {
          _speechTiming.mark('cleanup_completed');
          VoiceDiagnosticsService.instance.stage('timing', _speechTiming.timings, id: id);
        }
      }).whenComplete(() {
        if (mounted && attempt == _speechAttempt) {
          _recognizerCleanupPending = false;
          _smartInputUiRevision.value++;
        }
      });
      await reconcileSpeechEndpoint(
        timing: _speechTiming,
        cleanup: observedCleanup,
        finalResult: () => _speechFinalResult!.future,
        isCurrent: () => mounted && attempt == _speechAttempt,
      );
      if (!mounted || attempt != _speechAttempt) return;
      final transcript = _voiceEntry.session.latestDraft;
      final completeness = _speechCompleteness(transcript);
      _traceSpeechEvent(manual ? 'manual_stop' : deadline ? 'session_deadline' : 'finalized',
          transcript: transcript, completeness: completeness);
      if (!completeness.isComplete || transcript.isEmpty) {
        if (manual || deadline) {
          // Manual stop and the session deadline retain their existing
          // handler behavior, including normal confidence/amount validation.
          final decision = _voiceEntry.session.onRecognizerError(retryable: false);
          await _applySpeechDecision(decision);
          return;
        }
        VoiceDiagnosticsService.instance.finish(_voiceDiagnosticId,
            transcript.isEmpty ? 'no_speech' : 'incomplete',
            reason: completeness.reason);
        _voiceEntry.session.reset();
        _smartInputCtrl.clear();
        _showTransactionError(
          AppMessage('the_voice_command_was_incomplete_please_tap_the__e3c527'),
          title: AppMessage('voice_command_incomplete_0baf1a'),
        );
        return;
      }
      final decision = _voiceEntry.session.recordTranscript(
          transcript, isFinal: true, isComplete: true);
      _speechTiming.mark('endpoint_accepted');
      await _applySpeechDecision(decision);
    } catch (error) {
      _voiceEntry.session.markFailed();
      VoiceDiagnosticsService.instance.finish(_voiceDiagnosticId, 'failed',
          reason: 'finalization_${error.runtimeType}');
      _showTransactionError(
          AppMessage('voice_log_stopped_before_it_received_a_final_res_3ba187'),
          title: AppMessage('voice_log_stopped_c214bc'));
    } finally {
      _finalizingRecognizerStop = false;
      if (mounted) _smartInputUiRevision.value++;
    }
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
    if (!_isListening) _setListening(true);
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
    VoiceDiagnosticsService.instance.event(_voiceDiagnosticId, 'speech_session', {
      'event': event, 'transcript': transcript, 'state': _voiceEntry.session.state.name,
      'retry': _voiceEntry.session.retryCount, 'complete': completeness.isComplete,
      'reason': completeness.reason, 'timing': _speechTiming.timings,
    });
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
    if (!mounted || _handlingSpeechError || _finalizingRecognizerStop ||
        _isProcessingVoiceCommand) return;
    if (_voiceEntry.session.state != SpeechSessionState.listening &&
        _voiceEntry.session.state != SpeechSessionState.finalizing) {
      return;
    }
    VoiceDiagnosticsService.instance.event(_voiceDiagnosticId, 'recognizer_error', {'code': errorMessage});
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
    final retryOffline = _speechNetworkRecovery.tryOffline(
      normalized,
      isCloud: _voiceEntry.speech.isCloud,
      hasDraft: _voiceEntry.session.latestDraft.isNotEmpty,
      retryCount: _voiceEntry.session.retryCount,
    );
    final decision = _voiceEntry.session.onRecognizerError(
      retryable: recoverableEnd || canTryAnotherLocale || retryOffline,
    );

    if (decision.action == SpeechSessionAction.retry) {
      _smartInputCtrl.clear();
      await _restartSpeechListening(advanceLocale: canTryAnotherLocale);
      return;
    }

    _cancelSpeechTimers();
    _setListening(false);

    if (decision.action == SpeechSessionAction.processFinal) {
      await _applySpeechDecision(decision);
      return;
    }

    VoiceDiagnosticsService.instance.finish(_voiceDiagnosticId, 'failed', reason: errorMessage);
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
        AppMessage('voice_recognition_needs_an_internet_connection_o_2451e5'),
        title: AppMessage('voice_service_is_offline_4130dd'),
      );
      return;
    }

    if (languageFailure) {
      _showTransactionError(
        AppMessage('no_working_speech_language_was_found_enable_the__646a52'),
        title: AppMessage('speech_language_unavailable_5e3d34'),
      );
      return;
    }

    _showTransactionError(
      AppMessage('voice_log_stopped_before_it_received_a_final_res_3ba187'),
      title: AppMessage('voice_log_stopped_c214bc'),
    );
  }

  Future<void> _applySpeechDecision(SpeechSessionDecision decision) async {
    if (!mounted) return;
    switch (decision.action) {
      case SpeechSessionAction.processFinal:
        if (_isProcessingVoiceCommand) return;
        _cancelSpeechTimers();
        _setListening(false);
        _voiceEntry.session.markProcessing();
        _setVoiceProcessing(true);
        _speechTiming.mark('processing_started');
        try {
          final diagnosticId = _voiceDiagnosticId;
          VoiceDiagnosticsService.instance.submitted(diagnosticId, decision.transcript);
          final accepted = await VoiceDiagnosticsService.instance.run(diagnosticId, () => _processNLP(
            decision.transcript,
            source: SmartInputSource.voice,
          ));
          _speechTiming.mark('processing_completed');
          VoiceDiagnosticsService.instance.stage('timing', _speechTiming.timings, id: diagnosticId);
          VoiceDiagnosticsService.instance.finishProcessing(diagnosticId, accepted);
          _voiceEntry.session.markCompleted();
          _smartInputCtrl.clear();
          _voiceEntry.session.reset();
        } catch (error) {
          VoiceDiagnosticsService.instance.finish(_voiceDiagnosticId, 'failed', reason: 'processing_${error.runtimeType}');
          _voiceEntry.session.markFailed();
          _smartInputCtrl.clear();
          rethrow;
        } finally {
          _setVoiceProcessing(false);
        }
        return;
      case SpeechSessionAction.discardDraft:
        VoiceDiagnosticsService.instance.finish(_voiceDiagnosticId, 'incomplete', reason: 'draft_discarded');
        _cancelSpeechTimers();
        _setListening(false);
        _smartInputCtrl.clear();
        _voiceEntry.session.reset();
        _showTransactionError(
          AppMessage('the_voice_command_was_incomplete_please_tap_the__e3c527'),
          title: AppMessage('voice_command_incomplete_0baf1a'),
        );
        return;
      case SpeechSessionAction.none:
        if (_voiceEntry.session.state == SpeechSessionState.failed) {
          VoiceDiagnosticsService.instance.finish(_voiceDiagnosticId, 'no_speech', reason: 'no_complete_transcript');
          _cancelSpeechTimers();
          if (_isListening) _setListening(false);
          _smartInputCtrl.clear();
          _voiceEntry.session.reset();
          _showTransactionError(
            AppMessage('voice_recognition_stopped_before_hearing_any_wor_1b2943'),
            title: AppMessage('voice_stopped_too_soon_1a2e53'),
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
    _speechTiming.recordEnd();
    unawaited(_finalizeNormallyStoppedSpeech());
  }

  Future<void> _finalizeNormallyStoppedSpeech() async {
    if (_finalizingRecognizerStop || _isProcessingVoiceCommand ||
        _voiceEntry.session.state != SpeechSessionState.listening) return;
    final transcript = _voiceEntry.session.latestDraft;
    final completeness = _speechCompleteness(transcript);
    if (transcript.isEmpty) {
      final attempt = _speechAttempt;
      _speechStabilityTimer?.cancel();
      _speechStabilityTimer = Timer(SpeechTimingPolicy.resultGrace, () {
        if (!mounted || attempt != _speechAttempt || _finalizingRecognizerStop ||
            _isProcessingVoiceCommand) return;
        if (_voiceEntry.session.latestDraft.isNotEmpty) {
          _scheduleStableSpeechFinalization(
              _speechCompleteness(_voiceEntry.session.latestDraft));
        } else {
          unawaited(_applySpeechDecision(
              _voiceEntry.session.onRecognizerError(retryable: true)));
        }
      });
      return;
    }
    _scheduleStableSpeechFinalization(completeness);
  }
}

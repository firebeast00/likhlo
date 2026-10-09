import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:hive/hive.dart';

import '../models/expense_model.dart';
import 'voice_diagnostics_service.dart';
import 'deterministic_feedback_service.dart';
import 'voice_privacy_service.dart';
import '../l10n/app_strings.dart';

/// Plays deterministic transaction and app-command feedback.
///
/// Audio is deliberately best-effort: a device TTS error is logged locally
/// and never changes, rolls back, or delays the committed transaction.
class AudioFeedbackService {
  static const MethodChannel _deviceAudioChannel = MethodChannel(
    'com.likhlo/audio_feedback',
  );
  FlutterTts? _ttsInstance;
  final FlutterTts Function()? _ttsFactory;
  final bool _usesSharedTts;
  FlutterTts get _tts => _ttsInstance ??=
      _ttsFactory?.call() ?? (_sharedTts ??= FlutterTts());
  final DeterministicFeedbackService _messages;
  static FlutterTts? _sharedTts;
  static int _latestRequest = 0;
  static FlutterTts? _configuredTts;
  static AppLanguage? _configuredPreference;
  static bool _configuredUrdu = false;
  static Future<void>? _configurationTask;
  static Future<void> _microphoneCleanup = Future<void>.value();

  /// Ledger writes never await this gate. Only spoken feedback waits for the
  /// current recognizer cleanup, avoiding microphone/TTS overlap.
  static void deferSpokenFeedbackUntil(Future<void> cleanup) {
    _microphoneCleanup = cleanup;
  }
  static FlutterTts? _diagnosticTts;
  static String? _activeDiagnosticId;
  static int? _activeDiagnosticRequest;
  // FlutterTts callbacks have no utterance ID. After overlapping utterances,
  // report unknown completion rather than attributing an old callback to a save.
  static bool _callbackCorrelationReliable = true;

  static void _recordTtsCallback(String status) {
    final id = _activeDiagnosticId;
    if (id == null || !_callbackCorrelationReliable) return;
    VoiceDiagnosticsService.instance.stage('tts', {
      'status': status, 'request': _activeDiagnosticRequest,
      'completion_observed': status == 'completed',
    }, id: id);
    if (status == 'completed' || status == 'failed' || status == 'interrupted') {
      _activeDiagnosticId = null;
      _activeDiagnosticRequest = null;
    }
  }

  void _observeTts(FlutterTts engine, int request, String? id) {
    if (id == null && _activeDiagnosticId == null) return;
    try {
      if (!identical(_diagnosticTts, engine)) {
        _diagnosticTts = engine;
        _callbackCorrelationReliable = true;
        engine.setStartHandler(() => _recordTtsCallback('started'));
        engine.setCompletionHandler(() => _recordTtsCallback('completed'));
        engine.setCancelHandler(() => _recordTtsCallback('interrupted'));
        engine.setErrorHandler((_) => _recordTtsCallback('failed'));
      }
      if (_activeDiagnosticId != null) {
        _recordTtsCallback('interrupted');
        _callbackCorrelationReliable = false;
      }
      _activeDiagnosticId = id;
      _activeDiagnosticRequest = request;
      VoiceDiagnosticsService.instance.stage('tts', {
        'status': 'speak_invoked', 'request': request, 'completion_observed': false,
        'callback_correlation': _callbackCorrelationReliable ? 'single_utterance' : 'unknown_after_overlap',
      }, id: id);
    } catch (_) {
      // Installing diagnostic listeners must never prevent spoken feedback.
    }
  }

  AudioFeedbackService({
    FlutterTts? tts,
    FlutterTts Function()? ttsFactory,
    DeterministicFeedbackService messages =
        const DeterministicFeedbackService(),
  }) : _ttsInstance = tts,
       _ttsFactory = ttsFactory,
       _usesSharedTts = tts == null && ttsFactory == null,
       _messages = messages;

  Future<void> prepare() async {
    if (!Hive.isBoxOpen('preferences')) return;
    final privacy = VoicePrivacySettings.read(Hive.box('preferences'));
    if (!privacy.spokenFeedbackEnabled) return;
    try {
      await _configureOnce(AppLanguage.read());
    } catch (error) {
      debugPrint('Spoken confirmation warm-up unavailable: $error');
    }
  }

  Future<void> announce({
    required FinancialFeedbackAction action,
    required Expense entry,
    Expense? pairedEntry,
  }) async {
    final message = _messages.localizedMessage(
      FinancialFeedbackData(
        action: action,
        title: entry.title,
        amount: entry.amount,
        source: action == FinancialFeedbackAction.transfer
            ? _walletLabel(pairedEntry?.title ?? '', 'from')
            : null,
        destination: action == FinancialFeedbackAction.transfer
            ? _walletLabel(entry.title, 'to')
            : null,
      ),
    );
    await announceMessage(message);
  }

  /// Speaks an existing app response using the same opt-in and silent-mode
  /// checks as transaction confirmations. Never speaks a raw voice transcript.
  Future<void> announceMessage(Object message) async {
    final resolved = AppMessage.resolve(message);
    if (resolved.render(AppLanguage.english).trim().isEmpty) return;
    final request = ++_latestRequest;
    await _announceLatest(
      request: request,
      messages: [resolved],
    );
  }

  /// Reads both parts of an in-app notification. Query totals and periods
  /// often live in the title, while counts and details live in the body.
  Future<void> announceNotification({
    required Object title,
    required Object message,
  }) async {
    final request = ++_latestRequest;
    await _announceLatest(
      request: request,
      messages: [AppMessage.resolve(title), AppMessage.resolve(message)],
    );
  }

  /// Cancels delayed feedback as well as speech already playing.
  Future<void> stop() async {
    ++_latestRequest;
    if (_activeDiagnosticId != null) {
      _recordTtsCallback('interrupted');
      _activeDiagnosticId = null;
      _callbackCorrelationReliable = false;
    }
    try {
      final engine = _ttsInstance ?? (_usesSharedTts ? _sharedTts : null);
      if (engine != null && identical(_configuredTts, engine)) await engine.stop();
    } catch (error) {
      debugPrint('Spoken confirmation stop unavailable: $error');
    }
  }

  Future<void> _announceLatest({
    required int request,
    required List<AppMessage> messages,
  }) async {
    final diagnosticId = VoiceDiagnosticsService.instance.currentId;
    void observe(String status, {String? reason}) => VoiceDiagnosticsService.instance.stage('tts', {
      'status': status, 'reason': reason, 'request': request, 'completion_observed': false,
    }, id: diagnosticId);
    observe('preparing');
    final stopwatch = Stopwatch()..start();
    final language = AppLanguage.read();
    final canSpeakUrdu = messages.every((message) => message.hasUrduSpeech);
    try {
      if (request != _latestRequest) { observe('interrupted', reason: 'superseded'); return; }
      if (!Hive.isBoxOpen('preferences')) { observe('skipped', reason: 'preferences_unavailable'); return; }
      final privacy = VoicePrivacySettings.read(Hive.box('preferences'));
      if (!privacy.spokenFeedbackEnabled) { observe('skipped', reason: 'spoken_feedback_disabled'); return; }
      await _microphoneCleanup;
      if (request != _latestRequest) { observe('interrupted', reason: 'superseded'); return; }

      // Run the lightweight device-audio check while TTS configuration is
      // completing. Home pre-warms configuration after its first frame, so
      // normal saves usually reach speak() without any setup work.
      final silentModeFuture = defaultTargetPlatform == TargetPlatform.android
          ? _deviceAudioChannel
              .invokeMethod<bool>('isDeviceSilent')
              .then((value) => value ?? false)
          : Future<bool>.value(false);
      final readiness = await Future.wait<Object?>([
        silentModeFuture,
        _configureOnce(canSpeakUrdu ? language : AppLanguage.english).then<Object?>((_) => null),
      ]);
      final silentMode = readiness.first == true;
      if (silentMode || request != _latestRequest || AppLanguage.read() != language) {
        observe('skipped', reason: silentMode ? 'silent_mode' : 'superseded_or_language_changed'); return;
      }
      // A concurrent warm-up can reconfigure the shared engine while the
      // silent-mode check is pending. Restore this message's voice immediately
      // before speaking, including English fallback for unknown templates.
      await _configureOnce(canSpeakUrdu ? language : AppLanguage.english);
      if (request != _latestRequest || AppLanguage.read() != language) { observe('interrupted', reason: 'superseded_or_language_changed'); return; }
      final useUrdu = _configuredUrdu;
      // The setting may have changed while the device was preparing speech.
      if (!Hive.isBoxOpen('preferences') ||
          !VoicePrivacySettings.read(Hive.box('preferences'))
              .spokenFeedbackEnabled) {
        observe('skipped', reason: 'spoken_feedback_disabled');
        return;
      }
      if (request == _latestRequest) {
        VoiceDiagnosticsService.instance.stage('spoken_response', {
          'message_keys': messages.map((message) => message.key).toList(),
          'language': useUrdu ? 'ur' : 'en',
          'messages': messages.map((message) => message.render(
            useUrdu ? AppLanguage.romanUrdu : AppLanguage.english, spoken: true)).toList(),
        }, id: diagnosticId);
        _observeTts(_tts, request, diagnosticId);
        await _tts.speak(
          messages.map((message) => message.render(
            useUrdu ? AppLanguage.romanUrdu : AppLanguage.english,
            spoken: true,
          ).trim()).join('. ')
              .replaceAll(' · ', ', ')
              .replaceAllMapped(
                RegExp(r'\bRs\.?\s*([0-9,]+(?:\.[0-9]+)?)', caseSensitive: false),
                (match) => '${match.group(1)} ${useUrdu ? 'روپے' : 'rupees'}',
              )
              .replaceAll(RegExp('jazzcash', caseSensitive: false),
                useUrdu ? 'جاز کیش' : 'Jazz Cash'),
        );
        assert(() {
          debugPrint(
            '[Audio feedback] speak_invoked_ms=${stopwatch.elapsedMilliseconds} '
            'request=$request',
          );
          return true;
        }());
      }
    } catch (error) {
      observe('failed', reason: error.runtimeType.toString());
      debugPrint('Spoken confirmation unavailable: $error');
    }
  }

  Future<void> _configureOnce(AppLanguage language) async {
    // Serialize across engines and language changes; a waiting caller must
    // check the completed configuration instead of using another voice.
    while (true) {
      final inFlight = _configurationTask;
      if (inFlight != null) {
        await inFlight;
        continue;
      }
      if (identical(_configuredTts, _tts) && _configuredPreference == language) return;
      final task = _configureTts(language);
      _configurationTask = task;
      try {
        await task;
        return;
      } finally {
        if (identical(_configurationTask, task)) _configurationTask = null;
      }
    }
  }

  Future<void> _configureTts(AppLanguage language) async {
    var selectedUrdu = false;
    if (language == AppLanguage.romanUrdu) {
      for (final locale in ['ur-PK', 'ur-IN']) {
        try {
          final available = await _tts.isLanguageAvailable(locale) == true;
          final installed = defaultTargetPlatform != TargetPlatform.android ||
              await _tts.isLanguageInstalled(locale) == true;
          if (!available || !installed) continue;
          final result = await _tts.setLanguage(locale);
          if (result == 0 || result == false || (result is num && result < 0)) continue;
          selectedUrdu = true;
          break;
        } catch (_) {
          // Unsupported voice checks are a normal fallback on some engines.
        }
      }
    }
    if (!selectedUrdu) await _tts.setLanguage('en-IN');
    await _tts.setSpeechRate(0.56);
    await _tts.setVolume(1);
    await _tts.setPitch(1);
    _configuredTts = _tts;
    _configuredPreference = language;
    _configuredUrdu = selectedUrdu;
  }

  String? _walletLabel(String title, String marker) {
    final match = RegExp(
      '\\b${RegExp.escape(marker)}\\s+(.+)\$',
      caseSensitive: false,
    ).firstMatch(title.trim());
    final value = match?.group(1)?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}


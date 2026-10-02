import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:hive/hive.dart';

import '../models/expense_model.dart';
import 'deterministic_feedback_service.dart';
import 'voice_privacy_service.dart';

/// Plays deterministic confirmations after a ledger commit.
///
/// Audio is deliberately best-effort: a device TTS error is logged locally
/// and never changes, rolls back, or delays the committed transaction.
class AudioFeedbackService {
  static const MethodChannel _deviceAudioChannel = MethodChannel(
    'com.likhlo/audio_feedback',
  );
  final FlutterTts _tts;
  final DeterministicFeedbackService _messages;
  static final FlutterTts _sharedTts = FlutterTts();
  static int _latestRequest = 0;
  static FlutterTts? _configuredTts;
  static Future<void>? _configurationTask;

  AudioFeedbackService({
    FlutterTts? tts,
    DeterministicFeedbackService messages =
        const DeterministicFeedbackService(),
  }) : _tts = tts ?? _sharedTts,
       _messages = messages;

  Future<void> prepare() async {
    if (!Hive.isBoxOpen('preferences')) return;
    final privacy = VoicePrivacySettings.read(Hive.box('preferences'));
    if (!privacy.spokenFeedbackEnabled) return;
    try {
      await _configureOnce();
    } catch (error) {
      debugPrint('Spoken confirmation warm-up unavailable: $error');
    }
  }

  Future<void> announce({
    required FinancialFeedbackAction action,
    required Expense entry,
    Expense? pairedEntry,
  }) async {
    final request = ++_latestRequest;
    await _announceLatest(
      request: request,
      action: action,
      entry: entry,
      pairedEntry: pairedEntry,
    );
  }

  Future<void> _announceLatest({
    required int request,
    required FinancialFeedbackAction action,
    required Expense entry,
    Expense? pairedEntry,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      if (request != _latestRequest) return;
      if (!Hive.isBoxOpen('preferences')) return;
      final privacy = VoicePrivacySettings.read(Hive.box('preferences'));
      if (!privacy.spokenFeedbackEnabled) return;

      // Run the lightweight device-audio check while TTS configuration is
      // completing. Home pre-warms configuration after its first frame, so
      // normal saves usually reach speak() without any setup work.
      final silentModeFuture = defaultTargetPlatform == TargetPlatform.android
          ? _deviceAudioChannel
              .invokeMethod<bool>('isDeviceSilent')
              .then((value) => value ?? false)
          : Future<bool>.value(false);
      final configurationFuture = _configureOnce();

      final silentMode = await silentModeFuture;
      if (silentMode || request != _latestRequest) return;
      await configurationFuture;
      if (request != _latestRequest) return;

      final message = _messages.message(
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
      if (request == _latestRequest) {
        await _tts.speak(
          message.replaceAll(
            RegExp('jazzcash', caseSensitive: false),
            'Jazz Cash',
          ),
        );
        assert(() {
          debugPrint(
            '[Audio feedback] speak_invoked_ms=${stopwatch.elapsedMilliseconds} '
            'action=$action',
          );
          return true;
        }());
      }
    } catch (error) {
      debugPrint('Spoken confirmation unavailable: $error');
    }
  }

  Future<void> _configureOnce() async {
    if (identical(_configuredTts, _tts)) return;
    final inFlight = _configurationTask;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final task = _configureTts();
    _configurationTask = task;
    try {
      await task;
    } finally {
      if (identical(_configurationTask, task)) {
        _configurationTask = null;
      }
    }
  }

  Future<void> _configureTts() async {
    // Prefer a familiar accent for Roman Urdu and English code switching.
    await _tts.setLanguage('en-IN');
    await _tts.setSpeechRate(0.56);
    await _tts.setVolume(1);
    await _tts.setPitch(1);
    _configuredTts = _tts;
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

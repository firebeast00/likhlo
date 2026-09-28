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
  static Future<void> _previousSpeech = Future<void>.value();
  static int _latestRequest = 0;
  static FlutterTts? _configuredTts;

  AudioFeedbackService({
    FlutterTts? tts,
    DeterministicFeedbackService messages =
        const DeterministicFeedbackService(),
  }) : _tts = tts ?? _sharedTts,
       _messages = messages;

  Future<void> announce({
    required FinancialFeedbackAction action,
    required Expense entry,
    Expense? pairedEntry,
  }) async {
    final request = ++_latestRequest;
    final next = _previousSpeech.then(
      (_) => _announceLatest(
        request: request,
        action: action,
        entry: entry,
        pairedEntry: pairedEntry,
      ),
    );
    _previousSpeech = next.catchError((Object error) {
      debugPrint('Spoken confirmation unavailable: $error');
    });
    await next;
  }

  Future<void> _announceLatest({
    required int request,
    required FinancialFeedbackAction action,
    required Expense entry,
    Expense? pairedEntry,
  }) async {
    try {
      if (request != _latestRequest) return;
      if (!Hive.isBoxOpen('preferences')) return;
      final privacy = VoicePrivacySettings.read(Hive.box('preferences'));
      if (!privacy.spokenFeedbackEnabled) return;
      final silentMode = defaultTargetPlatform == TargetPlatform.android
          ? await _deviceAudioChannel.invokeMethod<bool>('isDeviceSilent') ??
                false
          : false;
      if (silentMode) return;

      await _configureOnce();
      if (request != _latestRequest) return;
      await _tts.stop();
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
      }
    } catch (error) {
      debugPrint('Spoken confirmation unavailable: $error');
    }
  }

  Future<void> _configureOnce() async {
    if (identical(_configuredTts, _tts)) return;
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

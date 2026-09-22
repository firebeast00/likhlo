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
  static const MethodChannel _deviceAudioChannel =
      MethodChannel('com.likhlo/audio_feedback');
  final FlutterTts _tts;
  final DeterministicFeedbackService _messages;
  bool _configured = false;

  AudioFeedbackService({
    FlutterTts? tts,
    DeterministicFeedbackService messages =
        const DeterministicFeedbackService(),
  })  : _tts = tts ?? FlutterTts(),
        _messages = messages;

  Future<void> announce({
    required FinancialFeedbackAction action,
    required Expense entry,
    Expense? pairedEntry,
  }) async {
    try {
      if (!Hive.isBoxOpen('preferences')) return;
      final privacy = VoicePrivacySettings.read(Hive.box('preferences'));
      if (!privacy.spokenFeedbackEnabled) return;
      final silentMode = defaultTargetPlatform == TargetPlatform.android
          ? await _deviceAudioChannel.invokeMethod<bool>('isDeviceSilent') ??
              false
          : false;
      if (silentMode) return;

      await _configureOnce();
      await _tts.stop();
      final message = _messages.message(
        FinancialFeedbackData(
          action: action,
          title: entry.title,
          amount: entry.amount,
          source: action == FinancialFeedbackAction.transfer
              ? _walletLabel(pairedEntry?.title ?? '', 'from') ??
                  entry.walletId
              : null,
          destination: action == FinancialFeedbackAction.transfer
              ? _walletLabel(entry.title, 'to') ??
                  pairedEntry?.walletId
              : null,
        ),
      );
      await _tts.speak(message);
    } catch (error) {
      debugPrint('Spoken confirmation unavailable: $error');
    }
  }

  Future<void> _configureOnce() async {
    if (_configured) return;
    _configured = true;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.46);
    await _tts.setVolume(1);
    await _tts.setPitch(1);
  }

  String? _walletLabel(String title, String marker) {
    final match = RegExp(
      '\\b$marker\\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(title.trim());
    final value = match?.group(1)?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}

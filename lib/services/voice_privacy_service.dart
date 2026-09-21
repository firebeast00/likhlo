import 'package:hive_flutter/hive_flutter.dart';

class VoicePrivacySettings {
  static const cloudSpeechKey = 'voice_cloud_speech_enabled_v1';
  static const diagnosticsKey = 'voice_diagnostics_opt_in_v1';
  static const spokenFeedbackKey = 'voice_spoken_feedback_enabled_v1';

  final bool cloudSpeechEnabled;
  final bool diagnosticsOptIn;
  final bool spokenFeedbackEnabled;

  const VoicePrivacySettings({
    this.cloudSpeechEnabled = false,
    this.diagnosticsOptIn = false,
    this.spokenFeedbackEnabled = false,
  });

  factory VoicePrivacySettings.read(Box box) {
    return VoicePrivacySettings(
      cloudSpeechEnabled: box.get(cloudSpeechKey, defaultValue: false) == true,
      diagnosticsOptIn: box.get(diagnosticsKey, defaultValue: false) == true,
      spokenFeedbackEnabled:
          box.get(spokenFeedbackKey, defaultValue: false) == true,
    );
  }
}

class VoiceDiagnosticEvent {
  final String provider;
  final String outcome;
  final int durationMilliseconds;
  final String? errorCategory;

  const VoiceDiagnosticEvent({
    required this.provider,
    required this.outcome,
    required this.durationMilliseconds,
    this.errorCategory,
  });

  Map<String, Object?> toPrivacySafeMap() => {
        'provider': provider,
        'outcome': outcome,
        'durationMs': durationMilliseconds,
        'errorCategory': errorCategory,
      };
}

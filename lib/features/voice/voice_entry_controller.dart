import '../../services/speech_command_completeness.dart';
import '../../services/speech_recognition_provider.dart';
import '../../services/speech_session_controller.dart';

/// Owns the reusable voice-entry dependencies and timing policy.
///
/// UI lifecycle flags/timers remain in HomeScreen for now so this extraction
/// does not change recognition behavior.
class VoiceEntryController {
  VoiceEntryController({
    SpeechRecognitionProvider? speech,
    SpeechSessionController? session,
    SpeechCommandCompletenessEvaluator? completeness,
  })  : speech = speech ??
            SpeechProviderRouter(
              deviceProvider: DeviceSpeechRecognitionProvider(),
            ),
        session = session ?? SpeechSessionController(maxRetries: 1),
        completeness =
            completeness ?? const SpeechCommandCompletenessEvaluator();

  final SpeechRecognitionProvider speech;
  final SpeechSessionController session;
  final SpeechCommandCompletenessEvaluator completeness;

  static const pauseWindow = Duration(seconds: 5);
  static const stabilityWindow = Duration(seconds: 3);
  static const sessionLimit = Duration(seconds: 30);
  static const startupGrace = Duration(milliseconds: 1200);
  static const prematureStatusGuard = Duration(milliseconds: 600);
}

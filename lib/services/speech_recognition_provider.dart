import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechRecognitionLocale {
  final String localeId;
  final String name;

  const SpeechRecognitionLocale({
    required this.localeId,
    required this.name,
  });
}

class SpeechRecognitionResult {
  final String text;
  final bool isFinal;
  final double? stability;
  final String provider;
  final String? detectedLanguage;

  const SpeechRecognitionResult({
    required this.text,
    required this.isFinal,
    required this.provider,
    this.stability,
    this.detectedLanguage,
  });
}

class SpeechRecognitionError {
  final String message;
  final String provider;

  const SpeechRecognitionError({
    required this.message,
    required this.provider,
  });
}

class SpeechRecognitionListenOptions {
  final String? localeId;
  final bool partialResults;
  final Duration pauseFor;
  final Duration listenFor;

  const SpeechRecognitionListenOptions({
    this.localeId,
    this.partialResults = true,
    this.pauseFor = const Duration(seconds: 3),
    this.listenFor = const Duration(seconds: 20),
  });
}

abstract interface class SpeechRecognitionProvider {
  String get id;
  bool get isCloud;

  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(SpeechRecognitionError error) onError,
  });

  Future<List<SpeechRecognitionLocale>> locales();
  Future<SpeechRecognitionLocale?> systemLocale();

  Future<void> listen({
    required SpeechRecognitionListenOptions options,
    required Future<void> Function(SpeechRecognitionResult result) onResult,
  });

  Future<void> stop();
  Future<void> cancel();
}

class DeviceSpeechRecognitionProvider implements SpeechRecognitionProvider {
  final stt.SpeechToText _speech;

  DeviceSpeechRecognitionProvider({stt.SpeechToText? speech})
      : _speech = speech ?? stt.SpeechToText();

  @override
  String get id => 'device';

  @override
  bool get isCloud => false;

  @override
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(SpeechRecognitionError error) onError,
  }) {
    return _speech.initialize(
      onStatus: onStatus,
      onError: (error) => onError(SpeechRecognitionError(
        message: error.errorMsg,
        provider: id,
      )),
    );
  }

  @override
  Future<List<SpeechRecognitionLocale>> locales() async {
    final values = await _speech.locales();
    return values
        .map((locale) => SpeechRecognitionLocale(
              localeId: locale.localeId,
              name: locale.name,
            ))
        .toList(growable: false);
  }

  @override
  Future<SpeechRecognitionLocale?> systemLocale() async {
    final locale = await _speech.systemLocale();
    if (locale == null) return null;
    return SpeechRecognitionLocale(
      localeId: locale.localeId,
      name: locale.name,
    );
  }

  @override
  Future<void> listen({
    required SpeechRecognitionListenOptions options,
    required Future<void> Function(SpeechRecognitionResult result) onResult,
  }) async {
    await _speech.listen(
      listenOptions: stt.SpeechListenOptions(
        localeId: options.localeId,
        cancelOnError: true,
        partialResults: options.partialResults,
        listenMode: stt.ListenMode.search,
        pauseFor: options.pauseFor,
        listenFor: options.listenFor,
      ),
      onResult: (result) => onResult(SpeechRecognitionResult(
        text: result.recognizedWords,
        isFinal: result.finalResult,
        provider: id,
      )),
    );
  }

  @override
  Future<void> stop() async {
    await _speech.stop();
  }

  @override
  Future<void> cancel() async {
    await _speech.cancel();
  }
}

/// Selects exactly one recognizer for a session. The cloud provider is never
/// started alongside device recognition and remains opt-in.
class SpeechProviderRouter implements SpeechRecognitionProvider {
  final SpeechRecognitionProvider deviceProvider;
  final SpeechRecognitionProvider? cloudProvider;
  final bool preferCloud;
  SpeechRecognitionProvider? _active;

  SpeechProviderRouter({
    required this.deviceProvider,
    this.cloudProvider,
    this.preferCloud = false,
  });

  SpeechRecognitionProvider get _selected =>
      preferCloud && cloudProvider != null ? cloudProvider! : deviceProvider;

  @override
  String get id => _active?.id ?? _selected.id;

  @override
  bool get isCloud => _active?.isCloud ?? _selected.isCloud;

  @override
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(SpeechRecognitionError error) onError,
  }) async {
    final selected = _selected;
    final available = await selected.initialize(
      onStatus: onStatus,
      onError: onError,
    );
    if (available) {
      _active = selected;
      return true;
    }
    if (selected == deviceProvider) return false;
    final fallbackAvailable = await deviceProvider.initialize(
      onStatus: onStatus,
      onError: onError,
    );
    if (fallbackAvailable) _active = deviceProvider;
    return fallbackAvailable;
  }

  @override
  Future<List<SpeechRecognitionLocale>> locales() =>
      (_active ?? _selected).locales();

  @override
  Future<SpeechRecognitionLocale?> systemLocale() =>
      (_active ?? _selected).systemLocale();

  @override
  Future<void> listen({
    required SpeechRecognitionListenOptions options,
    required Future<void> Function(SpeechRecognitionResult result) onResult,
  }) =>
      (_active ?? _selected).listen(options: options, onResult: onResult);

  @override
  Future<void> stop() => (_active ?? _selected).stop();

  @override
  Future<void> cancel() => (_active ?? _selected).cancel();
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'speech_recognition_provider.dart';

enum ChirpLanguageMode { urduPakistan, urduAndEnglish, automatic }

class ChirpGatewayConfig {
  final Uri endpoint;
  final Future<String?> Function() accessTokenProvider;
  final ChirpLanguageMode languageMode;
  final List<String> adaptationHints;
  final bool denoiserEnabled;

  const ChirpGatewayConfig({
    required this.endpoint,
    required this.accessTokenProvider,
    this.languageMode = ChirpLanguageMode.urduPakistan,
    this.adaptationHints = const [],
    this.denoiserEnabled = true,
  });

  List<String> get languageCodes {
    switch (languageMode) {
      case ChirpLanguageMode.urduPakistan:
        return const ['ur-PK'];
      case ChirpLanguageMode.urduAndEnglish:
        return const ['ur-PK', 'en-IN'];
      case ChirpLanguageMode.automatic:
        return const ['auto'];
    }
  }
}

abstract interface class ChirpAudioSource {
  Stream<List<int>> start();
  Future<void> stop();
}

/// Experimental authenticated gateway provider. It contains no Google
/// credential and cannot be selected until an audio source and gateway config
/// are explicitly supplied by the application.
class ChirpGatewaySpeechProvider implements SpeechRecognitionProvider {
  final ChirpGatewayConfig config;
  final ChirpAudioSource audioSource;
  WebSocket? _socket;
  void Function(String status)? _onStatus;
  void Function(SpeechRecognitionError error)? _onError;

  ChirpGatewaySpeechProvider({
    required this.config,
    required this.audioSource,
  });

  @override
  String get id => 'chirp_3_gateway';

  @override
  bool get isCloud => true;

  @override
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(SpeechRecognitionError error) onError,
  }) async {
    _onStatus = onStatus;
    _onError = onError;
    return config.endpoint.isScheme('wss');
  }

  @override
  Future<List<SpeechRecognitionLocale>> locales() async => const [
        SpeechRecognitionLocale(localeId: 'ur-PK', name: 'Urdu (Pakistan)'),
        SpeechRecognitionLocale(localeId: 'en-IN', name: 'English (India)'),
      ];

  @override
  Future<SpeechRecognitionLocale?> systemLocale() async =>
      const SpeechRecognitionLocale(
        localeId: 'ur-PK',
        name: 'Urdu (Pakistan)',
      );

  @override
  Future<void> listen({
    required SpeechRecognitionListenOptions options,
    required Future<void> Function(SpeechRecognitionResult result) onResult,
    // The gateway does not expose sound levels. Endpoint timing retains its
    // transcript/final-result fallback for this provider.
    void Function(double level)? onSoundLevelChange,
  }) async {
    final token = await config.accessTokenProvider();
    if (token == null || token.trim().isEmpty) {
      throw StateError('A short-lived gateway access token is required.');
    }
    final socket = await WebSocket.connect(
      config.endpoint.toString(),
      headers: {'Authorization': 'Bearer $token'},
    );
    _socket = socket;
    socket.add(jsonEncode({
      'type': 'config',
      'model': 'chirp_3',
      'languageCodes': config.languageCodes,
      'endpointing': 'SHORT',
      'automaticPunctuation': true,
      'denoiser': config.denoiserEnabled,
      'hints': config.adaptationHints.take(200).toList(),
    }));
    _onStatus?.call('listening');

    socket.listen(
      (message) {
        if (message is! String) return;
        final event = jsonDecode(message);
        if (event is! Map) return;
        if (event['type'] == 'transcript') {
          onResult(SpeechRecognitionResult(
            text: event['text']?.toString() ?? '',
            isFinal: event['isFinal'] == true,
            stability: (event['stability'] as num?)?.toDouble(),
            detectedLanguage: event['languageCode']?.toString(),
            provider: id,
          ));
        } else if (event['type'] == 'error') {
          _onError?.call(SpeechRecognitionError(
            message: event['message']?.toString() ?? 'cloud_error',
            provider: id,
          ));
        }
      },
      onDone: () => _onStatus?.call('done'),
      onError: (Object error) => _onError?.call(SpeechRecognitionError(
        message: error.toString(),
        provider: id,
      )),
      cancelOnError: true,
    );

    unawaited(_streamAudio(socket));
  }

  Future<void> _streamAudio(WebSocket socket) async {
    try {
      await for (final chunk in audioSource.start()) {
        if (_socket != socket || socket.readyState != WebSocket.open) break;
        socket.add(chunk);
      }
    } catch (error) {
      _onError?.call(SpeechRecognitionError(
        message: error.toString(),
        provider: id,
      ));
    }
  }

  @override
  Future<void> stop() async {
    await audioSource.stop();
    _socket?.add(jsonEncode({'type': 'finish'}));
  }

  @override
  Future<void> cancel() async {
    await audioSource.stop();
    await _socket?.close(WebSocketStatus.normalClosure);
    _socket = null;
  }
}


import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:hive/hive.dart';
import 'package:student_expense_manager/app/app_action.dart';
import 'package:student_expense_manager/models/expense_model.dart';
import 'package:student_expense_manager/services/audio_feedback_service.dart';
import 'package:student_expense_manager/services/deterministic_feedback_service.dart';
import 'package:student_expense_manager/services/voice_privacy_service.dart';

class _RecordingTts extends FlutterTts {
  final spoken = <String>[];
  int stops = 0;
  bool failSpeech = false;
  bool failConfiguration = false;

  @override
  Future<dynamic> setLanguage(String language) async {
    if (failConfiguration) throw StateError('TTS setup unavailable');
    return 1;
  }
  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;
  @override
  Future<dynamic> setVolume(double volume) async => 1;
  @override
  Future<dynamic> setPitch(double pitch) async => 1;
  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    if (failSpeech) throw StateError('TTS unavailable');
    spoken.add(text);
    return 1;
  }

  @override
  Future<dynamic> stop() async {
    stops++;
    return 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const audioChannel = MethodChannel('com.likhlo/audio_feedback');
  late Directory temporaryDirectory;
  late Box preferences;
  late _RecordingTts tts;
  late AudioFeedbackService service;
  bool silent = false;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('likhlo_audio_');
    Hive.init(temporaryDirectory.path);
    preferences = await Hive.openBox('preferences');
    await preferences.put(VoicePrivacySettings.spokenFeedbackKey, true);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    silent = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioChannel, (_) async => silent);
    tts = _RecordingTts();
    service = AudioFeedbackService(tts: tts);
    await service.prepare();
  });

  tearDown(() async {
    await service.stop();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioChannel, null);
    debugDefaultTargetPlatformOverride = null;
    await Hive.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test('app responses speak when feedback is enabled', () async {
    await service.announceMessage('Orange theme color is now active.');
    await service.announceMessage('Showing October 2026 Stats.');
    await service.announceMessage('Spoken confirmations are enabled.');
    expect(tts.spoken, [
      'Orange theme color is now active.',
      'Showing October 2026 Stats.',
      'Spoken confirmations are enabled.',
    ]);
  });

  test('disabled feedback, blank messages and silent mode do not speak', () async {
    await preferences.put(VoicePrivacySettings.spokenFeedbackKey, false);
    await service.announceMessage('Dark mode is now enabled.');
    await preferences.put(VoicePrivacySettings.spokenFeedbackKey, true);
    await service.announceMessage('  ');
    silent = true;
    await service.announceMessage('App menu opened.');
    expect(tts.spoken, isEmpty);
  });

  test('turning feedback off while audio is preparing prevents speech', () async {
    final audioCheckStarted = Completer<void>();
    final audioCheck = Completer<bool>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioChannel, (_) {
      audioCheckStarted.complete();
      return audioCheck.future;
    });
    final announcement = service.announceMessage('Dark mode is now enabled.');
    await audioCheckStarted.future;
    await preferences.put(VoicePrivacySettings.spokenFeedbackKey, false);
    audioCheck.complete(false);
    await announcement;
    expect(tts.spoken, isEmpty);
  });

  test('a new microphone session cancels delayed and active speech', () async {
    await service.announceMessage('Spoken confirmations are enabled.');
    final audioCheckStarted = Completer<void>();
    final audioCheck = Completer<bool>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioChannel, (_) {
      audioCheckStarted.complete();
      return audioCheck.future;
    });
    final pending = service.announceMessage('Opening Stats.');
    await audioCheckStarted.future;
    await service.stop();
    audioCheck.complete(false);
    await pending;
    expect(tts.stops, 1);
    expect(tts.spoken, ['Spoken confirmations are enabled.']);
  });

  test('committed transaction wording and JazzCash pronunciation remain', () async {
    await service.announce(
      action: FinancialFeedbackAction.expense,
      entry: Expense(
        id: 'saved-entry',
        title: 'Biryani from JazzCash',
        amount: 500,
        date: DateTime(2026, 10, 5),
        category: 'Food',
        colorValue: 0,
      ),
    );
    expect(tts.spoken, ['Biryani from Jazz Cash, 500 rupees expense saved.']);
  });

  test('device TTS errors remain best effort', () async {
    tts.failSpeech = true;
    await expectLater(service.announceMessage('Opening Wallets.'), completes);
  });

  test('TTS setup errors are caught even when the phone is silent', () async {
    final unavailableTts = _RecordingTts()..failConfiguration = true;
    silent = true;
    final unavailableService = AudioFeedbackService(tts: unavailableTts);
    await expectLater(
      unavailableService.announceMessage('Opening Stats.'),
      completes,
    );
    expect(unavailableTts.spoken, isEmpty);
  });

  test('delegated actions preserve voice origin without changing defaults', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(appActionProvider.notifier);
    controller.request(AppActionType.spokenConfirmationsOn);
    expect(container.read(appActionProvider)!.spokenFeedback, isFalse);
    controller.request(
      AppActionType.openStatsMonth,
      month: DateTime(2026, 9, 10),
      spokenFeedback: true,
    );
    final request = container.read(appActionProvider)!;
    expect(request.spokenFeedback, isTrue);
    expect(request.month, DateTime(2026, 9));
    controller.consume(request.id);
    expect(container.read(appActionProvider), isNull);
  });
}

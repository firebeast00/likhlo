import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';

import 'backup_codec.dart';
import 'backup_service.dart';

/// Refreshes the previously chosen Android document while the app is running.
/// Its password is retained by the platform Keystore, never in a Hive backup.
class AutomaticBackupService with WidgetsBindingObserver {
  AutomaticBackupService._();
  static final AutomaticBackupService instance = AutomaticBackupService._();
  static const channel = MethodChannel('com.likhlo/automatic_backup');
  static const lastSuccessKey = 'automatic_backup_last_success_v1';
  static const interval = Duration(hours: 24);

  Timer? _timer;
  bool _working = false;

  Future<bool> get supported async => defaultTargetPlatform == TargetPlatform.android &&
      (await channel.invokeMethod<bool>('supported') ?? false);

  void start() {
    if (defaultTargetPlatform != TargetPlatform.android || _timer != null)
      return;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => unawaited(updateIfDue()),
    );
    unawaited(updateIfDue());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(updateIfDue());
  }

  Future<bool> saveNew(Uint8List bytes, String password, String name) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    final saved = await channel.invokeMethod<bool>('create', {
      'bytes': bytes,
      'password': password,
      'name': name,
    });
    if (saved == true && Hive.isBoxOpen('preferences')) {
      await Hive.box('preferences')
          .put(lastSuccessKey, DateTime.now().toUtc().toIso8601String());
    }
    return saved == true;
  }

  Future<void> updateIfDue() async {
    if (defaultTargetPlatform != TargetPlatform.android ||
        _working ||
        !Hive.isBoxOpen('preferences'))
      return;
    final box = Hive.box('preferences');
    final rawDate = box.get(lastSuccessKey);
    if (rawDate is! String) return;
    final last = DateTime.tryParse(rawDate);
    if (last != null &&
        DateTime.now().toUtc().difference(last.toUtc()) < interval)
      return;
    _working = true;
    try {
      final config = await channel.invokeMapMethod<String, String>(
        'configuration',
      );
      final password = config?['password'];
      if (password == null || password.isEmpty) return;
      final bytes = await BackupCodec().encrypt(
        await BackupService().createPayload(),
        password,
      );
      if (bytes.length > BackupService.maxBackupBytes) return;
      final updated = await channel.invokeMethod<bool>('overwrite', {
        'bytes': bytes,
      });
      if (updated == true) {
        await box.put(lastSuccessKey, DateTime.now().toUtc().toIso8601String());
      }
    } catch (error) {
      // Preserve the last successful timestamp for a retry next launch/resume.
      debugPrint('Automatic backup refresh failed: $error');
    } finally {
      _working = false;
    }
  }
}

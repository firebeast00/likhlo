import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_10y.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:hive/hive.dart';
import '../models/expense_model.dart';
import '../models/wallet_model.dart';
import 'notification_entry_service.dart';

const _notificationEntryPortName = 'likhlo_notification_entry_port_v1';

class _NotificationEntryOutcome {
  final NotificationEntryResult result;
  final double? remainingToday;
  final double? spentToday;

  const _NotificationEntryOutcome(
    this.result, {
    this.remainingToday,
    this.spentToday,
  });
}

Future<_NotificationEntryOutcome> _processNotificationEntry(
  NotificationResponse response,
) async {
  final input = response.input ?? '';
  final notificationId =
      response.id ?? NotificationService.persistentBarId;
  final mainPort = IsolateNameServer.lookupPortByName(
    _notificationEntryPortName,
  );
  if (mainPort == null) {
    final result = await NotificationEntryService().process(
      input: input,
      notificationId: notificationId,
    );
    final status = NotificationService().persistentStatusSnapshot();
    return _NotificationEntryOutcome(
      result,
      remainingToday: status?['remainingToday'],
      spentToday: status?['spentToday'],
    );
  }

  final reply = ReceivePort();
  try {
    mainPort.send({
      'input': input,
      'notificationId': notificationId,
      'replyTo': reply.sendPort,
    });
    final message = await reply.first.timeout(const Duration(seconds: 20));
    if (message is Map) {
      final dispositionName = message['disposition']?.toString();
      final disposition = NotificationEntryDisposition.values.firstWhere(
        (value) => value.name == dispositionName,
        orElse: () => NotificationEntryDisposition.failed,
      );
      return _NotificationEntryOutcome(
        NotificationEntryResult(
          disposition,
          message['message']?.toString() ?? 'The entry could not be saved.',
        ),
        remainingToday: message['remainingToday'] is num
            ? (message['remainingToday'] as num).toDouble()
            : null,
        spentToday: message['spentToday'] is num
            ? (message['spentToday'] as num).toDouble()
            : null,
      );
    }
  } catch (error) {
    debugPrint('Notification entry bridge failed: $error');
  } finally {
    reply.close();
  }
  return const _NotificationEntryOutcome(
    NotificationEntryResult(
      NotificationEntryDisposition.failed,
      'The entry could not be saved. Please try again.',
    ),
  );
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  if (response.actionId != NotificationService.inlineEntryActionId) return;
  WidgetsFlutterBinding.ensureInitialized();
  final notifications = NotificationService();
  await notifications.initializeForBackgroundAction();
  final outcome = await _processNotificationEntry(response);
  // Re-post the pinned card first so Android clears the remote-input spinner
  // even when the visible app isolate is not running.
  if (outcome.remainingToday != null && outcome.spentToday != null) {
    await notifications.updatePersistentStatusBarWidget(
      remainingToday: outcome.remainingToday!,
      spentToday: outcome.spentToday!,
    );
  } else {
    await notifications.refreshPersistentStatusBarWidget();
  }
  await notifications.showNotificationEntryResult(outcome.result);
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  ReceivePort? _entryBridgePort;

  // Notification ID Partitioning
  static const int persistentBarId = 700;
  static const int testNotificationId = 888;
  static const int middayReminderId = 901;
  static const int eveningReminderId = 902;
  static const int weekendReviewId = 903;
  static const int notificationEntryResultId = 904;
  static const String inlineEntryActionId = 'action_inline_entry';
  static const String reviewEntryActionId = 'action_review_notification';

  /// Callback hook for when notification action buttons are tapped
  void Function(String action)? onActionTriggered;
  String? _pendingAction;

  String? takePendingAction() {
    final action = _pendingAction;
    _pendingAction = null;
    return action;
  }

  void startBackgroundEntryBridge() {
    if (_entryBridgePort != null) return;
    IsolateNameServer.removePortNameMapping(_notificationEntryPortName);
    final port = ReceivePort();
    if (!IsolateNameServer.registerPortWithName(
      port.sendPort,
      _notificationEntryPortName,
    )) {
      port.close();
      return;
    }
    _entryBridgePort = port;
    port.listen((message) async {
      if (message is! Map) return;
      final replyTo = message['replyTo'];
      if (replyTo is! SendPort) return;
      final result = await NotificationEntryService().process(
        input: message['input']?.toString() ?? '',
        notificationId: message['notificationId'] is int
            ? message['notificationId'] as int
            : persistentBarId,
      );
      final status = persistentStatusSnapshot();
      replyTo.send({
        'disposition': result.disposition.name,
        'message': result.message,
        if (status != null) ...status,
      });
    });
  }

  Future<void> initializeForBackgroundAction() async {
    if (_initialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_notification'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      macOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _notifications.initialize(
      settings,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    _initialized = true;
  }

  Future<void> init({void Function(String action)? onAction}) async {
    startBackgroundEntryBridge();
    if (onAction != null) onActionTriggered = onAction;
    if (_initialized) return;
    tz.initializeTimeZones();

    // Android Initialization Settings
    const androidSettings =
        AndroidInitializationSettings('@drawable/ic_notification');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _notifications.initialize(
      settings,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        final actionId = (response.actionId?.isNotEmpty ?? false)
            ? response.actionId!
            : response.payload ?? '';
        debugPrint(
            "🔔 Notification Response Received: actionId='$actionId', payload='${response.payload}'");
        if (actionId.isNotEmpty) {
          if (onActionTriggered != null) {
            onActionTriggered!(actionId);
          } else {
            _pendingAction = actionId;
          }
        }
      },
    );
    _initialized = true;

    final launchDetails =
        await _notifications.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      final response = launchDetails?.notificationResponse;
      final actionId = (response?.actionId?.isNotEmpty ?? false)
          ? response!.actionId!
          : response?.payload ?? '';
      if (actionId.isNotEmpty) {
        final handler = onActionTriggered;
        if (handler != null) {
          handler(actionId);
        } else {
          _pendingAction = actionId;
        }
      }
    }

    // Request Permissions on Android 13+
    final androidImplementation =
        _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
      await androidImplementation.requestExactAlarmsPermission();
    }

    // Auto-sync all persistent reminders on startup
    await syncAllScheduledNotifications();
  }

  // ==================== 🔊 SOUND & CHANNEL CONFIGURATION ====================

  Future<NotificationDetails> _getDetails({
    bool isPersistent = false,
    List<AndroidNotificationAction>? actions,
  }) async {
    Box? prefBox;
    if (Hive.isBoxOpen('preferences')) {
      prefBox = Hive.box('preferences');
    }

    String? customPath = prefBox?.get('custom_ringtone');

    String channelId =
        isPersistent ? 'likhlo_persistent_v1' : 'likhlo_alerts_v1';
    String channelName =
        isPersistent ? 'Quick Ledger Widget' : 'Reminders & Alerts';
    String channelDesc = isPersistent
        ? 'Persistent quick-entry shortcuts in notification bar'
        : 'Expense entry and payment reminders';

    AndroidNotificationSound? sound;

    if (!isPersistent && customPath != null) {
      final file = File(customPath);
      if (file.existsSync()) {
        channelId = 'likhlo_custom_${customPath.hashCode}';
        channelName = 'Custom Tone Alerts';
        String uriPath = customPath.startsWith('file://')
            ? customPath
            : 'file://$customPath';
        sound = UriAndroidNotificationSound(uriPath);
      }
    }

    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDesc,
        importance: isPersistent ? Importance.low : Importance.max,
        priority: isPersistent ? Priority.low : Priority.high,
        ongoing: isPersistent, // Keeps notification pinned in status bar
        autoCancel: !isPersistent,
        playSound: !isPersistent,
        sound: isPersistent ? null : sound,
        enableVibration: !isPersistent,
        actions: actions,
        category: isPersistent
            ? AndroidNotificationCategory.service
            : AndroidNotificationCategory.reminder,
        styleInformation: const BigTextStyleInformation(''),
      ),
      iOS: DarwinNotificationDetails(
        presentSound: !isPersistent,
        presentAlert: true,
        presentBadge: true,
      ),
    );
  }

  // ==================== 📌 1. PERSISTENT STATUS BAR QUICK-LOG WIDGET ====================

  /// Shows or updates an ongoing notification in the notification bar with quick buttons.
  Future<void> updatePersistentStatusBarWidget({
    required double remainingToday,
    required double spentToday,
  }) async {
    try {
      Box? prefBox;
      if (Hive.isBoxOpen('preferences')) {
        prefBox = Hive.box('preferences');
      }
      final bool isEnabled =
          prefBox?.get('persistent_bar_enabled', defaultValue: true) ?? true;

      if (!isEnabled) {
        await cancelNotification(persistentBarId);
        return;
      }

      final details = await _getDetails(
        isPersistent: true,
        actions: const [
          AndroidNotificationAction(
            inlineEntryActionId,
            'Type entry',
            inputs: <AndroidNotificationActionInput>[
              AndroidNotificationActionInput(
                label: 'e.g. 500 biryani from JazzCash',
              ),
            ],
            allowGeneratedReplies: true,
            showsUserInterface: false,
            cancelNotification: false,
          ),
          AndroidNotificationAction(
            'action_voice_log',
            'Voice entry',
            showsUserInterface: true,
            cancelNotification: false,
          ),
        ],
      );

      await _notifications.show(
        persistentBarId,
        'Likhlo Quick Entry',
        'Spent today: Rs. ${spentToday.toStringAsFixed(0)} • Balance: Rs. ${remainingToday.toStringAsFixed(0)}',
        details,
      );
    } catch (e) {
      debugPrint("❌ Error showing Persistent Notification: $e");
    }
  }

  Future<void> setPersistentStatusBarEnabled(bool enabled) async {
    if (Hive.isBoxOpen('preferences')) {
      await Hive.box('preferences').put('persistent_bar_enabled', enabled);
    }
    if (!enabled) {
      await cancelNotification(persistentBarId);
      return;
    }
    if (!_initialized) await init();
    await refreshPersistentStatusBarWidget();
  }

  Future<void> refreshPersistentStatusBarWidget() async {
    final status = persistentStatusSnapshot();
    if (status == null) return;
    await updatePersistentStatusBarWidget(
      remainingToday: status['remainingToday']!,
      spentToday: status['spentToday']!,
    );
  }

  Map<String, double>? persistentStatusSnapshot() {
    if (!Hive.isBoxOpen('expenses') || !Hive.isBoxOpen('wallets')) return null;
    final entries = Hive.box<Expense>('expenses')
        .values
        .where((entry) => entry.deletedAt == null)
        .toList(growable: false);
    final wallets = Hive.box<Wallet>('wallets').values;
    final movements = <String, double>{};
    var spentToday = 0.0;
    final now = DateTime.now();
    for (final entry in entries) {
      movements.update(
        entry.walletId,
        (value) => value +
            (entry.type == 'income' ? entry.amount : -entry.amount),
        ifAbsent: () => entry.type == 'income' ? entry.amount : -entry.amount,
      );
      if (entry.type == 'expense' &&
          entry.category != 'Transfer' &&
          entry.date.year == now.year &&
          entry.date.month == now.month &&
          entry.date.day == now.day) {
        spentToday += entry.amount;
      }
    }
    final totalAvailable = wallets.fold<double>(
      0,
      (sum, wallet) => sum + wallet.balance + (movements[wallet.id] ?? 0),
    );
    return {
      'remainingToday': totalAvailable,
      'spentToday': spentToday,
    };
  }

  // ==================== ⏰ 2. SMART ENTRY REMINDERS ====================

  /// Schedules daily multi-stage reminders to build consistent logging habits.
  Future<void> scheduleSmartEntryReminders() async {
    Box? prefBox;
    if (Hive.isBoxOpen('preferences')) {
      prefBox = Hive.box('preferences');
    }

    final bool remindersEnabled =
        prefBox?.get('daily_reminder_enabled', defaultValue: true) ?? true;
    if (!remindersEnabled) {
      await cancelNotification(middayReminderId);
      await cancelNotification(eveningReminderId);
      await cancelNotification(weekendReviewId);
      return;
    }

    final int eveningHour =
        prefBox?.get('reminder_hour', defaultValue: 20) ?? 20; // Default: 8 PM
    final int eveningMinute =
        prefBox?.get('reminder_minute', defaultValue: 0) ?? 0;

    // 1. Midday Pulse (2:00 PM) - Great for logging lunch, transport, coffee
    await _scheduleDailyRepeating(
      id: middayReminderId,
      title: "Midday Check-in 🍱",
      body: "Did you buy lunch, chai, or fuel today? Tap to record it!",
      hour: 14,
      minute: 0,
      payload: 'action_add_expense',
    );

    // 2. Evening Wrap-Up (User-configured, default 8:00 PM)
    await _scheduleDailyRepeating(
      id: eveningReminderId,
      title: "Daily Spending Wrap-up 🌙",
      body:
          "Close out your daily ledger! Take 5 seconds to review today's expenses.",
      hour: eveningHour,
      minute: eveningMinute,
      payload: 'action_add_expense',
    );

    // Clear the legacy Insights notification because that screen no longer
    // belongs to the streamlined app shell.
    await cancelNotification(weekendReviewId);

    debugPrint("🔔 All smart entry reminders successfully scheduled!");
  }

  // ==================== 🔄 4. PERSISTENCE & SYNC ENGINE ====================

  /// Resynchronizes all alarms from storage (call this in main.dart on startup)
  Future<void> syncAllScheduledNotifications() async {
    try {
      await scheduleSmartEntryReminders();
    } catch (e) {
      debugPrint("⚠️ Sync notification error: $e");
    }
  }

  // ==================== 🛠️ HELPER METHODS ====================

  Future<void> _scheduleDailyRepeating({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    required String payload,
  }) async {
    final details = await _getDetails(
      actions: const [
        AndroidNotificationAction('action_add_expense', '➕ Log Now',
            showsUserInterface: true),
      ],
    );

    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await _notifications.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: payload,
    );
  }

  Future<void> showInstantNotification(String title, String body) async {
    try {
      final details = await _getDetails();
      await _notifications.show(testNotificationId, title, body, details);
    } catch (e) {
      debugPrint("❌ Error Showing Instant Notification: $e");
    }
  }

  Future<void> showNotificationEntryResult(
    NotificationEntryResult result,
  ) async {
    await initializeForBackgroundAction();
    final needsReview =
        result.disposition == NotificationEntryDisposition.review ||
            result.disposition == NotificationEntryDisposition.failed;
    final details = await _getDetails(
      actions: needsReview
          ? const [
              AndroidNotificationAction(
                reviewEntryActionId,
                'Review in Likhlo',
                showsUserInterface: true,
              ),
            ]
          : null,
    );
    await _notifications.show(
      notificationEntryResultId,
      result.disposition == NotificationEntryDisposition.saved
          ? 'Entry saved'
          : result.disposition == NotificationEntryDisposition.duplicate
              ? 'Already handled'
              : 'Review entry',
      result.message,
      details,
      payload: needsReview ? reviewEntryActionId : null,
    );
  }
  // ==================== ⏰ GENERIC SCHEDULING (Used by Udhaar) ====================

  Future<void> scheduleNotification(
      int id, String title, String body, DateTime scheduledTime) async {
    try {
      final details = await _getDetails(); // Uses the updated robust details

      if (scheduledTime.isBefore(DateTime.now())) {
        debugPrint(
            "⚠️ Warning: Schedule time is in the past. Notification skipped.");
        return;
      }

      await _notifications.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledTime, tz.local),
        details,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      debugPrint("⏰ Generic Notification Scheduled for $scheduledTime");
    } catch (e) {
      debugPrint("❌ Error Scheduling Generic Notification: $e");
    }
  }

  Future<void> cancelNotification(int id) async =>
      await _notifications.cancel(id);

  Future<void> cancelAll() async => await _notifications.cancelAll();
}

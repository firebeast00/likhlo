import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:hive/hive.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  // Notification ID Partitioning
  static const int persistentBarId = 700;
  static const int testNotificationId = 888;
  static const int middayReminderId = 901;
  static const int eveningReminderId = 902;
  static const int weekendReviewId = 903;

  /// Callback hook for when notification action buttons are tapped
  Function(String action)? onActionTriggered;

  Future<void> init({Function(String action)? onAction}) async {
    onActionTriggered = onAction;
    tz.initializeTimeZones();

    // Android Initialization Settings
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
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
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        final actionId = response.actionId ?? response.payload ?? '';
        debugPrint("🔔 Notification Response Received: actionId='$actionId', payload='${response.payload}'");
        if (actionId.isNotEmpty && onActionTriggered != null) {
          onActionTriggered!(actionId);
        }
      },
    );

    // Request Permissions on Android 13+
    final androidImplementation = _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
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

    String channelId = isPersistent ? 'likhlo_persistent_v1' : 'likhlo_alerts_v1';
    String channelName = isPersistent ? 'Quick Ledger Widget' : 'Reminders & Alerts';
    String channelDesc = isPersistent
        ? 'Persistent quick-entry shortcuts in notification bar'
        : 'Smart habit nudges and velocity warnings';

    AndroidNotificationSound? sound;

    if (!isPersistent && customPath != null) {
      final file = File(customPath);
      if (file.existsSync()) {
        channelId = 'likhlo_custom_${customPath.hashCode}';
        channelName = 'Custom Tone Alerts';
        String uriPath = customPath.startsWith('file://') ? customPath : 'file://$customPath';
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
        category: isPersistent ? AndroidNotificationCategory.service : AndroidNotificationCategory.reminder,
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
      final bool isEnabled = prefBox?.get('persistent_bar_enabled', defaultValue: true) ?? true;

      if (!isEnabled) {
        await cancelNotification(persistentBarId);
        return;
      }

      final details = await _getDetails(
        isPersistent: true,
        actions: const [
          AndroidNotificationAction(
            'action_add_expense',
            '➕ Log Expense',
            showsUserInterface: true,
            cancelNotification: false,
          ),
          AndroidNotificationAction(
            'action_voice_log',
            '🎙️ Voice Log',
            showsUserInterface: true,
            cancelNotification: false,
          ),
        ],
      );

      await _notifications.show(
        persistentBarId,
        "Likhlo Quick Ledger ⚡",
        "Today's Spend: Rs. ${spentToday.toStringAsFixed(0)} • Remaining: Rs. ${remainingToday.toStringAsFixed(0)}",
        details,
        payload: 'action_add_expense',
      );
    } catch (e) {
      debugPrint("❌ Error showing Persistent Notification: $e");
    }
  }

  // ==================== ⏰ 2. SMART ENTRY REMINDERS ====================

  /// Schedules daily multi-stage reminders to build consistent logging habits.
  Future<void> scheduleSmartEntryReminders() async {
    Box? prefBox;
    if (Hive.isBoxOpen('preferences')) {
      prefBox = Hive.box('preferences');
    }

    final bool remindersEnabled = prefBox?.get('daily_reminder_enabled', defaultValue: true) ?? true;
    if (!remindersEnabled) {
      await cancelNotification(middayReminderId);
      await cancelNotification(eveningReminderId);
      await cancelNotification(weekendReviewId);
      return;
    }

    final int eveningHour = prefBox?.get('reminder_hour', defaultValue: 20) ?? 20; // Default: 8 PM
    final int eveningMinute = prefBox?.get('reminder_minute', defaultValue: 0) ?? 0;

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
      body: "Close out your daily ledger! Take 10 seconds to review today's expenses.",
      hour: eveningHour,
      minute: eveningMinute,
      payload: 'action_add_expense',
    );

    // 3. Weekly Sunday Financial Review (Sundays at 11:00 AM)
    await _scheduleWeeklyRepeating(
      id: weekendReviewId,
      title: "Weekly Financial Health 📊",
      body: "Check your velocity forecast and see where your budget is pacing for next week.",
      dayOfWeek: DateTime.sunday,
      hour: 11,
      minute: 0,
      payload: 'open_insights',
    );

    debugPrint("🔔 All smart entry reminders successfully scheduled!");
  }

  // ==================== ⚡ 3. VELOCITY & BILL DUE ALERTS ====================

  /// Triggered when the Time-Series Engine detects an overspending spike
  Future<void> showVelocitySpikeAlert({
    required double currentBurnRate,
    required double suggestedCut,
  }) async {
    try {
      final details = await _getDetails();
      await _notifications.show(
        904,
        "⚠️ Spending Velocity Alert!",
        "Your burn rate spiked to Rs. ${currentBurnRate.toStringAsFixed(0)}/day. Cut Rs. ${suggestedCut.toStringAsFixed(0)}/day to stay on track.",
        details,
        payload: 'open_insights',
      );
    } catch (e) {
      debugPrint("❌ Error showing velocity alert: $e");
    }
  }

  /// Scheduled for recurring bills or debt deadlines
  Future<void> scheduleBillReminder({
    required int id,
    required String title,
    required double amount,
    required DateTime dueDate,
  }) async {
    try {
      final scheduledDate = dueDate.subtract(const Duration(days: 1)); // 1 day before
      if (scheduledDate.isBefore(DateTime.now())) return;

      final details = await _getDetails();

      await _notifications.zonedSchedule(
        id,
        "Bill Due Tomorrow 🗓️",
        "$title (Rs. ${amount.toStringAsFixed(0)}) is due tomorrow. Plan your cash flow!",
        tz.TZDateTime.from(scheduledDate, tz.local),
        details,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'open_bills',
      );
    } catch (e) {
      debugPrint("❌ Error scheduling bill reminder: $e");
    }
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
        AndroidNotificationAction('action_add_expense', '➕ Log Now', showsUserInterface: true),
      ],
    );

    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

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
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: payload,
    );
  }

  Future<void> _scheduleWeeklyRepeating({
    required int id,
    required String title,
    required String body,
    required int dayOfWeek,
    required int hour,
    required int minute,
    required String payload,
  }) async {
    final details = await _getDetails();
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

    while (scheduledDate.weekday != dayOfWeek || scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await _notifications.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
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
  // ==================== ⏰ GENERIC SCHEDULING (Used by Tasks & Udhaar) ====================

  Future<void> scheduleNotification(int id, String title, String body, DateTime scheduledTime) async {
    try {
      final details = await _getDetails(); // Uses the updated robust details

      if (scheduledTime.isBefore(DateTime.now())) {
        debugPrint("⚠️ Warning: Schedule time is in the past. Notification skipped.");
        return;
      }

      await _notifications.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledTime, tz.local),
        details,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      debugPrint("⏰ Generic Notification Scheduled for $scheduledTime");
    } catch (e) {
      debugPrint("❌ Error Scheduling Generic Notification: $e");
    }
  }

  Future<void> cancelNotification(int id) async => await _notifications.cancel(id);

  Future<void> cancelAll() async => await _notifications.cancelAll();
}
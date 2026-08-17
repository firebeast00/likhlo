import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:hive/hive.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz.initializeTimeZones();

    // Android Init
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(); // iOS Support

    const settings = InitializationSettings(android: androidSettings, iOS: darwinSettings, macOS: darwinSettings);

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) async {
        print("🔔 Notification Clicked: ${response.payload}");
      },
    );

    // 🚀 ASK PERMISSIONS
    final androidImplementation = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
      await androidImplementation.requestExactAlarmsPermission();
    }
  }

  // ✅ FIXED: Robust Sound Logic
  Future<NotificationDetails> _getDetails() async {
    final box = Hive.box('preferences');
    String? path = box.get('custom_ringtone');

    // Default Config
    String channelId = 'likhlo_default_v1';
    String channelName = 'Default Notifications';
    AndroidNotificationSound? sound; // Base class (can be Raw or Uri)

    // Check if Custom File Exists
    if (path != null) {
      final file = File(path);
      if (file.existsSync()) {
        // 🔔 CRITICAL FIX: Android needs a new Channel ID for every new sound.
        // We use the file path's hash to guarantee a unique ID for this specific song.
        channelId = 'likhlo_custom_${path.hashCode}';
        channelName = 'Custom Ringtone';

        // 🔔 CRITICAL FIX: Ensure URI format starts with 'file://'
        String uriPath = path.startsWith('file://') ? path : 'file://$path';
        sound = UriAndroidNotificationSound(uriPath);

        print("🎵 Using Custom Sound: $uriPath");
      } else {
        print("⚠️ Custom sound file not found at $path. Reverting to default.");
      }
    }

    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        sound: sound, // Null = System Default
        enableVibration: true,

        // ✅ CRITICAL FIX: Audio Attributes ensure it plays as a Notification
        audioAttributesUsage: AudioAttributesUsage.notification,
        category: AndroidNotificationCategory.alarm,

        // Visuals
        styleInformation: const BigTextStyleInformation(''),
      ),
      iOS: const DarwinNotificationDetails(
        presentSound: true,
        presentAlert: true,
        presentBadge: true,
      ),
    );
  }

  Future<void> showInstantNotification(String title, String body) async {
    try {
      final details = await _getDetails();
      // Using ID 888 for Test Notifications so they don't overlap real ones
      await _notifications.show(888, title, body, details);
      print("✅ Notification Sent: $title");
    } catch (e) {
      print("❌ Error Showing Notification: $e");
    }
  }
  Future<void> scheduleDailyReminder() async {
    try {
      final details = await _getDetails();

      // Calculate next 8:00 PM
      final now = tz.TZDateTime.now(tz.local);
      var scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, 20, 0);

      // If it's already past 8:00 PM today, schedule for tomorrow
      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      await _notifications.zonedSchedule(
        999, // Static ID so it doesn't duplicate
        "Daily Check-in 💸",
        "What did you spend today? Tap to log it quickly.",
        scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time, // Repeats daily at this time
      );
      print("🔔 Daily 8 PM Reminder scheduled!");
    } catch (e) {
      print("🔔 Error scheduling daily reminder: $e");
    }
  }

  Future<void> scheduleNotification(int id, String title, String body, DateTime scheduledTime) async {
    try {
      final details = await _getDetails();

      if (scheduledTime.isBefore(DateTime.now())) {
        print("⚠️ Warning: Schedule time is in the past. Notification skipped.");
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
      print("⏰ Notification Scheduled for $scheduledTime");
    } catch (e) {
      print("❌ Error Scheduling Notification: $e");
    }
  }

  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }
  // ✅ NEW: 8:00 PM Daily Reminder

}
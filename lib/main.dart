import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:student_expense_manager/screens/splash_screen.dart';

// Models
import 'models/expense_model.dart';
import 'models/todo_model.dart';
import 'models/debt_model.dart';
import 'models/settings_model.dart';
import 'models/goal_model.dart';

// services
import "./services/notification_service.dart";

// Providers
import 'providers/settings_provider.dart';

// Screens
import 'models/recurring_bill_model.dart';
import 'models/mess_entry_model.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? startupError;

  try {
    await Hive.initFlutter();

    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ExpenseAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ToDoItemAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(DebtEntryAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(AppSettingsAdapter());
    if (!Hive.isAdapterRegistered(5)) Hive.registerAdapter(SmartGoalAdapter());
    if (!Hive.isAdapterRegistered(6)) {
      Hive.registerAdapter(RecurringBillAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(MessEntryAdapter());

    await Future.wait([
      Hive.openBox<Expense>('expenses'),
      Hive.openBox<ToDoItem>('todos'),
      Hive.openBox<DebtEntry>('debts'),
      Hive.openBox('settings'),
      Hive.openBox('preferences'),
      Hive.openBox<SmartGoal>('goals'),
      Hive.openBox<RecurringBill>('recurring_bills'),
      Hive.openBox<MessEntry>('mess_khata'),
    ]);
  } catch (error) {
    startupError = error;
  }

  if (startupError == null) {
    try {
      await NotificationService().init();
      await NotificationService().scheduleDailyReminder();
    } catch (error) {
      debugPrint('Notification initialization failed: $error');
    }
  }

  runApp(
    ProviderScope(
      child: startupError == null
          ? const LikhloApp()
          : StartupFailureApp(error: startupError),
    ),
  );
}

class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({required this.error, super.key});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.storage_rounded,
                      size: 56, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    'Likhlo could not open its local data',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Close and reopen the app. Your existing data has not been deleted.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    error.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LikhloApp extends ConsumerWidget {
  const LikhloApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final primaryColor = Color(settings.profileColorValue);

    // 👇 DYNAMIC THEME TINTING: Mix your active theme color into the dark background and cards
    final Color darkScaffoldBg = Color.lerp(const Color(0xFF05070B), primaryColor, 0.10)!;
    final Color darkCardBg = Color.lerp(const Color(0xFF0E1422), primaryColor, 0.18)!;

    final prefsBox = Hive.box('preferences');
    final bool hasOnboarded = prefsBox.get('has_onboarded', defaultValue: false);

    return MaterialApp(
      title: 'Likhlo',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode == 'system'
          ? ThemeMode.system
          : (settings.themeMode == 'dark' ? ThemeMode.dark : ThemeMode.light),

      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: primaryColor, brightness: Brightness.light),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.dark(primary: primaryColor, secondary: primaryColor, surface: darkScaffoldBg, onSurface: Colors.white),
        scaffoldBackgroundColor: darkScaffoldBg,
        cardColor: darkCardBg,
        dialogBackgroundColor: darkCardBg,
        dividerColor: primaryColor.withOpacity(0.15),
      ),

      // 🚀 THE FIX: THIS ACTUALLY DIMS THE ENTIRE APP!
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            // Draws a black screen over the app based on the brightness level
            if (settings.brightnessLevel > 0)
              IgnorePointer(
                child: Container(
                  color: Colors.black.withOpacity(settings.brightnessLevel),
                ),
              ),
          ],
        );
      },

      home: const SplashScreen(),
    );
  }
}
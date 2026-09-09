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
import 'models/recurring_bill_model.dart';
import 'models/mess_entry_model.dart';
import "models/wallet_model.dart";

// Services
import "./services/notification_service.dart";

// Providers
import 'providers/settings_provider.dart';




void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Hive.initFlutter();

    // Register Adapters
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ExpenseAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ToDoItemAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(DebtEntryAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(AppSettingsAdapter());
    if (!Hive.isAdapterRegistered(5)) Hive.registerAdapter(SmartGoalAdapter());
    if (!Hive.isAdapterRegistered(6)) Hive.registerAdapter(RecurringBillAdapter());
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(MessEntryAdapter());
    if (!Hive.isAdapterRegistered(8)) Hive.registerAdapter(WalletAdapter()); // 🚀 ADDED (TypeId 8)

    await Future.wait([
      Hive.openBox<Expense>('expenses'),
      Hive.openBox<ToDoItem>('todos'),
      Hive.openBox<DebtEntry>('debts'),
      Hive.openBox('settings'),
      Hive.openBox('preferences'),
      Hive.openBox<SmartGoal>('goals'),
      Hive.openBox<RecurringBill>('recurring_bills'),
      Hive.openBox<MessEntry>('mess_khata'),
      Hive.openBox<Wallet>('wallets'),
    ]);

    await NotificationService().init();
    await NotificationService().scheduleSmartEntryReminders();

  } catch (e) {
    print("Hive Initialization Error: $e");
  }

  runApp(const ProviderScope(child: LikhloApp()));
}

class LikhloApp extends ConsumerWidget {
  const LikhloApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final primaryColor = Color(settings.profileColorValue);

    // DYNAMIC THEME TINTING: Mix your active theme color into the dark background and cards
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
        colorScheme: ColorScheme.dark(
            primary: primaryColor,
            secondary: primaryColor,
            surface: darkScaffoldBg,
            onSurface: Colors.white),
        scaffoldBackgroundColor: darkScaffoldBg,
        cardColor: darkCardBg,
        dialogBackgroundColor: darkCardBg,
        dividerColor: primaryColor.withOpacity(0.15),
      ),

      // 🚀 THE BUILDER: Handles Global Overlays (Dimmer & AI Chat)
      builder: (context, child) {
        // Wrapped in Directionality to ensure text renders safely over all routes
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              // 1. The main app content (Navigators, Screens, etc.)
              if (child != null) child,

              // 3. 🌙 SCREEN DIMMER
              // Draws a black screen over the app based on the brightness level
              if (settings.brightnessLevel > 0)
                IgnorePointer(
                  child: Container(
                    color: Colors.black.withOpacity(settings.brightnessLevel),
                  ),
                ),
            ],
          ),
        );
      },

      home: const SplashScreen(),
    );
  }
}
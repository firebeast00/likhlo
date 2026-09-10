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

  Object? storageError;
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

  } catch (e) {
    storageError = e;
    debugPrint("Hive Initialization Error: $e");
  }

  if (storageError == null) {
    try {
      await NotificationService().init();
    } catch (e) {
      debugPrint("Notification Initialization Error: $e");
    }
  }

  runApp(
    ProviderScope(
      child: LikhloApp(startupError: storageError?.toString()),
    ),
  );
}

class LikhloApp extends ConsumerWidget {
  final String? startupError;

  const LikhloApp({super.key, this.startupError});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (startupError != null) {
      return MaterialApp(
        title: 'Likhlo',
        debugShowCheckedModeBanner: false,
        home: StartupRecoveryScreen(details: startupError!),
      );
    }

    final settings = ref.watch(settingsProvider);
    final primaryColor = Color(settings.profileColorValue);

    // DYNAMIC THEME TINTING: Mix your active theme color into the dark background and cards
    final Color darkScaffoldBg = Color.lerp(const Color(0xFF05070B), primaryColor, 0.10)!;
    final Color darkCardBg = Color.lerp(const Color(0xFF0E1422), primaryColor, 0.18)!;

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

class StartupRecoveryScreen extends StatelessWidget {
  final String details;

  const StartupRecoveryScreen({super.key, required this.details});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.storage_rounded, size: 64, color: Colors.orange),
              const SizedBox(height: 20),
              const Text(
                'Likhlo could not open local storage',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Your data has not been deleted. Close and reopen the app. If the problem continues, back up the app data before reinstalling.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => SystemNavigator.pop(),
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Close and restart'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

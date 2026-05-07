import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/splash_screen.dart';
import "screens/fyp_prototype_screen.dart";
import 'models/expense_model.dart';
import 'models/todo_model.dart';
import 'models/debt_model.dart';
import 'models/settings_model.dart';
import 'providers/settings_provider.dart';



void main() async {
  // 1. Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // 2. Initialize Storage
    await Hive.initFlutter();

    // Register Adapters
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ExpenseAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ToDoItemAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(DebtEntryAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(AppSettingsAdapter());

    // Open Boxes
    await Hive.openBox<Expense>('expenses');
    await Hive.openBox<ToDoItem>('todos');
    await Hive.openBox<DebtEntry>('debts');
    await Hive.openBox<AppSettings>('settings');
    await Hive.openBox('preferences');
  } catch (e) {
    print("Hive Initialization Error: $e");
    // App will still launch even if old data is corrupted
  }

  try {
    // 3. Initialize Notifications separately so it doesn't crash the app if it fails
    //await NotificationService().init();
  } catch (e) {
    print("Notification Service Error: $e");
  }

  // 4. Run the app
  runApp(const ProviderScope(child: LikhloApp()));
}
class LikhloApp extends ConsumerWidget {
  const LikhloApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1. Now we CAN watch settings because Hive boxes are opened in main()
    final settings = ref.watch(settingsProvider);
    final primaryColor = Color(settings.profileColorValue);

    return MaterialApp(
      title: 'Likhlo',
      debugShowCheckedModeBanner: false,

      // 2. Dynamically set the Theme Mode
      themeMode: settings.themeMode == 'system'
          ? ThemeMode.system
          : (settings.themeMode == 'dark' ? ThemeMode.dark : ThemeMode.light),

      // 3. Define the Light Theme
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: primaryColor, brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        cardColor: Colors.white,
      ),

      // 4. Define the Dark Theme
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.dark(
          primary: primaryColor,
          surface: const Color(0xFF1E293B),
          background: const Color(0xFF0F172A),
        ),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        cardColor: const Color(0xFF1E293B),
        dialogBackgroundColor: const Color(0xFF1E293B),
      ),
      home: const FypPrototypeScreen(),
    );
  }
}
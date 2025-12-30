import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/splash_screen.dart';
import 'models/expense_model.dart';
import 'models/todo_model.dart';
import 'models/debt_model.dart';
import 'models/settings_model.dart';
import 'providers/settings_provider.dart';

void main() async {
  // 1. Minimal Setup
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Only init Hive system (Fast), don't open boxes yet
  await Hive.initFlutter();

  // 3. Register Adapters (Fast)
  try {
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ExpenseAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ToDoItemAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(DebtEntryAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(AppSettingsAdapter());
  } catch (e) { print(e); }

  // 4. 🚀 LAUNCH APP IMMEDIATELY (Fixes Black Screen)
  runApp(const ProviderScope(child: LikhloApp()));
}

class LikhloApp extends ConsumerWidget {
  const LikhloApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // We can't watch settings yet because the box isn't open.
    // Use a default theme for the Splash Screen, then switch when loaded.

    return MaterialApp(
      title: 'Likhlo',
      debugShowCheckedModeBanner: false,
      // Default theme for Splash Screen (Deep Blue to match logo)
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        primaryColor: const Color(0xFF2563EB),
        useMaterial3: true,
      ),
      home: const SplashScreen(), // Logic moved here
    );
  }
}
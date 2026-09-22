import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:student_expense_manager/screens/home_screen.dart';
import 'package:student_expense_manager/screens/onboarding_screen.dart';

// Models
import 'models/expense_model.dart';
import 'models/debt_model.dart';
import 'models/mess_entry_model.dart';
import "models/wallet_model.dart";
import 'models/workspace_model.dart';

// Services
import "./services/notification_service.dart";

// Providers
import 'providers/settings_provider.dart';
import 'widgets/app_lock_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Object? storageError;
  try {
    await Hive.initFlutter();

    // Register Adapters
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ExpenseAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(DebtEntryAdapter());
    // Read-only compatibility for older encrypted backups. The removed Mess
    // feature is not opened during normal startup.
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(MessEntryAdapter());
    if (!Hive.isAdapterRegistered(8)) {
      Hive.registerAdapter(WalletAdapter()); // 🚀 ADDED (TypeId 8)
    }
    if (!Hive.isAdapterRegistered(9)) {
      Hive.registerAdapter(WorkspaceAdapter());
    }

    await Future.wait([
      Hive.openBox<Expense>('expenses'),
      Hive.openBox('settings'),
      Hive.openBox('preferences'),
      Hive.openBox<Wallet>('wallets'),
      Hive.openBox<Workspace>('workspaces'),
    ]);
  } catch (e) {
    storageError = e;
    debugPrint("Hive Initialization Error: $e");
  }

  runApp(
    ProviderScope(
      child: LikhloApp(startupError: storageError?.toString()),
    ),
  );

  // Keep the first frame independent from notification plug-in work. The
  // native splash remains visible only while essential local storage opens.
  if (storageError == null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 1200), () async {
        try {
          await NotificationService().init();
        } catch (e) {
          debugPrint("Notification Initialization Error: $e");
        }
      });
    });
  }
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

    final themeSettings = ref.watch(
      settingsProvider.select(
        (settings) => (settings.themeMode, settings.profileColorValue),
      ),
    );
    final themeMode = themeSettings.$1;
    final primaryColor = Color(themeSettings.$2);

    // DYNAMIC THEME TINTING: Mix your active theme color into the dark background and cards
    final Color darkScaffoldBg =
        Color.lerp(const Color(0xFF05070B), primaryColor, 0.10)!;
    final Color darkCardBg =
        Color.lerp(const Color(0xFF0E1422), primaryColor, 0.18)!;

    return MaterialApp(
      title: 'Likhlo',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const _LikhloScrollBehavior(),
      themeAnimationDuration: Duration.zero,
      themeMode: themeMode == 'system'
          ? ThemeMode.system
          : (themeMode == 'dark' ? ThemeMode.dark : ThemeMode.light),

      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
            seedColor: primaryColor, brightness: Brightness.light),
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
        dialogTheme: DialogThemeData(backgroundColor: darkCardBg),
        dividerColor: primaryColor.withValues(alpha: 0.15),
      ),

      // 🚀 THE BUILDER: Handles Global Overlays (Dimmer & AI Chat)
      builder: (context, child) {
        return Actions(
          actions: <Type, Action<Intent>>{
            EditableTextTapOutsideIntent:
                CallbackAction<EditableTextTapOutsideIntent>(
              onInvoke: (intent) {
                intent.focusNode.unfocus();
                return null;
              },
            ),
          },
          child: AppLockGate(
            child: _AppContentWithDimmer(
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },

      home: (Hive.box('preferences').get('has_onboarded', defaultValue: false)
              as bool)
          ? const HomeScreen()
          : const OnboardingScreen(),
    );
  }
}

class _LikhloScrollBehavior extends MaterialScrollBehavior {
  const _LikhloScrollBehavior();

  @override
  ScrollViewKeyboardDismissBehavior getKeyboardDismissBehavior(
    BuildContext context,
  ) {
    return ScrollViewKeyboardDismissBehavior.onDrag;
  }
}

class _AppContentWithDimmer extends ConsumerWidget {
  final Widget child;

  const _AppContentWithDimmer({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightnessLevel = ref.watch(
      settingsProvider.select((settings) => settings.brightnessLevel),
    );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          child,
          if (brightnessLevel > 0)
            IgnorePointer(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: brightnessLevel),
                child: const SizedBox.expand(),
              ),
            ),
        ],
      ),
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

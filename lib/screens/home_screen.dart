import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import "../services/notification_service.dart";
import '../services/notification_entry_service.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/category_provider.dart';
import '../providers/wallet_provider.dart';
import '../providers/workspace_provider.dart';
import '../models/expense_model.dart';
import '../models/debt_model.dart';
import '../models/mess_entry_model.dart';
import '../models/wallet_model.dart';
import '../widgets/app_drawer.dart';
import 'debt_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'about_screen.dart';
import '../services/local_nlp_service.dart';
import '../services/ocr_scanner_service.dart';
import '../services/speech_session_controller.dart';
import '../services/transaction_executor.dart';
import '../services/smart_command.dart';
import '../services/smart_input_engine.dart';
import '../services/confidence_evaluator.dart';
import '../services/speech_recognition_provider.dart';
import '../services/speech_command_completeness.dart';
import '../services/transaction_title_policy.dart';
import "./mess_khata_screen.dart";
import './income_accounts_screen.dart';
import './trash_screen.dart';
import './receipt_review_screen.dart';
import './workspaces_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin {
  static const platform = MethodChannel('com.likhlo/quick_tile');
  static const _smartEntryDefaultAccountKey =
      'smart_entry_default_wallet_id';
  static const _homeVisibleWalletsKey = 'home_visible_wallet_ids_v1';
  static const _smartEntryLearningKey = 'smart_entry_learning_v1';
  static const _dashboardViews = ['Dashboard', 'Udhaar', 'Mess Khata'];
  String _currentView = 'Dashboard';
  final PageController _dashboardPageController = PageController();
  bool _dashboardBoxesReady = false;
  DateTime _focusedMonth = DateTime.now();
  String _selectedCategoryTab = 'All';
  bool _isSearching = false;
  String _searchQuery = "";
  String? _smartEntryTypeFilter;
  SmartEntryTimeRange? _smartEntrySearchRange;
  bool _smartEntrySearchAllHistory = false;
  final ScrollController _categoryScrollCtrl = ScrollController();

  late AnimationController _fabController;
  late Animation<double> _fabScale;

  final SpeechRecognitionProvider _speech = SpeechProviderRouter(
    deviceProvider: DeviceSpeechRecognitionProvider(),
  );
  static const _speechPauseWindow = Duration(milliseconds: 2500);
  static const _speechStabilityWindow = Duration(milliseconds: 450);
  static const _speechSessionLimit = Duration(seconds: 20);
  static const _speechStartupGrace = Duration(milliseconds: 1200);
  static const _prematureSpeechStatusGuard = Duration(milliseconds: 600);
  final SpeechSessionController _speechSession =
  SpeechSessionController(maxRetries: 2);
  final SmartInputEngine _smartInputEngine = SmartInputEngine();
  final SpeechCommandCompletenessEvaluator _speechCompletenessEvaluator =
  const SpeechCommandCompletenessEvaluator();
  bool _isListening = false;
  bool _handlingSpeechError = false;
  bool _restartingSpeech = false;
  bool _speechInitialized = false;
  bool _speechLocalesLoaded = false;
  List<String?> _speechLocaleCandidates = const [null];
  int _speechLocaleCandidateIndex = 0;
  bool _isScanningReceipt = false;
  final TextEditingController _smartInputCtrl = TextEditingController();
  String? _smartEntryDefaultWalletId;
  List<String> _homeVisibleWalletIds = const [];
  final Map<String, _LearnedSmartEntryPreference>
  _learnedSmartEntryPreferences = {};
  Timer? _notificationUpdateTimer;
  Timer? _messageTimer;
  Timer? _speechStabilityTimer;
  Timer? _speechDeadlineTimer;
  Timer? _speechStartupTimer;
  DateTime? _speechListenStartedAt;
  bool _recognizerReportedListening = false;
  bool _finalizingRecognizerStop = false;
  OverlayEntry? _activeMessageEntry;

  @override
  void initState() {
    super.initState();
    final storedSmartEntryWallet =
    Hive.box('preferences').get(_smartEntryDefaultAccountKey);
    _smartEntryDefaultWalletId = storedSmartEntryWallet is String &&
        storedSmartEntryWallet.trim().isNotEmpty
        ? storedSmartEntryWallet
        : null;
    final storedHomeWallets =
    Hive.box('preferences').get(_homeVisibleWalletsKey);
    _homeVisibleWalletIds = storedHomeWallets is List
        ? storedHomeWallets
        .whereType<String>()
        .where((id) => id.trim().isNotEmpty)
        .take(4)
        .toList(growable: false)
        : const [];
    _loadSmartEntryLearning();
    _fabController = AnimationController(vsync: this, duration: const Duration(milliseconds: 200), lowerBound: 0.0, upperBound: 0.1);
    _fabScale = Tween<double>(begin: 1.0, end: 0.95).animate(_fabController);

    const QuickActions quickActions = QuickActions();
    quickActions.initialize((String shortcutType) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (shortcutType == 'action_voice_log') {
          _listenForExpense();
        } else if (shortcutType == 'action_add_expense') {
          _showAddOrEditModal();
        }
      });
    });

    quickActions.setShortcutItems(<ShortcutItem>[
      const ShortcutItem(type: 'action_voice_log', localizedTitle: 'Voice Log', icon: 'ic_mic'),
      const ShortcutItem(type: 'action_add_expense', localizedTitle: 'Add Transaction', icon: 'ic_add'),
    ]);
    _setupNativeQuickTile();
    unawaited(_prepareDashboardBoxes());

    NotificationService().onActionTriggered = _handleNotificationAction;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pendingAction = NotificationService().takePendingAction();
      if (pendingAction != null) _handleNotificationAction(pendingAction);

      _queuePersistentNotificationUpdate(
        delay: const Duration(seconds: 2),
      );
      final workspaceState = ref.read(workspaceProvider);
      final customIndex = workspaceState.workspaces
          .where((workspace) => !workspace.isDefault)
          .toList()
          .indexWhere((workspace) => workspace.id == workspaceState.selectedId);
      if (customIndex >= 0 && _dashboardPageController.hasClients) {
        _dashboardPageController.jumpToPage(customIndex + 3);
      }
    });
  }

  void _handleNotificationAction(String action) {
    if (!mounted) return;
    if (action == 'action_voice_log') {
      _showNotificationVoiceEntrySheet();
    } else if (action == 'action_add_expense') {
      _showAddOrEditModal();
    } else if (action == NotificationService.reviewEntryActionId) {
      _reviewPendingNotificationEntry();
    }
  }

  Future<void> _reviewPendingNotificationEntry() async {
    final stored = Hive.box('preferences').get(
      NotificationEntryService.pendingReviewKey,
    );
    final text = stored is Map ? stored['text']?.toString().trim() : null;
    if (text == null || text.isEmpty) {
      _showTransactionInfo(
        'There is no notification entry waiting for review.',
        title: 'Nothing to review',
      );
      return;
    }
    _smartInputCtrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    final saved =
        await _processNLP(text, source: SmartInputSource.notification);
    if (saved && Hive.isBoxOpen('preferences')) {
      await Hive.box('preferences').delete(
        NotificationEntryService.pendingReviewKey,
      );
    }
  }

  Future<void> _showNotificationVoiceEntrySheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Voice entry',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'Speak one complete expense or income. Your transcript stays here if recognition or saving fails.',
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _smartInputCtrl,
              builder: (_, value, __) => TextField(
                controller: _smartInputCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: _isListening ? 'Listening…' : 'Voice transcript',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _listenForExpense,
                    icon: const Icon(Icons.mic_rounded),
                    label: const Text('Speak'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _setupNativeQuickTile() {
    platform.invokeMethod<String>('getQuickAction').then((action) {
      if (action == 'add_expense') {
        Future.delayed(const Duration(milliseconds: 500), () => _showAddOrEditModal());
      }
    }).catchError((Object error) {
      debugPrint("Quick Tile Error: $error");
      return null;
    });

    platform.setMethodCallHandler((call) async {
      if (call.method == 'triggerAction' && call.arguments == 'add_expense') {
        _showAddOrEditModal();
      }
    });
  }

  @override
  void dispose() {
    NotificationService().onActionTriggered = null;
    _speech.cancel();
    _fabController.dispose();
    _notificationUpdateTimer?.cancel();
    _messageTimer?.cancel();
    _speechStabilityTimer?.cancel();
    _speechDeadlineTimer?.cancel();
    _speechStartupTimer?.cancel();
    _activeMessageEntry?.remove();
    _activeMessageEntry = null;
    _categoryScrollCtrl.dispose();
    _dashboardPageController.dispose();
    _smartInputCtrl.dispose();
    super.dispose();
  }

  Future<void> _prepareDashboardBoxes() async {
    try {
      if (!Hive.isBoxOpen('debts')) {
        await Hive.openBox<DebtEntry>('debts');
      }
      if (!Hive.isBoxOpen('mess_khata')) {
        await Hive.openBox<MessEntry>('mess_khata');
      }
      if (mounted) setState(() => _dashboardBoxesReady = true);
    } catch (error) {
      if (mounted) {
        _showTransactionError(
          'Udhaar and Mess Khata could not be opened. Your main ledger is still available.',
          title: 'Dashboard pages unavailable',
        );
      }
    }
  }

  void _queuePersistentNotificationUpdate({
    Duration delay = const Duration(milliseconds: 350),
  }) {
    _notificationUpdateTimer?.cancel();
    _notificationUpdateTimer = Timer(delay, () {
      if (!mounted) return;
      final now = DateTime.now();
      final expenses = ref.read(expenseProvider).allExpenses;
      final wallets = ref.read(walletProvider);
      final walletNotifier = ref.read(walletProvider.notifier);

      final totalAvailable = wallets.fold<double>(
        0,
            (sum, wallet) => sum + walletNotifier.getBalanceForWallet(wallet.id),
      );

      double spentToday = 0;
      for (final entry in expenses) {
        if (entry.category == 'Transfer') continue;
        if (entry.type == 'expense' &&
            entry.date.year == now.year &&
            entry.date.month == now.month &&
            entry.date.day == now.day) {
          spentToday += entry.amount;
        }
      }

      NotificationService().updatePersistentStatusBarWidget(
        remainingToday: totalAvailable,
        spentToday: spentToday,
      );
    });
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _loadSmartEntryLearning() {
    final stored = Hive.box('preferences').get(_smartEntryLearningKey);
    if (stored is! Map) return;
    for (final item in stored.entries) {
      final key = item.key?.toString() ?? '';
      final preference = _LearnedSmartEntryPreference.fromStored(item.value);
      if (key.isNotEmpty && preference != null) {
        _learnedSmartEntryPreferences[key] = preference;
      }
    }
  }

  _LearnedSmartEntryPreference? _learnedPreferenceFor(String title) {
    final key = _normalizeLearningTitle(title);
    if (key.isEmpty) return null;
    return _learnedSmartEntryPreferences[key];
  }

  Future<void> _rememberSmartEntryPreference(Expense entry) async {
    if (entry.category == 'Transfer') return;
    final key = _normalizeLearningTitle(entry.title);
    if (key.isEmpty) return;

    final existing = _learnedSmartEntryPreferences[key];
    _learnedSmartEntryPreferences[key] = _LearnedSmartEntryPreference(
      category: entry.category,
      walletId: entry.walletId,
      uses: (existing?.uses ?? 0) + 1,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    if (_learnedSmartEntryPreferences.length > 200) {
      final oldest = _learnedSmartEntryPreferences.entries.reduce(
            (first, second) => first.value.updatedAt <= second.value.updatedAt
            ? first
            : second,
      );
      _learnedSmartEntryPreferences.remove(oldest.key);
    }

    try {
      await Hive.box('preferences').put(
        _smartEntryLearningKey,
        {
          for (final item in _learnedSmartEntryPreferences.entries)
            item.key: item.value.toStored(),
        },
      );
    } catch (error) {
      debugPrint('Smart Entry learning could not be saved: $error');
    }
  }

  Future<void> _refreshSmartEntryReminders() async {
    try {
      await NotificationService().scheduleSmartEntryReminders();
    } catch (error) {
      debugPrint('Notification reset failed: $error');
    }
  }

  void _selectCategory(String category, int index) {
    _dismissKeyboard();
    setState(() => _selectedCategoryTab = category);
    double offset = (index * 70.0) - (MediaQuery.of(context).size.width / 2) + 35;
    if (offset < 0) offset = 0;
    if (_categoryScrollCtrl.hasClients) {
      _categoryScrollCtrl.animateTo(offset, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  Future<void> _changeView(String view) async {
    _dismissKeyboard();
    if (!mounted || view == _currentView) return;

    try {
      if (view == 'Mess Khata' && !Hive.isBoxOpen('mess_khata')) {
        await Hive.openBox<MessEntry>('mess_khata');
      } else if (view == 'Udhaar' && !Hive.isBoxOpen('debts')) {
        await Hive.openBox<DebtEntry>('debts');
      }
    } catch (error) {
      if (mounted) {
        _showTransactionError('Could not open $view. Please try again.');
      }
      return;
    }

    if (!mounted) return;
    var dashboardIndex = _dashboardViews.indexOf(view);
    if (view == 'Dashboard') {
      final workspaceState = ref.read(workspaceProvider);
      final customIndex = workspaceState.workspaces
          .where((workspace) => !workspace.isDefault)
          .toList()
          .indexWhere((workspace) => workspace.id == workspaceState.selectedId);
      if (customIndex >= 0) dashboardIndex = customIndex + 3;
    }
    setState(() {
      _currentView = view;
      _isSearching = false;
      _searchQuery = '';
      _smartEntryTypeFilter = null;
      _smartEntrySearchRange = null;
      _smartEntrySearchAllHistory = false;
    });

    if (dashboardIndex >= 0 && _dashboardPageController.hasClients) {
      await _dashboardPageController.animateToPage(
        dashboardIndex,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }

    if (view == 'Dashboard') _queuePersistentNotificationUpdate();
  }

  void _onDashboardPageChanged(int index) {
    if (!mounted || index < 0) return;
    final workspaceState = ref.read(workspaceProvider);
    final customWorkspaces = workspaceState.workspaces
        .where((workspace) => !workspace.isDefault)
        .toList();
    if (index >= 3) {
      final customIndex = index - 3;
      if (customIndex >= customWorkspaces.length) return;
      unawaited(
        ref.read(workspaceProvider.notifier).select(
              customWorkspaces[customIndex].id,
            ),
      );
    } else if (index == 0) {
      unawaited(ref.read(workspaceProvider.notifier).select('personal'));
    }
    final view = index >= 3 ? 'Dashboard' : _dashboardViews[index];
    setState(() {
      _currentView = view;
      _isSearching = false;
      _searchQuery = '';
    });
    if (view == 'Dashboard') _queuePersistentNotificationUpdate();
  }

  void _showAddCategoryDialog() {
    _dismissKeyboard();
    final catCtrl = TextEditingController();
    final primaryColor = Color(ref.read(settingsProvider).profileColorValue);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: primaryColor.withValues(alpha: 0.15), shape: BoxShape.circle), child: Icon(Icons.category_rounded, color: primaryColor, size: 20)),
            const SizedBox(width: 12),
            const Expanded(child: Text("New Category", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ],
        ),
        content: _buildModernInput(catCtrl, "Category Name", Icons.new_label_rounded, primaryColor),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel", style: TextStyle(color: Colors.grey)))),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 12)),
                  onPressed: () {
                    if (catCtrl.text.trim().isNotEmpty) {
                      final added = ref
                          .read(categoryProvider.notifier)
                          .addCategory(catCtrl.text.trim());
                      if (!added) {
                        _showTransactionError(
                          'Choose a different name for this category.',
                          title: 'Category already exists',
                        );
                        return;
                      }
                      Navigator.pop(ctx);
                      Future.delayed(const Duration(milliseconds: 300), () {
                        if (_categoryScrollCtrl.hasClients) {
                          _categoryScrollCtrl.animateTo(_categoryScrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                        }
                      });
                    }
                  },
                  child: const Text("Save"),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Future<void> _confirmDeleteCategory(String category) async {
    _dismissKeyboard();
    if (category == 'All') return;
    final categories = ref.read(categoryProvider);

    if (categories.length <= 1) {
      _showTransactionError('Keep at least one expense category.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Delete Category?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Text(
          "Delete '$category'? Existing transactions will remain unchanged.",
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    ref.read(categoryProvider.notifier).deleteCategory(category);

    if (_selectedCategoryTab == category) {
      setState(() => _selectedCategoryTab = 'All');
    }
    _showDeletionMessage(
      "Category '$category' was deleted.",
      title: 'Category deleted',
    );
  }

  // ==================== TRANSACTION / TRANSFER MODAL ====================
  Future<bool?> _showAddOrEditModal({
    Expense? existing,
    String? prefilledAmount,
    String? prefilledTitle,
    String? prefilledCategory,
    DateTime? prefilledDate,
    String? preselectedWalletId,
    String initialType = 'expense',
    String? reviewMessage,
  }) async {
    _dismissKeyboard();
    if (existing?.category == 'Transfer') {
      _showTransactionInfo(
        'Delete this transfer and create it again if its details need to change.',
        title: 'Transfers cannot be edited',
      );
      return null;
    }

    final titleCtrl = TextEditingController(
      text: existing?.title ?? prefilledTitle ?? "",
    );
    final amountCtrl = TextEditingController(
      text: prefilledAmount ?? (existing?.amount.toString() ?? ""),
    );
    String selectedCategory =
        existing?.category ?? prefilledCategory ?? "General";
    DateTime selectedDate =
        existing?.date ?? prefilledDate ?? DateTime.now();

    String transactionType = existing?.type ?? initialType;

    final wallets = ref.read(walletProvider);
    String selectedWalletId =
        existing?.walletId ?? preselectedWalletId ?? '';
    String transferToWalletId = '';

    final categories = ref.read(categoryProvider);
    if (!categories.contains(selectedCategory) && categories.isNotEmpty) {
      selectedCategory = categories.first;
    }

    final primaryColor = Color(ref.read(settingsProvider).profileColorValue);

    if (!wallets.any((w) => w.id == selectedWalletId) && wallets.isNotEmpty) {
      final cashWallet = wallets.cast<Wallet?>().firstWhere(
            (w) => w != null && !w.isBackup && (w.walletType == 'cash' || w.name.toLowerCase().contains('cash')),
        orElse: () => null,
      );

      if (cashWallet != null) {
        selectedWalletId = cashWallet.id;
      } else {
        selectedWalletId = wallets.firstWhere((w) => !w.isBackup, orElse: () => wallets.first).id;
      }
    }

    if (wallets.length > 1) {
      transferToWalletId = wallets.firstWhere((w) => w.id != selectedWalletId, orElse: () => wallets.last).id;
    }

    return showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setModalState) => Container(
            decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 30, offset: const Offset(0, -10))]
            ),
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 24, left: 24, right: 24, top: 12),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 48, height: 4, decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)), margin: const EdgeInsets.only(bottom: 24)),

                  if (reviewMessage != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: primaryColor.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.fact_check_outlined,
                            color: primaryColor,
                            size: 21,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Review before saving',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  reviewMessage,
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontSize: 12.5,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  Container(
                    decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        _buildSegment(transactionType, 'expense', "Expense", Colors.red, () => setModalState(() => transactionType = 'expense')),
                        _buildSegment(transactionType, 'income', "Income", Colors.green, () => setModalState(() => transactionType = 'income')),
                        _buildSegment(transactionType, 'transfer', "Transfer", Colors.blue, () => setModalState(() => transactionType = 'transfer')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (transactionType != 'transfer')
                    _buildModernInput(titleCtrl, "Title", Icons.title_rounded, primaryColor)
                  else
                    const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(left: 8, bottom: 8), child: Text("Moving money between wallets", style: TextStyle(color: Colors.grey, fontSize: 13)))),

                  const SizedBox(height: 12),
                  _buildModernInput(amountCtrl, "Amount", Icons.attach_money_rounded, primaryColor, isNumber: true),
                  const SizedBox(height: 12),

                  if (transactionType == 'transfer') ...[
                    _buildWalletDropdown(wallets, selectedWalletId, "From Wallet", (v) => setModalState(() => selectedWalletId = v!)),
                    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Icon(Icons.arrow_downward_rounded, color: Colors.grey)),
                    _buildWalletDropdown(wallets, transferToWalletId, "To Wallet", (v) => setModalState(() => transferToWalletId = v!)),
                  ] else ...[
                    _buildWalletDropdown(wallets, selectedWalletId, "Wallet", (v) => setModalState(() => selectedWalletId = v!)),
                  ],
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: GestureDetector(
                          onTap: () async {
                            final picked = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
                            if (picked != null) setModalState(() => selectedDate = picked);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today_rounded, color: Colors.grey.shade500, size: 20),
                                const SizedBox(width: 8),
                                Expanded(child: Text(DateFormat.yMMMd().format(selectedDate), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (transactionType == 'expense') ...[
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: categories.contains(selectedCategory) ? selectedCategory : (categories.isNotEmpty ? categories.first : "General"),
                                isExpanded: true,
                                icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade500),
                                items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis))).toList(),
                                onChanged: (v) => setModalState(() => selectedCategory = v!),
                              ),
                            ),
                          ),
                        ),
                      ]
                    ],
                  ),

                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity, height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: transactionType == 'transfer' ? Colors.blue : primaryColor, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      onPressed: () async {
                        final amt = double.tryParse(amountCtrl.text.trim());
                        if (amt == null || !amt.isFinite || amt <= 0) {
                          _showTransactionError('Enter a valid amount above zero.');
                          return;
                        }
                        if (wallets.isEmpty) {
                          _showTransactionError('Create a wallet first.');
                          return;
                        }

                        if (transactionType == 'expense') {
                          final currentBalance = ref
                              .read(walletProvider.notifier)
                              .getBalanceForWallet(selectedWalletId);
                          final reusableAmount = existing != null &&
                              existing.type == 'expense' &&
                              existing.walletId == selectedWalletId
                              ? existing.amount
                              : 0.0;
                          final available = currentBalance + reusableAmount;
                          if (amt > available) {
                            final accountName = wallets
                                .firstWhere((w) => w.id == selectedWalletId)
                                .name;
                            _showTransactionError(
                              'Available in $accountName: Rs. ${available.toStringAsFixed(0)}. Required: Rs. ${amt.toStringAsFixed(0)}. Add money to this wallet or enter a smaller amount.',
                              title: 'Insufficient balance',
                            );
                            return;
                          }
                        }

                        Expense? preferenceEntry;
                        if (transactionType == 'transfer') {
                          if (wallets.length < 2) {
                            _showTransactionError('Create at least two wallets to transfer money.');
                            return;
                          }
                          if (selectedWalletId == transferToWalletId) {
                            _showTransactionError('Choose two different wallets.');
                            return;
                          }
                          final available = ref
                              .read(walletProvider.notifier)
                              .getBalanceForWallet(selectedWalletId);
                          if (amt > available) {
                            _showTransactionError(
                              'Available in the source wallet: Rs. ${available.toStringAsFixed(0)}. Enter a smaller amount or add money first.',
                              title: 'Insufficient balance',
                            );
                            return;
                          }
                          final fromName = wallets.firstWhere((w) => w.id == selectedWalletId).name;
                          final toName = wallets.firstWhere((w) => w.id == transferToWalletId).name;
                          final transferId = const Uuid().v4();

                          final transferResult = await ref
                              .read(transactionExecutorProvider)
                              .execute(CreateTransferCommand(
                            outgoing: Expense(id: '${transferId}_out', title: coreTransactionTitle("Transfer to $toName"), amount: amt, date: selectedDate, category: "Transfer", colorValue: Colors.blue.toARGB32(), type: 'expense', walletId: selectedWalletId),
                            incoming: Expense(id: '${transferId}_in', title: coreTransactionTitle("Transfer from $fromName"), amount: amt, date: selectedDate, category: "Transfer", colorValue: Colors.blue.toARGB32(), type: 'income', walletId: transferToWalletId),
                          ));
                          if (!transferResult.succeeded) {
                            _showTransactionError(
                              'The source wallet no longer has enough money for this transfer.',
                              title: 'Transfer not saved',
                            );
                            return;
                          }
                        } else {
                          String finalTitle =
                          coreTransactionTitle(titleCtrl.text);
                          if (finalTitle.isEmpty) {
                            if (transactionType == 'income') {
                              finalTitle = 'Income / Allowance';
                            } else {
                              _showTransactionError('Enter a transaction title.');
                              return;
                            }
                          }

                          final finalCategory = transactionType == 'income' ? 'Income / Allowance' : selectedCategory;
                          if (existing == null) {
                            final newEntry = Expense(id: const Uuid().v4(), title: finalTitle, amount: amt, date: selectedDate, category: finalCategory, colorValue: primaryColor.toARGB32(), type: transactionType, walletId: selectedWalletId);
                            final createResult = await ref
                                .read(transactionExecutorProvider)
                                .execute(CreateTransactionCommand(newEntry));
                            if (!createResult.succeeded) {
                              _showTransactionError(
                                'Check the selected wallet balance and try again.',
                                title: 'Transaction not saved',
                              );
                              return;
                            }
                            preferenceEntry = newEntry;
                          } else {
                            final editedEntry = Expense(id: existing.id, title: finalTitle, amount: amt, date: selectedDate, category: finalCategory, colorValue: existing.colorValue, type: transactionType, walletId: selectedWalletId);
                            final updateResult = await ref
                                .read(transactionExecutorProvider)
                                .execute(UpdateTransactionCommand(
                              existingId: existing.id,
                              updated: editedEntry,
                            ));
                            if (!updateResult.succeeded) {
                              _showTransactionError('This transaction no longer exists.');
                              return;
                            }
                            preferenceEntry = editedEntry;
                          }
                        }
                        if (ctx.mounted) Navigator.pop(ctx, true);
                        if (reviewMessage == null && mounted) {
                          if (transactionType == 'transfer') {
                            _showTransferMessage(
                              'Money was moved between the selected wallets.',
                            );
                          } else if (transactionType == 'income') {
                            _showIncomeMessage(
                              'The income was added to the selected wallet.',
                            );
                          } else {
                            _showExpenseMessage(
                              'The expense was saved to the selected wallet.',
                            );
                          }
                        }
                        if (preferenceEntry != null) {
                          unawaited(
                            _rememberSmartEntryPreference(preferenceEntry),
                          );
                        }
                        unawaited(_refreshSmartEntryReminders());
                      },
                      child: Text(transactionType == 'transfer' ? "Complete Transfer" : "Save Transaction", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  )
                ],
              ),
            ),
          ),
        )
    );
  }

  void _showTransactionError(
      String message, {
        String title = 'Unable to continue',
      }) {
    _showTopMessage(title: title, message: message, tone: _MessageTone.error);
  }

  void _showTransactionSuccess(
      String message, {
        String title = 'Completed',
        String? actionLabel,
        Future<void> Function()? onAction,
      }) {
    _showTopMessage(
      title: title,
      message: message,
      tone: _MessageTone.success,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  void _showTransactionInfo(
      String message, {
        String title = 'Information',
      }) {
    _showTopMessage(title: title, message: message, tone: _MessageTone.info);
  }

  void _showExpenseMessage(String message, {String title = 'Expense saved'}) {
    _showTopMessage(title: title, message: message, tone: _MessageTone.expense);
  }

  void _showIncomeMessage(String message, {String title = 'Income added'}) {
    _showTopMessage(title: title, message: message, tone: _MessageTone.income);
  }

  void _showTransferMessage(
    String message, {
    String title = 'Transfer completed',
    String? actionLabel,
    Future<void> Function()? onAction,
  }) {
    _showTopMessage(
      title: title,
      message: message,
      tone: _MessageTone.transfer,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  void _showDeletionMessage(
    String message, {
    String title = 'Moved to Trash',
    String? actionLabel,
    Future<void> Function()? onAction,
  }) {
    _showTopMessage(
      title: title,
      message: message,
      tone: _MessageTone.deletion,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  void _showWarningMessage(String message, {String title = 'Check this entry'}) {
    _showTopMessage(title: title, message: message, tone: _MessageTone.warning);
  }

  void _showTopMessage({
    required String title,
    required String message,
    required _MessageTone tone,
    String? actionLabel,
    Future<void> Function()? onAction,
  }) {
    if (!mounted) return;

    _messageTimer?.cancel();
    _activeMessageEntry?.remove();

    late final OverlayEntry entry;
    void dismiss() {
      if (_activeMessageEntry != entry) return;
      entry.remove();
      _activeMessageEntry = null;
      _messageTimer?.cancel();
      _messageTimer = null;
    }

    entry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        top: MediaQuery.paddingOf(overlayContext).top + 12,
        left: 16,
        right: 16,
        child: Align(
          alignment: Alignment.topCenter,
          child: _TopMessageCard(
            title: title,
            message: message,
            tone: tone,
            actionLabel: actionLabel,
            onAction: onAction,
            onDismiss: dismiss,
          ),
        ),
      ),
    );

    _activeMessageEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    _messageTimer = Timer(const Duration(seconds: 5), dismiss);
  }

  Widget _buildSegment(String current, String type, String label, Color color, VoidCallback onTap) {
    bool isActive = current == type;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: isActive ? color.withValues(alpha: 0.15) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
          child: Center(child: Text(label, style: TextStyle(color: isActive ? color : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12))),
        ),
      ),
    );
  }

  Widget _buildWalletDropdown(List<Wallet> wallets, String value, String hint, Function(String?) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.withValues(alpha: 0.1))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: wallets.any((w) => w.id == value) ? value : wallets.first.id,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade500),
          items: wallets.map((w) => DropdownMenuItem(value: w.id, child: Row(children: [
            Icon(w.isBackup ? Icons.shield_rounded : Icons.account_balance_wallet_rounded, size: 18, color: Color(w.colorValue)),
            const SizedBox(width: 12),
            Text(w.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))
          ]))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildModernInput(TextEditingController ctrl, String label, IconData icon, Color primaryColor, {bool isNumber = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber
          ? const TextInputType.numberWithOptions(decimal: true, signed: false)
          : TextInputType.text,
      inputFormatters: isNumber
          ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))]
          : null,
      textCapitalization: isNumber ? TextCapitalization.none : TextCapitalization.sentences,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      decoration: InputDecoration(labelText: label, labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13), prefixIcon: Icon(icon, color: Colors.grey.shade500, size: 20), filled: true, fillColor: Theme.of(context).cardColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: primaryColor, width: 1.5)), contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16)),
    );
  }

  Future<void> _openIncomeAccounts() async {
    _dismissKeyboard();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const IncomeAccountsScreen()),
    );
    if (mounted) _queuePersistentNotificationUpdate();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ExpenseState>(expenseProvider, (_, __) {
      _queuePersistentNotificationUpdate();
    });
    ref.listen<List<Wallet>>(walletProvider, (_, __) {
      _queuePersistentNotificationUpdate();
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final workspaceState = ref.watch(workspaceProvider);

    if (!_dashboardViews.contains(_currentView)) {
      return Scaffold(
        drawer: AppDrawer(
          currentView: _currentView,
          onViewChanged: _changeView,
        ),
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            _currentView,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          centerTitle: true,
          leading: IconButton(
            tooltip: 'Back to dashboard',
            icon: const Icon(Icons.arrow_back_rounded, size: 24),
            onPressed: () => _changeView('Dashboard'),
          ),
        ),
        body: _buildOtherViews(),
      );
    }

    final ledger = ref.watch(monthlyLedgerProvider(_focusedMonth));
    final categories = ref.watch(categoryProvider);
    final wallets = ref.watch(walletProvider);

    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    final monthlyTransactions = ledger.transactions;
    final globalSpent = ledger.spent;

    final walletNotifier = ref.read(walletProvider.notifier);
    final totalAvailable = wallets.fold<double>(
      0,
          (sum, wallet) => sum + walletNotifier.getBalanceForWallet(wallet.id),
    );
    final showMoneySetup = totalAvailable.abs() < 0.000001 &&
        ref.watch(expenseProvider).allExpenses.isEmpty;

    var displayExpenses = List<Expense>.from(
      _isSearching && _smartEntrySearchAllHistory
          ? visibleTransactions(
              ref
                  .watch(expenseProvider)
                  .allExpenses
                  .where(
                    (entry) => entry.workspaceId == workspaceState.selectedId,
                  ),
            )
          : monthlyTransactions,
    );

    if (_selectedCategoryTab != 'All' && !categories.contains(_selectedCategoryTab)) {
      _selectedCategoryTab = 'All';
    }

    if (_selectedCategoryTab != 'All') displayExpenses = displayExpenses.where((e) => e.category == _selectedCategoryTab).toList();
    if (_searchQuery.isNotEmpty) displayExpenses = displayExpenses.where((e) => e.title.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    if (_smartEntryTypeFilter != null) {
      displayExpenses = displayExpenses
          .where((entry) => entry.type == _smartEntryTypeFilter)
          .toList();
    }
    if (_smartEntrySearchRange != null) {
      displayExpenses = displayExpenses
          .where((entry) => matchesSmartEntryTimeRange(
        entry.date,
        _smartEntrySearchRange!,
      ))
          .toList();
    }

    return Scaffold(
      drawer: AppDrawer(
        currentView: _currentView,
        onViewChanged: _changeView,
      ),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        title: _isSearching ? TextField(style: const TextStyle(fontSize: 15), decoration: InputDecoration(border: InputBorder.none, hintText: "Search transactions...", hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14)), onChanged: (v)=>setState(()=>_searchQuery=v)) : Text(
          _currentView == 'Dashboard'
              ? workspaceState.workspaces.isEmpty
                  ? 'Personal'
                  : workspaceState.workspaces
                      .firstWhere(
                        (workspace) =>
                            workspace.id == workspaceState.selectedId,
                        orElse: () => workspaceState.workspaces.first,
                      )
                      .name
              : _currentView,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        centerTitle: true,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded, size: 24),
            onPressed: () {
              _dismissKeyboard();
              Scaffold.of(context).openDrawer();
            },
          ),
        ),
        actions: [
          if (_currentView == 'Dashboard' && !_isSearching)
            IconButton(
              tooltip: 'Manage workspaces',
              icon: const Icon(Icons.workspaces_outline, size: 21),
              onPressed: () => _changeView('Workspaces'),
            ),
          if (_currentView == 'Dashboard' && !_isSearching)
            IconButton(
              tooltip: 'Wallets',
              icon: const Icon(Icons.account_balance_wallet_outlined, size: 22),
              onPressed: _openIncomeAccounts,
            ),
          if (_currentView == 'Dashboard')
            IconButton(
              tooltip: _isSearching ? 'Close search' : 'Search',
              icon: Icon(
                _isSearching ? Icons.close_rounded : Icons.search_rounded,
                size: 22,
              ),
              onPressed: () {
                _dismissKeyboard();
                setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) {
                    _searchQuery = '';
                    _smartEntryTypeFilter = null;
                    _smartEntrySearchRange = null;
                    _smartEntrySearchAllHistory = false;
                  }
                });
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: _buildDashboardSelector(primaryColor, workspaceState),
        ),
      ),
      body: PageView(
        controller: _dashboardPageController,
        onPageChanged: _onDashboardPageChanged,
        children: [
          _buildResponsiveBody(
            isLandscape,
            isDark,
            primaryColor,
            totalAvailable,
            globalSpent,
            wallets,
            categories,
            displayExpenses,
            showMoneySetup,
          ),
          _dashboardBoxesReady
              ? const DebtScreen(
                  key: PageStorageKey('dashboard-udhaar'),
                  embedded: true,
                )
              : const Center(child: CircularProgressIndicator()),
          _dashboardBoxesReady
              ? const MessKhataScreen(
                  key: PageStorageKey('dashboard-mess'),
                  embedded: true,
                )
              : const Center(child: CircularProgressIndicator()),
          for (final workspace
              in workspaceState.workspaces.where((item) => !item.isDefault))
            KeyedSubtree(
              key: PageStorageKey('workspace-${workspace.id}'),
              child: _buildResponsiveBody(
                isLandscape,
                isDark,
                primaryColor,
                totalAvailable,
                globalSpent,
                wallets,
                categories,
                displayExpenses,
                showMoneySetup,
              ),
            ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: (_currentView == 'Dashboard') ? GestureDetector(
        onTapDown: (_) => _fabController.forward(),
        onTapUp: (_) { _fabController.reverse(); _showAddOrEditModal(); },
        onTapCancel: () => _fabController.reverse(),
        child: ScaleTransition(
          scale: _fabScale,
          child: Container(
            height: 52, padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(gradient: LinearGradient(colors: [primaryColor, primaryColor.withValues(alpha: 0.8)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(26), boxShadow: [BoxShadow(color: primaryColor.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 6))]),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add_rounded, color: Colors.white, size: 22), SizedBox(width: 8), Text("Add Transaction", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))]),
          ),
        ),
      ) : null,
    );
  }

  Widget _buildResponsiveBody(
      bool isLandscape,
      bool isDark,
      Color primaryColor,
      double totalAvailable,
      double spent,
      List<Wallet> wallets,
      List<String> categories,
      List<Expense> displayExpenses,
      bool showMoneySetup,
      ) {
    if (isLandscape && !_isSearching) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 80),
              child: Column(
                children: [
                  if (showMoneySetup) ...[
                    _buildMoneySetupCard(primaryColor),
                    const SizedBox(height: 10),
                  ],
                  _buildMonthSelector(isDark),
                  const SizedBox(height: 8),
                  _buildHeroCard(
                    totalAvailable,
                    spent,
                    wallets,
                    primaryColor,
                  ),
                  const SizedBox(height: 14),
                  _buildSmartInputBar(primaryColor, isDark, wallets),
                  const SizedBox(height: 8),
                  _buildCategoryTabsWidget(
                    categories,
                    primaryColor,
                    isDark,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _buildExpenseList(
              displayExpenses,
              primaryColor,
              isDark,
              isSliver: false,
            ),
          ),
        ],
      );
    }

    if (_isSearching) {
      return Column(
        children: [
          const SizedBox(height: 4),
          Expanded(
            child: _buildExpenseList(
              displayExpenses,
              primaryColor,
              isDark,
              isSliver: false,
            ),
          ),
        ],
      );
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        if (showMoneySetup)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: _buildMoneySetupCard(primaryColor),
            ),
          ),
        SliverToBoxAdapter(
          child: _buildMonthSelector(isDark),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _buildHeroCard(
              totalAvailable,
              spent,
              wallets,
              primaryColor,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 8),
            child: _buildSmartInputBar(primaryColor, isDark, wallets),
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _StickyHeaderDelegate(
            minHeight: 56,
            maxHeight: 56,
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: _buildCategoryTabsWidget(
                categories,
                primaryColor,
                isDark,
              ),
            ),
          ),
        ),
        _buildExpenseList(
          displayExpenses,
          primaryColor,
          isDark,
          isSliver: true,
        ),
      ],
    );
  }

  Widget _buildDashboardSelector(
    Color primaryColor,
    WorkspaceState workspaceState,
  ) {
    final customWorkspaces = workspaceState.workspaces
        .where((workspace) => !workspace.isDefault)
        .toList();
    final labels = [
      'Personal',
      'Udhaar',
      'Mess Khata',
      ...customWorkspaces.map((workspace) => workspace.name),
    ];
    return Container(
      height: 40,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primaryColor.withValues(alpha: 0.12)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (context, index) {
          final isWorkspace = index == 0 || index >= 3;
          final workspaceId = index == 0
              ? 'personal'
              : index >= 3
                  ? customWorkspaces[index - 3].id
                  : null;
          final selected = isWorkspace
              ? _currentView == 'Dashboard' &&
                  workspaceState.selectedId == workspaceId
              : _currentView == _dashboardViews[index];
          return SizedBox(
            width: 104,
            child: InkWell(
                borderRadius: BorderRadius.circular(11),
                onTap: () async {
                  if (workspaceId != null) {
                    await ref
                        .read(workspaceProvider.notifier)
                        .select(workspaceId);
                  }
                  if (_dashboardPageController.hasClients) {
                    await _dashboardPageController.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                    );
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? primaryColor.withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    labels[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: selected
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: selected
                          ? primaryColor
                          : Colors.grey.shade600,
                    ),
                  ),
                ),
              ),
          );
        },
      ),
    );
  }

  Widget _buildMoneySetupCard(Color primaryColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: primaryColor.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.rocket_launch_outlined,
                  color: primaryColor,
                  size: 21,
                ),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Set up your first money',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Your total balance automatically equals all wallet balances.',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.south_west_rounded, size: 17),
                label: const Text('Add first income'),
                onPressed: () => _showAddOrEditModal(initialType: 'income'),
              ),
              ActionChip(
                avatar: const Icon(Icons.account_balance_wallet_outlined, size: 17),
                label: const Text('Set wallet balance'),
                onPressed: _openIncomeAccounts,
              ),
              ActionChip(
                avatar: const Icon(Icons.auto_awesome_rounded, size: 17),
                label: const Text('Try Smart Entry'),
                onPressed: () {
                  _smartInputCtrl.text = '5000 salary JazzCash mein add karo';
                  _smartInputCtrl.selection = TextSelection.collapsed(
                    offset: _smartInputCtrl.text.length,
                  );
                  _showTransactionInfo(
                    'Review the example, then tap Send.',
                    title: 'Smart Entry example ready',
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOtherViews() {
    if (_currentView == 'Mess Khata') return const MessKhataScreen();
    if (_currentView == 'Udhaar') return const DebtScreen();
    if (_currentView == 'Stats') return const StatsScreen();
    if (_currentView == 'Settings') return const SettingsScreen();
    if (_currentView == 'About') return const AboutScreen();
    if (_currentView == 'Trash') return const TrashScreen();
    if (_currentView == 'Workspaces') return const WorkspacesScreen();
    return const SizedBox.shrink();
  }

  Widget _buildExpenseList(List<Expense> expenses, Color primaryColor, bool isDark, {required bool isSliver}) {
    if (expenses.isEmpty) {
      final emptyState = Center(child: Padding(padding: const EdgeInsets.only(top: 40.0), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.receipt_long_rounded, size: 50, color: Colors.grey.withValues(alpha: 0.3)), const SizedBox(height: 12), Text("No transactions here yet.", style: TextStyle(color: Colors.grey.shade500, fontSize: 13))])));
      return isSliver ? SliverFillRemaining(hasScrollBody: false, child: emptyState) : emptyState;
    }

    final now = DateTime.now();
    final double todaySpend = expenses
        .where((e) =>
    e.type == 'expense' &&
        e.category != 'Transfer' &&
        e.date.day == now.day &&
        e.date.month == now.month &&
        e.date.year == now.year)
        .fold(0.0, (sum, e) => sum + e.amount);

    final hasTodaySummary = todaySpend > 0;
    final itemCount = expenses.length + (hasTodaySummary ? 1 : 0);

    Widget buildItem(BuildContext context, int index) {
      if (hasTodaySummary && index == 0) {
        return _buildTodaySpendPill(todaySpend, primaryColor);
      }
      final expenseIndex = index - (hasTodaySummary ? 1 : 0);
      return _buildExpenseTile(
        expenses[expenseIndex],
        primaryColor,
        isDark,
      );
    }

    if (isSliver) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 80),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            buildItem,
            childCount: itemCount,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 80),
      itemCount: itemCount,
      itemBuilder: buildItem,
    );
  }

  Widget _buildTodaySpendPill(double todaySpend, Color primaryColor) {
    return Padding(
      key: const ValueKey('daily_spend_pill'),
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Align(
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: primaryColor.withValues(alpha: 0.2)),
          ),
          child: Text(
            "Today's Spend: Rs. ${todaySpend.toStringAsFixed(0)}",
            style: TextStyle(
              color: primaryColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpenseTile(Expense e, Color primaryColor, bool isDark) {
    final eColor = Color(e.colorValue);
    final isIncome = e.type == 'income';
    final isTransfer = e.category == 'Transfer';

    final amountSign = isTransfer ? "" : (isIncome ? "+" : "-");
    final amountColor = isTransfer ? Colors.blue : (isIncome ? Colors.green : (isDark ? Colors.white : Colors.black87));
    final displayIcon = isTransfer ? Icons.swap_horiz_rounded : (isIncome ? Icons.south_west_rounded : Icons.category_rounded);

    return Dismissible(
      key: Key(e.id),
      direction: DismissDirection.endToStart,
      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(18)), child: const Icon(Icons.delete_outline_rounded, color: Colors.white)),
      confirmDismiss: (direction) async {
        final confirmed = await showDialog<bool>(
              context: context,
              builder: (dialogCtx) => Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                backgroundColor: Theme.of(context).cardColor,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.red,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isTransfer
                            ? 'Move Transfer to Trash?'
                            : 'Move Transaction to Trash?',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isTransfer
                            ? 'Both linked wallet entries will move together and can be restored.'
                            : "Move '${e.title}' to Trash? It can be restored for 30 days.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.of(dialogCtx).pop(false),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => Navigator.of(dialogCtx).pop(true),
                              child: const Text('Move to Trash'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ) ??
            false;
        if (!confirmed) return false;
        final result = isTransfer
            ? await ref
              .read(transactionExecutorProvider)
              .execute(DeleteTransferCommand(e.id))
            : await ref
              .read(transactionExecutorProvider)
              .execute(DeleteTransactionCommand(e.id));
        if (!mounted) return false;
        if (!result.succeeded) {
          _showTransactionError(
            result.reason ?? 'The entry could not be moved to Trash.',
          );
          return false;
        }
        return true;
      },
      onDismissed: (direction) {
        _showDeletionMessage(
          "'${e.title}' can be restored from Trash.",
          title: isTransfer ? 'Transfer moved to Trash' : 'Moved to Trash',
          actionLabel: 'Undo',
          onAction: () async {
            final restored = isTransfer
                ? await ref
                    .read(transactionExecutorProvider)
                    .execute(RestoreTransferCommand(e.id))
                : await ref
                    .read(transactionExecutorProvider)
                    .execute(RestoreTransactionCommand(e.id));
            if (!mounted) return;
            if (restored.succeeded) {
              _showTransactionInfo('The entry was restored.', title: 'Restored');
            }
          },
        );
      },
      child: GestureDetector(
        onTap: isTransfer ? null : () => _showAddOrEditModal(existing: e),
        child: Container(
            margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(18), border: Border.all(color: isDark ? primaryColor.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.12), width: 1.2)),
            child: Row(
              children: [
                Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: (isTransfer ? Colors.blue : (isIncome ? Colors.green : eColor)).withValues(alpha: 0.15), shape: BoxShape.circle), child: Icon(displayIcon, color: isTransfer ? Colors.blue : (isIncome ? Colors.green : eColor), size: 20)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Row(children: [Icon(Icons.schedule_rounded, size: 11, color: Colors.grey.shade500), const SizedBox(width: 4), Text(DateFormat.MMMEd().format(e.date), style: TextStyle(fontSize: 11, color: Colors.grey.shade500))]),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text("$amountSign Rs. ${e.amount.toStringAsFixed(0)}", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: amountColor)),
              ],
            )
        ),
      ),
    );
  }

  Widget _buildCategoryTabsWidget(List<String> categories, Color primaryColor, bool isDark) {
    return Container(
      height: 40, margin: const EdgeInsets.only(top: 4, bottom: 8),
      child: ListView(
          controller: _categoryScrollCtrl, scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [_buildTab('All', 0, isDark, primaryColor), ...List.generate(categories.length, (i) => _buildTab(categories[i], i + 1, isDark, primaryColor)), _buildAddCategoryBtn(primaryColor, isDark)]
      ),
    );
  }

  Widget _buildAddCategoryBtn(Color primaryColor, bool isDark) {
    return GestureDetector(
      onTap: _showAddCategoryDialog,
      child: Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 16), decoration: BoxDecoration(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20), border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300, width: 1.2)), child: Row(children: [Icon(Icons.add_rounded, size: 16, color: isDark ? Colors.white70 : Colors.black87), const SizedBox(width: 4), Text("New", style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold, fontSize: 12))])),
    );
  }

  Widget _buildTab(String label, int index, bool isDark, Color primaryColor) {
    bool isSelected = _selectedCategoryTab == label;
    return GestureDetector(
        onTap: () => _selectCategory(label, index),
        onLongPress: label == 'All' ? null : () => _confirmDeleteCategory(label),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isSelected ? primaryColor : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
            border: isSelected ? null : Border.all(color: isDark ? primaryColor.withValues(alpha: 0.25) : Colors.grey.withValues(alpha: 0.15), width: 1.2),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87), fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, fontSize: 12)),
                if (isSelected && label != 'All') ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _confirmDeleteCategory(label),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.close_rounded, size: 14, color: Colors.white),
                    ),
                  ),
                ],
              ],
            ),
          ),
        )
    );
  }

  Widget _buildSmartInputBar(
      Color primaryColor,
      bool isDark,
      List<Wallet> wallets,
      ) {
    final cardColor = Theme.of(context).cardColor;
    final inputColor = isDark
        ? Colors.white.withValues(alpha: 0.055)
        : primaryColor.withValues(alpha: 0.045);
    final defaultAccountLabel = _smartEntryDefaultAccountLabel(wallets);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _isListening
              ? Colors.red.withValues(alpha: 0.7)
              : primaryColor.withValues(alpha: isDark ? 0.24 : 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.055),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: (_isListening ? Colors.red : primaryColor)
                      .withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _isListening
                      ? Icons.graphic_eq_rounded
                      : Icons.auto_awesome_rounded,
                  color: _isListening ? Colors.red : primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: InkWell(
                  onTap: _isListening
                      ? null
                      : _showSmartEntryAccountPicker,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isListening ? 'Listening now' : 'Smart Entry',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isListening
                              ? 'Speak naturally — it saves automatically'
                              : defaultAccountLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _isListening
                                ? Colors.grey.shade500
                                : primaryColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_isListening)
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                )
              else
                IconButton(
                  tooltip: 'Select default Smart Entry wallet',
                  visualDensity: VisualDensity.compact,
                  onPressed: _showSmartEntryAccountPicker,
                  icon: Icon(
                    Icons.tune_rounded,
                    color: primaryColor,
                    size: 20,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 54,
            decoration: BoxDecoration(
              color: inputColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: TextField(
              controller: _smartInputCtrl,
              textInputAction: TextInputAction.done,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              onSubmitted: _processNLP,
              decoration: InputDecoration(
                hintText: _isListening
                    ? 'Listening…'
                    : 'e.g. 500 biryani from JazzCash',
                hintStyle: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                contentPadding:
                const EdgeInsets.only(left: 15, top: 17, bottom: 17),
                suffixIconConstraints:
                const BoxConstraints(minHeight: 40),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Scan receipt',
                      visualDensity: VisualDensity.compact,
                      constraints:
                      const BoxConstraints.tightFor(width: 38, height: 40),
                      onPressed:
                      _isScanningReceipt ? null : _scanReceiptIntoInput,
                      icon: _isScanningReceipt
                          ? SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: primaryColor,
                        ),
                      )
                          : Icon(
                        Icons.document_scanner_outlined,
                        size: 20,
                        color: primaryColor,
                      ),
                    ),
                    IconButton(
                      tooltip:
                      _isListening ? 'Stop listening' : 'Voice input',
                      visualDensity: VisualDensity.compact,
                      constraints:
                      const BoxConstraints.tightFor(width: 38, height: 40),
                      onPressed: _listenForExpense,
                      icon: Icon(
                        _isListening
                            ? Icons.stop_circle_rounded
                            : Icons.mic_none_rounded,
                        size: 21,
                        color: _isListening ? Colors.red : primaryColor,
                      ),
                    ),
                    Container(
                      width: 34,
                      height: 34,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        tooltip: 'Save Smart Entry',
                        padding: EdgeInsets.zero,
                        onPressed: () =>
                            _processNLP(_smartInputCtrl.text),
                        icon: const Icon(
                          Icons.arrow_upward_rounded,
                          size: 19,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _smartEntryDefaultAccountLabel(List<Wallet> wallets) {
    final selected = _selectedSmartEntryWallet(wallets);
    return selected == null
        ? 'Default wallet: Automatic (Cash → JazzCash) · Tap to change'
        : 'Default wallet: ${selected.name} · Tap to change';
  }

  Wallet? _selectedSmartEntryWallet(List<Wallet> wallets) {
    final selectedId = _smartEntryDefaultWalletId;
    if (selectedId == null) return null;
    for (final wallet in wallets) {
      if (wallet.id == selectedId) return wallet;
    }
    return null;
  }

  Future<void> _showSmartEntryAccountPicker() async {
    _dismissKeyboard();
    final wallets = ref.read(walletProvider);
    if (wallets.isEmpty) {
      _showTransactionError(
        'Create a wallet before selecting a Smart Entry default.',
        title: 'No wallets',
      );
      return;
    }

    final walletNotifier = ref.read(walletProvider.notifier);
    final selectedId = _selectedSmartEntryWallet(wallets)?.id;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Default Smart Entry wallet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(sheetContext)
                            .colorScheme
                            .primaryContainer,
                        child: Icon(
                          Icons.auto_awesome_rounded,
                          color: Theme.of(sheetContext)
                              .colorScheme
                              .primary,
                        ),
                      ),
                      title: const Text(
                        'Automatic',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'Use Cash first, then JazzCash',
                      ),
                      trailing: selectedId == null
                          ? const Icon(Icons.check_circle_rounded)
                          : null,
                      onTap: () async {
                        await Hive.box('preferences')
                            .delete(_smartEntryDefaultAccountKey);
                        if (!mounted) return;
                        setState(() => _smartEntryDefaultWalletId = null);
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }
                      },
                    ),
                    const Divider(height: 1),
                    for (final wallet in wallets)
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Color(wallet.colorValue)
                              .withValues(alpha: 0.14),
                          child: Icon(
                            _walletIcon(wallet),
                            color: Color(wallet.colorValue),
                            size: 20,
                          ),
                        ),
                        title: Text(
                          wallet.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          '${wallet.isBackup ? 'Reserve wallet' : 'Wallet'} · Rs. ${walletNotifier.getBalanceForWallet(wallet.id).toStringAsFixed(0)}',
                        ),
                        trailing: selectedId == wallet.id
                            ? const Icon(Icons.check_circle_rounded)
                            : null,
                        onTap: () async {
                          await Hive.box('preferences').put(
                            _smartEntryDefaultAccountKey,
                            wallet.id,
                          );
                          if (!mounted) return;
                          setState(
                                () => _smartEntryDefaultWalletId = wallet.id,
                          );
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Wallet> _resolvedHomeWallets(List<Wallet> wallets) {
    if (wallets.isEmpty) return const [];

    final walletsById = {for (final wallet in wallets) wallet.id: wallet};
    final savedSelection = _homeVisibleWalletIds
        .where(walletsById.containsKey)
        .take(4)
        .map((id) => walletsById[id]!)
        .toList(growable: false);
    if (savedSelection.isNotEmpty) return savedSelection;

    int defaultPriority(Wallet wallet) {
      final type = wallet.walletType.toLowerCase();
      final id = wallet.id.toLowerCase();
      final name = wallet.name.toLowerCase().replaceAll(' ', '');
      if (type == 'cash' || id == 'default_cash' || name == 'cashinhand') {
        return 0;
      }
      if (type == 'jazzcash' ||
          id == 'default_jazzcash' ||
          name == 'jazzcash') {
        return 1;
      }
      return 2;
    }

    final defaults = wallets
        .where((wallet) => defaultPriority(wallet) < 2)
        .toList(growable: false)
      ..sort((a, b) => defaultPriority(a).compareTo(defaultPriority(b)));
    if (defaults.isNotEmpty) {
      return defaults.take(4).toList(growable: false);
    }

    final fallbackCount = wallets.length < 2 ? wallets.length : 2;
    return wallets.take(fallbackCount).toList(growable: false);
  }

  Future<void> _showHomeWalletPicker() async {
    _dismissKeyboard();
    final wallets = ref.read(walletProvider);
    if (wallets.isEmpty) {
      _showTransactionError(
        'Create a wallet before choosing daily wallets.',
        title: 'No wallets',
      );
      return;
    }

    final walletNotifier = ref.read(walletProvider.notifier);
    final selectedIds = <String>{
      ..._resolvedHomeWallets(wallets).map((wallet) => wallet.id),
    };

    final savedIds = await showModalBottomSheet<List<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.78,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Daily wallets',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Choose up to 4 wallets for quick Home tracking.',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${selectedIds.length}/4',
                          style: TextStyle(
                            color: Theme.of(sheetContext).colorScheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: wallets.length,
                      itemBuilder: (context, index) {
                        final wallet = wallets[index];
                        final isSelected = selectedIds.contains(wallet.id);
                        final selectionLimitReached =
                            !isSelected && selectedIds.length >= 4;
                        final balance =
                        walletNotifier.getBalanceForWallet(wallet.id);

                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: selectionLimitReached
                              ? null
                              : (checked) {
                            setSheetState(() {
                              if (checked == true) {
                                selectedIds.add(wallet.id);
                              } else {
                                selectedIds.remove(wallet.id);
                              }
                            });
                          },
                          secondary: CircleAvatar(
                            backgroundColor: Color(wallet.colorValue)
                                .withValues(alpha: 0.14),
                            child: Icon(
                              _walletIcon(wallet),
                              color: Color(wallet.colorValue),
                              size: 20,
                            ),
                          ),
                          title: Text(
                            wallet.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            '${wallet.isBackup ? 'Reserve wallet' : 'Wallet'} · Rs. ${balance.toStringAsFixed(0)}',
                          ),
                          controlAffinity: ListTileControlAffinity.trailing,
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: selectedIds.isEmpty
                            ? null
                            : () => Navigator.pop(
                          sheetContext,
                          selectedIds.toList(growable: false),
                        ),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Save daily wallets'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (savedIds == null || !mounted) return;
    await Hive.box('preferences').put(_homeVisibleWalletsKey, savedIds);
    if (!mounted) return;
    setState(() => _homeVisibleWalletIds = savedIds);
  }

  Widget _buildHeroCard(
      double totalAvailable,
      double spent,
      List<Wallet> wallets,
      Color primary,
      ) {
    final visibleWallets = _resolvedHomeWallets(wallets);
    final darkerPrimary = Color.lerp(
      primary,
      Colors.black,
      Theme.of(context).brightness == Brightness.dark ? 0.12 : 0.18,
    )!;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, darkerPrimary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.20),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Total available',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Choose daily wallets',
                onPressed: _showHomeWalletPicker,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                icon: const Icon(
                  Icons.tune_rounded,
                  color: Colors.white,
                  size: 19,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'Rs. ${totalAvailable.toStringAsFixed(0)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.8,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildBalanceMetric(
                  label: 'Spent this month',
                  value: 'Rs. ${spent.toStringAsFixed(0)}',
                  onTap: () => _changeView('Stats'),
                  semanticHint: 'Open monthly statistics',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildBalanceMetric(
                  label: 'All wallets',
                  value: '${wallets.length}',
                  onTap: _openIncomeAccounts,
                  semanticHint: 'Open wallet accounts',
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Daily wallets',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${visibleWallets.length} of ${wallets.length} shown',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          if (visibleWallets.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Text(
                'No wallets yet',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                ),
              ),
            )
          else
            SizedBox(
              height: 62,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: visibleWallets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 9),
                itemBuilder: (context, index) =>
                    _buildAccountPill(visibleWallets[index]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBalanceMetric({
    required String label,
    required String value,
    VoidCallback? onTap,
    String? semanticHint,
  }) {
    return Semantics(
      button: onTap != null,
      label: label,
      value: value,
      hint: semanticHint,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.68),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 12,
                    color: Colors.white.withValues(alpha: 0.62),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccountPill(Wallet wallet) {
    final balance =
    ref.read(walletProvider.notifier).getBalanceForWallet(wallet.id);

    return Container(
      width: 158,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Color(wallet.colorValue).withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _walletIcon(wallet),
              color: Colors.white,
              size: 15,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  wallet.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Rs. ${balance.toStringAsFixed(0)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (wallet.isBackup)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(
                Icons.shield_outlined,
                color: Colors.white54,
                size: 13,
              ),
            ),
        ],
      ),
    );
  }

  IconData _walletIcon(Wallet wallet) {
    if (wallet.isBackup) return Icons.shield_outlined;
    switch (wallet.walletType.toLowerCase()) {
      case 'jazzcash':
        return Icons.phone_android_rounded;
      case 'bank':
        return Icons.account_balance_outlined;
      case 'cash':
        return Icons.payments_outlined;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }

  Future<void> _pickBudgetMonth() async {
    _dismissKeyboard();
    var selectedYear = _focusedMonth.year;
    final selected = await showDialog<DateTime>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Select month and year'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: selectedYear,
                  decoration: const InputDecoration(
                    labelText: 'Year',
                    prefixIcon: Icon(Icons.calendar_today_rounded),
                  ),
                  items: [
                    for (var year = 2000; year <= 2100; year++)
                      DropdownMenuItem(value: year, child: Text('$year')),
                  ],
                  onChanged: (year) {
                    if (year != null) {
                      setDialogState(() => selectedYear = year);
                    }
                  },
                ),
                const SizedBox(height: 16),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 2.2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: 12,
                  itemBuilder: (context, index) {
                    final month = index + 1;
                    final isSelected = selectedYear == _focusedMonth.year &&
                        month == _focusedMonth.month;
                    return FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        backgroundColor: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : null,
                        foregroundColor: isSelected ? Colors.white : null,
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () => Navigator.pop(
                        dialogContext,
                        DateTime(selectedYear, month, 1),
                      ),
                      child: Text(DateFormat.MMM().format(DateTime(2000, month))),
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _focusedMonth = selected);
    }
  }

  Widget _buildMonthSelector(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
            onPressed: () => setState(() => _focusedMonth =
                DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1)),
          ),
          TextButton.icon(
            onPressed: _pickBudgetMonth,
            icon: const Icon(Icons.calendar_month_rounded, size: 18),
            label: Text(
              DateFormat.yMMMM().format(_focusedMonth),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            onPressed: () => setState(() => _focusedMonth =
                DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1)),
          ),
        ],
      ),
    );
  }

  Future<void> _listenForExpense() async {
    _dismissKeyboard();
    if (_isListening) {
      await _finishSpeechSession(manual: true);
      unawaited(HapticFeedback.selectionClick());
      return;
    }

    _cancelSpeechTimers();
    _speechSession.reset();
    _handlingSpeechError = false;
    _restartingSpeech = false;
    _finalizingRecognizerStop = false;
    final preservedDraft = _smartInputCtrl.text.trim();
    if (!_speechInitialized) {
      final available = await _speech.initialize(
        onStatus: _handleSpeechStatus,
        onError: (error) => _handleSpeechError(error.message),
      );
      if (!mounted) return;
      if (!available) {
        _showTransactionError(
          'Speech recognition is not available. Enable the Google app or your phone\'s speech-recognition service, then allow microphone access.',
          title: 'Voice recognition unavailable',
        );
        return;
      }
      _speechInitialized = true;
    }

    if (!_speechLocalesLoaded) {
      _speechLocaleCandidates = await _buildSpeechLocaleCandidates();
      _speechLocalesLoaded = true;
    }
    _speechLocaleCandidateIndex = 0;
    if (!mounted) return;

    _speechSession.start();
    if (preservedDraft.isNotEmpty) {
      _speechSession.recordTranscript(
        preservedDraft,
        isFinal: false,
      );
    }
    _speechDeadlineTimer = Timer(
      _speechSessionLimit,
          () => unawaited(_finishSpeechSession()),
    );
    setState(() => _isListening = true);
    unawaited(HapticFeedback.mediumImpact());
    await _startSpeechListening();
  }

  Future<List<String?>> _buildSpeechLocaleCandidates() async {
    final candidates = <String?>[];
    try {
      final locales = await _speech.locales();
      final systemLocale = await _speech.systemLocale();

      String normalize(String value) =>
          value.toLowerCase().replaceAll('-', '_');
      final added = <String>{};

      void addLocale(String? localeId) {
        if (localeId == null || localeId.trim().isEmpty) return;
        final normalized = normalize(localeId);
        if (added.add(normalized)) candidates.add(localeId);
      }

      const preferred = ['en_pk', 'en_in', 'en_gb', 'en_us'];
      for (final preferredId in preferred) {
        for (final locale in locales) {
          if (normalize(locale.localeId) == preferredId) {
            addLocale(locale.localeId);
          }
        }
      }
      final systemId = systemLocale?.localeId;
      if (systemId != null && normalize(systemId).startsWith('en_')) {
        addLocale(systemId);
      }
      for (final locale in locales) {
        if (normalize(locale.localeId).startsWith('en_')) {
          addLocale(locale.localeId);
        }
      }
    } catch (error) {
      debugPrint('Speech locale lookup failed: $error');
    }

    candidates.add(null);
    return candidates.take(4).toList(growable: false);
  }

  Future<void> _startSpeechListening() async {
    if (!mounted) return;
    final localeId =
    _speechLocaleCandidates[_speechLocaleCandidateIndex];
    _recognizerReportedListening = false;
    _speechListenStartedAt = DateTime.now();
    _speechStartupTimer?.cancel();
    _speechStartupTimer = Timer(
      _speechStartupGrace,
          () => unawaited(_handleSpeechStartupTimeout()),
    );

    try {
      await _speech.listen(
        options: SpeechRecognitionListenOptions(
          localeId: localeId,
          partialResults: true,
          pauseFor: _speechPauseWindow,
          listenFor: _speechSessionLimit,
        ),
        onResult: (result) async {
          if (!mounted) return;
          if (_speechSession.state != SpeechSessionState.listening &&
              _speechSession.state != SpeechSessionState.finalizing) {
            return;
          }
          _markRecognizerActive();
          final words = result.text.trim();
          final candidate = _mergeSpeechTranscripts(
            _speechSession.latestDraft,
            words,
          );
          final completeness = _speechCompleteness(candidate);
          final decision = _speechSession.recordTranscript(
            candidate,
            isFinal: result.isFinal && completeness.isComplete,
          );
          final combinedWords = _speechSession.latestDraft;
          if (combinedWords.isNotEmpty) {
            _smartInputCtrl.value = TextEditingValue(
              text: combinedWords,
              selection: TextSelection.collapsed(
                offset: combinedWords.length,
              ),
            );
          }
          _traceSpeechEvent(
            result.isFinal ? 'result_final' : 'result_partial',
            transcript: combinedWords,
            completeness: completeness,
          );
          _scheduleStableSpeechFinalization(
            combinedWords,
            completeness,
            isFinal: result.isFinal,
          );
          await _applySpeechDecision(decision);
        },
      );
    } catch (error) {
      debugPrint('Speech listen failed: $error');
      if (!mounted || _handlingSpeechError) return;
      _handlingSpeechError = true;
      _speechSession.onRecognizerError(retryable: false);
      _cancelSpeechTimers();
      setState(() => _isListening = false);
      _showTransactionError(
        'Voice recognition could not start. Check microphone permission and the phone\'s speech-recognition service.',
        title: 'Voice Log unavailable',
      );
    }
  }

  SpeechCommandCompleteness _speechCompleteness(String transcript) {
    final normalized = transcript.trim();
    if (normalized.isEmpty) {
      return const SpeechCommandCompleteness.incomplete('empty_transcript');
    }
    try {
      final plan = _smartInputEngine.parse(
        normalized,
        ref.read(categoryProvider),
        source: SmartInputSource.voice,
      );
      final accounts = ref
          .read(walletProvider)
          .map(
            (wallet) => SmartEntryAccount(
          id: wallet.id,
          name: wallet.name,
          type: wallet.walletType,
          availableBalance: 0,
          isBackup: wallet.isBackup,
        ),
      )
          .toList(growable: false);
      return _speechCompletenessEvaluator.evaluate(
        plan,
        accounts: accounts,
      );
    } catch (error) {
      debugPrint('Speech completeness check failed: $error');
      return const SpeechCommandCompleteness.incomplete('parse_failed');
    }
  }

  void _scheduleStableSpeechFinalization(
      String transcript,
      SpeechCommandCompleteness completeness, {
        required bool isFinal,
      }) {
    _speechStabilityTimer?.cancel();
    if (isFinal || !completeness.isComplete || transcript.isEmpty) return;

    final stableTranscript = transcript;
    _speechStabilityTimer = Timer(_speechStabilityWindow, () async {
      if (!mounted ||
          _restartingSpeech ||
          _speechSession.state != SpeechSessionState.listening ||
          _speechSession.latestDraft != stableTranscript) {
        return;
      }
      final currentCompleteness = _speechCompleteness(stableTranscript);
      final decision = _speechSession.recordTranscript(
        stableTranscript,
        isFinal: currentCompleteness.isComplete,
      );
      _traceSpeechEvent(
        'stable',
        transcript: stableTranscript,
        completeness: currentCompleteness,
      );
      if (decision.action == SpeechSessionAction.processFinal) {
        await _stopRecognizerThenApply(decision);
      }
    });
  }

  Future<void> _finishSpeechSession({bool manual = false}) async {
    if (!mounted) return;
    final transcript = _speechSession.latestDraft;
    final completeness = _speechCompleteness(transcript);
    final decision = completeness.isComplete && transcript.isNotEmpty
        ? _speechSession.recordTranscript(transcript, isFinal: true)
        : _speechSession.onRecognizerError(retryable: false);
    _traceSpeechEvent(
      manual ? 'manual_stop' : 'session_deadline',
      transcript: transcript,
      completeness: completeness,
    );
    if (decision.action == SpeechSessionAction.none &&
        _speechSession.state != SpeechSessionState.failed) {
      return;
    }
    await _stopRecognizerThenApply(decision);
  }

  Future<void> _stopRecognizerThenApply(
      SpeechSessionDecision decision,
      ) async {
    _cancelSpeechTimers();
    _restartingSpeech = true;
    try {
      await _speech.stop();
    } finally {
      _restartingSpeech = false;
    }
    if (!mounted) return;
    if (_isListening) setState(() => _isListening = false);
    await _applySpeechDecision(decision);
  }

  Future<void> _restartSpeechListening({bool advanceLocale = false}) async {
    if (!mounted || _restartingSpeech) return;
    _speechStabilityTimer?.cancel();
    _speechStartupTimer?.cancel();
    _restartingSpeech = true;
    try {
      await _speech.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      if (advanceLocale &&
          _speechLocaleCandidateIndex + 1 <
              _speechLocaleCandidates.length) {
        _speechLocaleCandidateIndex++;
      }
    } finally {
      _restartingSpeech = false;
    }
    if (!mounted) return;
    _handlingSpeechError = false;
    if (!_isListening) setState(() => _isListening = true);
    _traceSpeechEvent(
      'restart',
      transcript: _speechSession.latestDraft,
      completeness: _speechCompleteness(_speechSession.latestDraft),
    );
    await _startSpeechListening();
  }

  void _cancelSpeechTimers() {
    _speechStabilityTimer?.cancel();
    _speechStabilityTimer = null;
    _speechDeadlineTimer?.cancel();
    _speechDeadlineTimer = null;
    _speechStartupTimer?.cancel();
    _speechStartupTimer = null;
  }

  void _markRecognizerActive() {
    _recognizerReportedListening = true;
    _speechStartupTimer?.cancel();
    _speechStartupTimer = null;
  }

  Future<void> _handleSpeechStartupTimeout() async {
    if (!mounted ||
        _restartingSpeech ||
        _recognizerReportedListening ||
        _speechSession.state != SpeechSessionState.listening) {
      return;
    }
    final transcript = _speechSession.latestDraft;
    final completeness = _speechCompleteness(transcript);
    final decision = completeness.isComplete && transcript.isNotEmpty
        ? _speechSession.recordTranscript(transcript, isFinal: true)
        : _speechSession.onRecognizerError(retryable: true);
    _traceSpeechEvent(
      'startup_timeout',
      transcript: transcript,
      completeness: completeness,
    );
    await _applySpeechDecision(decision);
  }

  void _traceSpeechEvent(
      String event, {
        required String transcript,
        required SpeechCommandCompleteness completeness,
      }) {
    assert(() {
      debugPrint(
        '[Voice session] time=${DateTime.now().toIso8601String()} '
            'event=$event state=${_speechSession.state.name} '
            'retry=${_speechSession.retryCount} '
            'complete=${completeness.isComplete} '
            'reason=${completeness.reason} transcript="$transcript"',
      );
      return true;
    }());
  }

  Future<void> _handleSpeechError(String errorMessage) async {
    if (!mounted || _handlingSpeechError) return;
    if (_speechSession.state != SpeechSessionState.listening &&
        _speechSession.state != SpeechSessionState.finalizing) {
      return;
    }
    debugPrint('STT Error: $errorMessage');
    _handlingSpeechError = true;

    final normalized = errorMessage.toLowerCase();
    final recoverableEnd = normalized.contains('error_speech_timeout') ||
        normalized.contains('error_no_match') ||
        normalized.contains('error_client');
    final languageFailure =
        normalized.contains('error_language_unavailable') ||
            normalized.contains('error_language_not_supported');
    final canTryAnotherLocale = languageFailure &&
        _speechLocaleCandidateIndex + 1 < _speechLocaleCandidates.length;
    final decision = _speechSession.onRecognizerError(
      retryable: recoverableEnd || canTryAnotherLocale,
    );

    if (decision.action == SpeechSessionAction.retry) {
      await _restartSpeechListening(advanceLocale: canTryAnotherLocale);
      return;
    }

    _cancelSpeechTimers();
    setState(() => _isListening = false);

    if (decision.action == SpeechSessionAction.processFinal) {
      await _applySpeechDecision(decision);
      return;
    }

    if (normalized.contains('error_client')) {
      _speechInitialized = false;
    }

    final networkFailure =
        normalized.contains('error_network') ||
            normalized.contains('error_server') ||
            normalized.contains('error_too_many_requests');

    if (networkFailure) {
      _showTransactionError(
        _speechDraftMessage(
          'Voice recognition needs an internet connection on this phone. Connect to the internet or install an offline English language in Google voice typing. Typed Smart Entry still works.',
        ),
        title: 'Voice service is offline',
      );
      return;
    }

    if (languageFailure) {
      _showTransactionError(
        _speechDraftMessage(
          'No working speech language was found. Enable the Google app, select English in Google voice typing, and download its offline language pack.',
        ),
        title: 'Speech language unavailable',
      );
      return;
    }

    _showTransactionError(
      _speechDraftMessage(
        'Voice Log stopped before it received a final result. Please try again.',
      ),
      title: 'Voice Log stopped',
    );
  }

  String _speechDraftMessage(String message) {
    if (_smartInputCtrl.text.trim().isEmpty) return message;
    return '$message Your unfinished words were kept. Tap the microphone again and the next words will be merged with them.';
  }

  Future<void> _applySpeechDecision(SpeechSessionDecision decision) async {
    if (!mounted) return;
    switch (decision.action) {
      case SpeechSessionAction.processFinal:
        _cancelSpeechTimers();
        setState(() => _isListening = false);
        _speechSession.markProcessing();
        try {
          final succeeded = await _processNLP(
            decision.transcript,
            source: SmartInputSource.voice,
          );
          _speechSession.markCompleted();
          if (succeeded) {
            _smartInputCtrl.clear();
            _speechSession.reset();
          } else if (_smartInputCtrl.text.trim().isEmpty &&
              decision.transcript.trim().isNotEmpty) {
            final preservedText = decision.transcript.trim();
            _smartInputCtrl.value = TextEditingValue(
              text: preservedText,
              selection: TextSelection.collapsed(
                offset: preservedText.length,
              ),
            );
          }
        } catch (error) {
          _speechSession.markFailed();
          rethrow;
        }
        return;
      case SpeechSessionAction.preserveDraft:
        _cancelSpeechTimers();
        setState(() => _isListening = false);
        _showTransactionError(
          'The voice command was incomplete. Your words were kept—tap the microphone again and continue speaking.',
          title: 'Voice command incomplete',
        );
        return;
      case SpeechSessionAction.none:
        if (_speechSession.state == SpeechSessionState.failed) {
          _cancelSpeechTimers();
          if (_isListening) setState(() => _isListening = false);
          _showTransactionError(
            'Voice recognition stopped before hearing any words. Tap the microphone and try again.',
            title: 'Voice stopped too soon',
          );
        }
        return;
      case SpeechSessionAction.retry:
        await _restartSpeechListening();
        return;
    }
  }

  Future<void> _scanReceiptIntoInput() async {
    if (_isScanningReceipt) return;
    _dismissKeyboard();
    setState(() => _isScanningReceipt = true);
    try {
      final receipt = await OcrScannerService().scanReceiptDetailed();
      if (!mounted || receipt == null) return;

      if (receipt.total <= 0 && receipt.items.isEmpty) {
        _showTransactionError(
          'No reliable receipt items or total were detected. Retake the photo with the full receipt visible and good lighting.',
          title: 'Receipt details not found',
        );
        return;
      }

      final confirmed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ReceiptReviewScreen(receipt: receipt),
        ),
      );
      if (confirmed == true && mounted) {
        _showExpenseMessage(
          'The reviewed receipt was added to your records.',
          title: 'Receipt saved',
        );
      }
    } finally {
      if (mounted) setState(() => _isScanningReceipt = false);
    }
  }

  void _handleSpeechStatus(String status) {
    if (!mounted) return;
    if (status == 'listening') {
      _markRecognizerActive();
      return;
    }
    if (status != 'done' && status != 'notListening') return;
    if (_restartingSpeech) return;
    final startedAt = _speechListenStartedAt;
    final elapsed = startedAt == null
        ? null
        : DateTime.now().difference(startedAt);
    if (!_recognizerReportedListening &&
        elapsed != null &&
        elapsed < _prematureSpeechStatusGuard) {
      // Android may emit a stale `notListening` status while a new listen call
      // is still starting. The startup timer will retry if no real listening
      // status or transcript arrives.
      return;
    }
    _speechStartupTimer?.cancel();
    _speechStartupTimer = null;
    unawaited(_finalizeNormallyStoppedSpeech());
  }

  Future<void> _finalizeNormallyStoppedSpeech() async {
    // Several Android recognizers report `done` just before delivering their
    // final callback. Give it a chance to arrive. An incomplete transcript is
    // continued in a fresh recognizer cycle rather than promoted to a command.
    if (_finalizingRecognizerStop) return;
    _finalizingRecognizerStop = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!mounted || _restartingSpeech) return;
      final transcript = _speechSession.latestDraft;
      final completeness = _speechCompleteness(transcript);
      final decision = completeness.isComplete
          ? _speechSession.onRecognizerStopped()
          : _speechSession.onRecognizerError(retryable: true);
      _traceSpeechEvent(
        'recognizer_stopped',
        transcript: transcript,
        completeness: completeness,
      );
      await _applySpeechDecision(decision);
    } finally {
      _finalizingRecognizerStop = false;
    }
  }

  Future<Expense?> _showSmartEntryMatchPicker(
      List<SmartEntryTransaction> matches, {
        required bool deleting,
        bool repeating = false,
      }) async {
    final selectedWorkspaceId = ref.read(selectedWorkspaceIdProvider);
    final allEntries = ref
        .read(expenseProvider)
        .allExpenses
        .where((entry) => entry.workspaceId == selectedWorkspaceId);
    final entriesById = {
      for (final entry in allEntries) entry.id: entry,
    };
    final wallets = ref.read(walletProvider);
    final walletNames = {
      for (final wallet in wallets) wallet.id: wallet.name,
    };
    final candidates = matches
        .map((match) => entriesById[match.id])
        .whereType<Expense>()
        .toList(growable: false);
    if (candidates.isEmpty) return null;

    return showModalBottomSheet<Expense>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.68,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                  child: Row(
                    children: [
                      Icon(
                        deleting
                            ? Icons.delete_outline_rounded
                            : repeating
                            ? Icons.replay_rounded
                            : Icons.edit_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              deleting
                                  ? 'Choose entry to delete'
                                  : repeating
                                  ? 'Choose entry to repeat'
                                  : 'Choose entry to edit',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Several entries match your command.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: candidates.length,
                    separatorBuilder: (_, __) => const Divider(
                      height: 1,
                      indent: 72,
                    ),
                    itemBuilder: (context, index) {
                      final entry = candidates[index];
                      final isIncome = entry.type == 'income';
                      final walletName =
                          walletNames[entry.walletId] ?? 'Unknown wallet';
                      final dateLabel =
                      DateFormat('dd MMM, h:mm a').format(entry.date);
                      final amountLabel = entry.amount.toStringAsFixed(
                        entry.amount == entry.amount.truncateToDouble()
                            ? 0
                            : 2,
                      );
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: (isIncome
                              ? Colors.green
                              : Colors.red)
                              .withValues(alpha: 0.12),
                          child: Icon(
                            isIncome
                                ? Icons.south_west_rounded
                                : Icons.north_east_rounded,
                            color: isIncome ? Colors.green : Colors.red,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '$walletName · $dateLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          'Rs. $amountLabel',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onTap: () =>
                            Navigator.of(sheetContext).pop(entry),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleSmartEntryTransferCommand(
      ParsedSmartEntryCommand command,
      ) async {
    if (command.amount <= 0) {
      _showTransactionError(
        "Include an amount, for example: 'transfer 500 Cash to JazzCash'.",
        title: 'Transfer amount required',
      );
      return;
    }

    final wallets = ref.read(walletProvider);
    if (wallets.length < 2) {
      _showTransactionError(
        'Create at least two wallets before making a transfer.',
        title: 'Two wallets required',
      );
      return;
    }

    final walletNotifier = ref.read(walletProvider.notifier);
    final accounts = wallets
        .map(
          (wallet) => SmartEntryAccount(
        id: wallet.id,
        name: wallet.name,
        type: wallet.walletType,
        availableBalance:
        walletNotifier.getBalanceForWallet(wallet.id),
        isBackup: wallet.isBackup,
      ),
    )
        .toList(growable: false);
    final resolution = resolveSmartEntryTransferAccounts(
      command.rawInput,
      accounts,
    );
    if (resolution == null) {
      _showTransactionError(
        "Name both wallets, for example: 'transfer 500 Cash to JazzCash'.",
        title: 'Source and destination required',
      );
      return;
    }

    final transferConfidence = const ConfidenceEvaluator().evaluate(
      TransferCommand(
        parsed: command,
        source: SmartInputSource.typed,
      ),
      context: ConfidenceContext(
        hasExactAmount: command.amount > 0 &&
            (command.confidenceByField['amount'] ?? 0) >= 0.9,
        hasResolvedTransferSource: true,
        hasResolvedTransferDestination: true,
        transferDirectionConfidence: resolution.confidence,
      ),
    );
    if (!transferConfidence.canAutoExecute) {
      _showTransactionError(
        'I found both wallets but the transfer direction is not clear. Say “Cash se JazzCash me” or “Cash to JazzCash”.',
        title: 'Confirm transfer direction',
      );
      return;
    }

    final source = wallets.firstWhere(
          (wallet) => wallet.id == resolution.sourceAccountId,
    );
    final destination = wallets.firstWhere(
          (wallet) => wallet.id == resolution.destinationAccountId,
    );
    if (source.id == destination.id) {
      _showTransactionError(
        'Choose two different wallets.',
        title: 'Invalid transfer',
      );
      return;
    }

    final available = walletNotifier.getBalanceForWallet(source.id);
    if (command.amount > available + 0.000001) {
      _showTransactionError(
        'Available in ${source.name}: Rs. ${available.toStringAsFixed(0)}. '
            'Required: Rs. ${command.amount.toStringAsFixed(0)}.',
        title: 'Insufficient balance',
      );
      return;
    }

    final transferId = const Uuid().v4();
    final transferEntries = [
      Expense(
        id: '${transferId}_out',
        title: coreTransactionTitle('Transfer to ${destination.name}'),
        amount: command.amount,
        date: command.date,
        category: 'Transfer',
        colorValue: Colors.blue.toARGB32(),
        type: 'expense',
        walletId: source.id,
      ),
      Expense(
        id: '${transferId}_in',
        title: coreTransactionTitle('Transfer from ${source.name}'),
        amount: command.amount,
        date: command.date,
        category: 'Transfer',
        colorValue: Colors.blue.toARGB32(),
        type: 'income',
        walletId: destination.id,
      ),
    ];
    final execution = await ref
        .read(transactionExecutorProvider)
        .execute(CreateTransferCommand(
      outgoing: transferEntries.first,
      incoming: transferEntries.last,
    ));
    if (!mounted) return;
    if (!execution.succeeded) {
      _showTransactionError(
        'The source wallet changed or no longer has enough money.',
        title: 'Transfer not saved',
      );
      return;
    }

    _smartInputCtrl.clear();
    final transferAmount = command.amount.toStringAsFixed(
      command.amount == command.amount.truncateToDouble() ? 0 : 2,
    );
    _showTransferMessage(
      'Rs. $transferAmount · ${source.name} → ${destination.name}',
      title: 'Transfer completed',
      actionLabel: 'Undo',
      onAction: () async {
        await ref
            .read(transactionExecutorProvider)
            .execute(DeleteTransferCommand(transferId));
        if (!mounted) return;
        _showTransactionInfo(
          'The transfer was reversed.',
          title: 'Transfer undone',
        );
      },
    );
    unawaited(HapticFeedback.lightImpact());
  }

  Future<void> _handleSmartEntryRepeatCommand(
      ParsedSmartEntryCommand command,
      ) async {
    final wallets = ref.read(walletProvider);
    final walletNotifier = ref.read(walletProvider.notifier);
    final accounts = wallets
        .map(
          (wallet) => SmartEntryAccount(
        id: wallet.id,
        name: wallet.name,
        type: wallet.walletType,
        availableBalance: walletNotifier.getBalanceForWallet(wallet.id),
        isBackup: wallet.isBackup,
      ),
    )
        .toList(growable: false);
    final mentionedIds = findMentionedSmartEntryAccountIds(
      command.rawInput,
      accounts,
    );
    if (mentionedIds.length > 1) {
      _showTransactionError(
        'Mention only one wallet when selecting an entry to repeat.',
        title: 'Multiple wallets detected',
      );
      return;
    }

    final walletId = mentionedIds.isEmpty ? null : mentionedIds.single;
    SmartEntryAccount? mentionedAccount;
    for (final account in accounts) {
      if (account.id == walletId) mentionedAccount = account;
    }
    final selectedWorkspaceId = ref.read(selectedWorkspaceIdProvider);
    final allEntries = ref
        .read(expenseProvider)
        .allExpenses
        .where((entry) => entry.workspaceId == selectedWorkspaceId)
        .toList(growable: false);
    final match = matchSmartEntryTransaction(
      command: command,
      entries: allEntries.map(
            (entry) => SmartEntryTransaction(
          id: entry.id,
          title: entry.title,
          amount: entry.amount,
          category: entry.category,
          type: entry.type,
          date: entry.date,
          walletId: entry.walletId,
        ),
      ),
      walletId: walletId,
      ignoredTitlePhrases: mentionedAccount == null
          ? const []
          : [mentionedAccount.name, mentionedAccount.type],
    );
    if (match.status == SmartEntryMatchStatus.notFound) {
      _showTransactionError(
        'No safe matching entry was found. Add a title, amount, date, or wallet.',
        title: 'Entry not found',
      );
      return;
    }

    Expense? source;
    if (match.status == SmartEntryMatchStatus.unique) {
      final id = match.matches.single.id;
      for (final entry in allEntries) {
        if (entry.id == id) source = entry;
      }
    } else {
      source = await _showSmartEntryMatchPicker(
        match.matches,
        deleting: false,
        repeating: true,
      );
    }
    if (source == null || !mounted) return;

    final repeated = source.copyWith(
      id: const Uuid().v4(),
      date: DateTime.now(),
      title: coreTransactionTitle(source.title),
    );
    final execution = await ref
        .read(transactionExecutorProvider)
        .execute(CreateTransactionCommand(
      repeated,
      action: TransactionAction.repeat,
    ));
    if (!mounted) return;
    if (!execution.succeeded) {
      _showTransactionError(
        source.type == 'expense'
            ? 'The original wallet does not have enough balance to repeat this expense.'
            : 'The original wallet is no longer available.',
        title: 'Entry not repeated',
      );
      return;
    }

    _smartInputCtrl.clear();
    _showTopMessage(
      title: source.type == 'income' ? 'Income repeated' : 'Expense repeated',
      message: '${repeated.title} — Rs. ${repeated.amount.toStringAsFixed(0)}',
      tone: source.type == 'income'
          ? _MessageTone.income
          : _MessageTone.expense,
      actionLabel: 'Undo',
      onAction: () async {
        await ref
            .read(transactionExecutorProvider)
            .execute(DeleteTransactionCommand(repeated.id));
        if (!mounted) return;
        _showTransactionInfo(
          'The repeated entry was removed.',
          title: 'Repeat undone',
        );
      },
    );
    unawaited(_rememberSmartEntryPreference(repeated));
    unawaited(HapticFeedback.lightImpact());
  }

  void _handleSmartEntryQuery(ParsedSmartEntryCommand command) {
    final metric = command.queryMetric;
    if (metric == null) {
      _showTransactionInfo(
        "Ask something like 'how much did I spend this month?'",
        title: 'Question needs more detail',
      );
      return;
    }

    final wallets = ref.read(walletProvider);
    final walletNotifier = ref.read(walletProvider.notifier);
    final accounts = wallets
        .map(
          (wallet) => SmartEntryAccount(
        id: wallet.id,
        name: wallet.name,
        type: wallet.walletType,
        availableBalance: walletNotifier.getBalanceForWallet(wallet.id),
        isBackup: wallet.isBackup,
      ),
    )
        .toList(growable: false);
    final mentionedIds = findMentionedSmartEntryAccountIds(
      command.rawInput,
      accounts,
    );
    if (mentionedIds.length > 1) {
      _showTransactionError(
        'Mention one wallet at a time for a precise answer.',
        title: 'Multiple wallets detected',
      );
      return;
    }

    if (metric == SmartEntryQueryMetric.balance) {
      if (mentionedIds.isEmpty) {
        final total = wallets.fold<double>(
          0,
              (sum, wallet) => sum + walletNotifier.getBalanceForWallet(wallet.id),
        );
        _showTransactionInfo(
          'Rs. ${total.toStringAsFixed(0)} across ${wallets.length} wallet${wallets.length == 1 ? '' : 's'}.',
          title: 'Total wallet balance',
        );
      } else {
        final wallet = wallets.firstWhere(
              (item) => item.id == mentionedIds.single,
        );
        final balance = walletNotifier.getBalanceForWallet(wallet.id);
        _showTransactionInfo(
          'Rs. ${balance.toStringAsFixed(0)} available.',
          title: '${wallet.name} balance',
        );
      }
      _smartInputCtrl.clear();
      return;
    }

    var entries = ref
        .read(expenseProvider)
        .allExpenses
        .where(
          (entry) =>
              entry.workspaceId == ref.read(selectedWorkspaceIdProvider),
        )
        .where((entry) => entry.category != 'Transfer')
        .where((entry) => matchesSmartEntryTimeRange(
      entry.date,
      command.timeRange,
    ));
    if (mentionedIds.isNotEmpty) {
      final walletId = mentionedIds.single;
      entries = entries.where((entry) => entry.walletId == walletId);
    }
    final hasCategory = command.category != 'General' &&
        command.confidenceByField['category']! >= 0.8;
    if (hasCategory) {
      entries = entries.where((entry) => entry.category == command.category);
    } else {
      final title = _smartQueryTitle(command.title);
      if (title.isNotEmpty) {
        entries = entries.where(
              (entry) => entry.title.toLowerCase().contains(title.toLowerCase()),
        );
      }
    }
    final matching = entries.toList(growable: false);
    final income = matching
        .where((entry) => entry.type == 'income')
        .fold<double>(0, (sum, entry) => sum + entry.amount);
    final spending = matching
        .where((entry) => entry.type == 'expense')
        .fold<double>(0, (sum, entry) => sum + entry.amount);
    final period = _smartTimeRangeLabel(command.timeRange);
    final subject = hasCategory ? ' · ${command.category}' : '';

    switch (metric) {
      case SmartEntryQueryMetric.spending:
        _showTransactionInfo(
          '${matching.where((entry) => entry.type == 'expense').length} expense${matching.where((entry) => entry.type == 'expense').length == 1 ? '' : 's'}$subject.',
          title: 'Rs. ${spending.toStringAsFixed(0)} spent · $period',
        );
        break;
      case SmartEntryQueryMetric.income:
        _showTransactionInfo(
          '${matching.where((entry) => entry.type == 'income').length} income entr${matching.where((entry) => entry.type == 'income').length == 1 ? 'y' : 'ies'}$subject.',
          title: 'Rs. ${income.toStringAsFixed(0)} received · $period',
        );
        break;
      case SmartEntryQueryMetric.net:
        _showTransactionInfo(
          'Income Rs. ${income.toStringAsFixed(0)} · Expenses Rs. ${spending.toStringAsFixed(0)}.',
          title: 'Net Rs. ${(income - spending).toStringAsFixed(0)} · $period',
        );
        break;
      case SmartEntryQueryMetric.transactionCount:
        final type = command.entryTypeFilter;
        final count = type == null
            ? matching.length
            : matching.where((entry) => entry.type == type).length;
        _showTransactionInfo(
          '${type == null ? 'Income and expense' : type == 'income' ? 'Income' : 'Expense'} records$subject.',
          title: '$count transactions · $period',
        );
        break;
      case SmartEntryQueryMetric.balance:
        break;
    }
    _smartInputCtrl.clear();
  }

  void _handleSmartEntrySearch(ParsedSmartEntryCommand command) {
    final category = command.category != 'General' &&
        command.confidenceByField['category']! >= 0.8
        ? command.category
        : 'All';
    var query = _smartQueryTitle(command.title);
    if (category != 'All' &&
        query.toLowerCase() == category.toLowerCase()) {
      query = '';
    }
    setState(() {
      _currentView = 'Dashboard';
      _isSearching = true;
      _searchQuery = query;
      _selectedCategoryTab = category;
      _smartEntryTypeFilter = command.entryTypeFilter;
      _smartEntrySearchRange = command.timeRange;
      _smartEntrySearchAllHistory = true;
    });
    _smartInputCtrl.clear();
    _showTransactionInfo(
      'Close search to return to the normal monthly view.',
      title: 'Transaction filters applied',
    );
  }

  Future<void> _handleSmartEntryNavigation(
      ParsedSmartEntryCommand command,
      ) async {
    final target = command.navigationTarget;
    if (target == null) {
      _showTransactionInfo(
        'Try Home, Stats, Wallets, Udhaar, Mess Khata, Settings, or About.',
        title: 'Screen not recognized',
      );
      return;
    }
    _smartInputCtrl.clear();
    if (target == 'Wallets') {
      await _openIncomeAccounts();
      return;
    }
    await _changeView(target);
  }

  String _smartQueryTitle(String value) {
    final normalized = value.trim();
    const generic = {
      '',
      'Transaction',
      'Quick Expense',
      'Income Allowance',
      'Income / Allowance',
    };
    return generic.contains(normalized) ? '' : normalized;
  }

  String _smartTimeRangeLabel(SmartEntryTimeRange range) {
    switch (range) {
      case SmartEntryTimeRange.today:
        return 'today';
      case SmartEntryTimeRange.yesterday:
        return 'yesterday';
      case SmartEntryTimeRange.thisWeek:
        return 'this week';
      case SmartEntryTimeRange.lastWeek:
        return 'last week';
      case SmartEntryTimeRange.thisMonth:
        return 'this month';
      case SmartEntryTimeRange.lastMonth:
        return 'last month';
      case SmartEntryTimeRange.allTime:
        return 'all time';
    }
  }

  Future<void> _handleSmartEntryMutationCommand(
      SmartInputPlan plan,
      ) async {
    final command = plan.parsed;
    final mutation = plan.command as MutationCommand;
    final deleting = mutation.deleting;
    if (!deleting && mutation.patch.isEmpty) {
      _showTransactionError(
        "Say what to change, for example: 'change burger amount to 600' or 'headphones ka naam Kurch karo'.",
        title: 'Change required',
      );
      return;
    }
    if (mutation.patch.amount != null && mutation.patch.amount! <= 0) {
      _showTransactionError(
        'The new amount must be greater than zero.',
        title: 'Invalid amount',
      );
      return;
    }

    final wallets = ref.read(walletProvider);
    final walletNotifier = ref.read(walletProvider.notifier);
    final smartAccounts = wallets
        .map(
          (wallet) => SmartEntryAccount(
        id: wallet.id,
        name: wallet.name,
        type: wallet.walletType,
        availableBalance:
        walletNotifier.getBalanceForWallet(wallet.id),
        isBackup: wallet.isBackup,
      ),
    )
        .toList(growable: false);
    final mentionedWalletIds = findMentionedSmartEntryAccountIds(
      command.rawInput,
      smartAccounts,
    );
    if (mentionedWalletIds.length > 1) {
      _showTransactionError(
        'Mention only one wallet so the correct entry can be identified.',
        title: 'Multiple wallets detected',
      );
      return;
    }

    final mentionedWalletId = mentionedWalletIds.isEmpty
        ? null
        : mentionedWalletIds.single;
    SmartEntryAccount? mentionedAccount;
    if (mentionedWalletId != null) {
      for (final account in smartAccounts) {
        if (account.id == mentionedWalletId) {
          mentionedAccount = account;
          break;
        }
      }
    }

    final selectedWorkspaceId = ref.read(selectedWorkspaceIdProvider);
    final allEntries = ref
        .read(expenseProvider)
        .allExpenses
        .where((entry) => entry.workspaceId == selectedWorkspaceId)
        .toList(growable: false);
    final match = matchSmartEntryTransaction(
      command: command,
      entries: allEntries.map(
            (entry) => SmartEntryTransaction(
          id: entry.id,
          title: entry.title,
          amount: entry.amount,
          category: entry.category,
          type: entry.type,
          date: entry.date,
          walletId: entry.walletId,
        ),
      ),
      walletId: mentionedWalletId,
      ignoredTitlePhrases: mentionedAccount == null
          ? const []
          : [
        mentionedAccount.name,
        mentionedAccount.type,
        'cash in hand',
        'jazz cash',
        'jazzcash',
      ],
      selectorTitle: mutation.selector.title,
      selectorAmount: mutation.selector.amount,
      selectorDate: mutation.selector.date,
    );

    if (match.status == SmartEntryMatchStatus.notFound) {
      _showTransactionError(
        deleting
            ? 'No safe matching entry was found. Add a title, amount, date, or wallet.'
            : 'No safe matching entry was found. Name the entry you want to edit.',
        title: 'Entry not found',
      );
      return;
    }

    if (match.status == SmartEntryMatchStatus.unique) {
      final confidence = const ConfidenceEvaluator().evaluate(
        plan.command,
        context: ConfidenceContext(
          hasUniqueTarget: true,
          targetConfidence: match.confidence,
        ),
      );
      if (!confidence.canAutoExecute) {
        _showTransactionError(
          'The matching entry is not certain enough to change automatically. Add its amount, date, or wallet.',
          title: 'Review target entry',
        );
        return;
      }
    }

    Expense? target;
    if (match.status == SmartEntryMatchStatus.unique) {
      final targetId = match.matches.single.id;
      for (final entry in allEntries) {
        if (entry.id == targetId) {
          target = entry;
          break;
        }
      }
    } else {
      target = await _showSmartEntryMatchPicker(
        match.matches,
        deleting: deleting,
      );
    }
    if (target == null || !mounted) return;

    if (deleting) {
      if (target.type == 'income') {
        final available =
        walletNotifier.getBalanceForWallet(target.walletId);
        if (available + 0.000001 < target.amount) {
          _showTransactionError(
            'Deleting this income would make the wallet balance negative.',
            title: 'Income cannot be deleted',
          );
          return;
        }
      }

      final deleteResult = await ref
          .read(transactionExecutorProvider)
          .execute(DeleteTransactionCommand(target.id));
      if (!mounted) return;
      if (!deleteResult.succeeded) {
        _showTransactionError(
          'The entry changed before it could be deleted. Try again.',
          title: 'Entry not deleted',
        );
        return;
      }

      _smartInputCtrl.clear();
      final deletedEntry = target;
      final deletedAmount =
      deletedEntry.amount.toStringAsFixed(0);
      _showDeletionMessage(
        '${deletedEntry.title} — Rs. $deletedAmount',
        title: 'Entry moved to Trash',
        actionLabel: 'Undo',
        onAction: () async {
          final restoreResult = await ref
              .read(transactionExecutorProvider)
              .execute(RestoreTransactionCommand(deletedEntry.id));
          if (!mounted) return;
          if (restoreResult.succeeded) {
            _showTransactionInfo(
              'The deleted entry was restored.',
              title: 'Deletion undone',
            );
          } else {
            _showTransactionError(
              'The entry could not be restored because the wallet changed.',
              title: 'Undo failed',
            );
          }
        },
      );
      unawaited(HapticFeedback.lightImpact());
      return;
    }

    final originalEntry = target;
    String? updatedCategory = mutation.patch.category;
    if (updatedCategory != null) {
      final categories = ref.read(categoryProvider);
      final matches = categories.where(
            (category) =>
        category.toLowerCase() == updatedCategory!.toLowerCase(),
      );
      if (matches.isEmpty) {
        _showTransactionError(
          'Choose an existing category: ${categories.join(', ')}.',
          title: 'Category not found',
        );
        return;
      }
      updatedCategory = matches.first;
    }
    final updatedEntry = originalEntry.copyWith(
      amount: mutation.patch.amount,
      title: mutation.patch.title == null
          ? null
          : coreTransactionTitle(mutation.patch.title!),
      category: updatedCategory,
      date: mutation.patch.date,
      walletId: mutation.patch.walletId,
    );
    if (updatedEntry.amount == originalEntry.amount &&
        updatedEntry.title == originalEntry.title &&
        updatedEntry.category == originalEntry.category &&
        updatedEntry.date == originalEntry.date &&
        updatedEntry.walletId == originalEntry.walletId) {
      _showTransactionInfo(
        'The entry already has these details.',
        title: 'No change needed',
      );
      return;
    }

    final updateResult = await ref
        .read(transactionExecutorProvider)
        .execute(UpdateTransactionCommand(
      existingId: originalEntry.id,
      updated: updatedEntry,
    ));
    if (!mounted) return;
    if (!updateResult.succeeded) {
      _showTransactionError(
        'The wallet cannot support this change, or the entry changed. Review its balance and try again.',
        title: 'Entry not updated',
      );
      return;
    }

    _smartInputCtrl.clear();
    _showTransactionSuccess(
      '${updatedEntry.title} · Rs. ${updatedEntry.amount.toStringAsFixed(0)} · ${updatedEntry.category}',
      title: 'Entry updated',
      actionLabel: 'Undo',
      onAction: () async {
        final restoreResult = await ref
            .read(transactionExecutorProvider)
            .execute(UpdateTransactionCommand(
          existingId: originalEntry.id,
          updated: originalEntry,
        ));
        if (!mounted) return;
        if (restoreResult.succeeded) {
          _showTransactionInfo(
            'The previous amount was restored.',
            title: 'Edit undone',
          );
        } else {
          _showTransactionError(
            'The previous amount could not be restored because the wallet changed.',
            title: 'Undo failed',
          );
        }
      },
    );
    unawaited(HapticFeedback.lightImpact());
  }

  Future<bool> _processNLP(
      String text, {
        SmartInputSource source = SmartInputSource.typed,
      }) async {
    _dismissKeyboard();
    final normalized = text.trim();
    if (normalized.isEmpty) return false;

    final categories = ref.read(categoryProvider);
    final plan = _smartInputEngine.parse(
      normalized,
      categories,
      source: source,
    );
    _debugSmartInputPlan(plan);
    final command = plan.parsed;
    final canonicalInput = plan.normalizedText;
    if (!command.intent.isTransactionAddition) {
      if (command.intent == SmartEntryIntent.deleteEntry ||
          command.intent == SmartEntryIntent.editEntry) {
        await _handleSmartEntryMutationCommand(plan);
        return _smartInputCtrl.text.trim().isEmpty;
      }

      String message;
      String title;
      switch (command.intent) {
        case SmartEntryIntent.transfer:
          await _handleSmartEntryTransferCommand(command);
          return _smartInputCtrl.text.trim().isEmpty;
        case SmartEntryIntent.repeatEntry:
          await _handleSmartEntryRepeatCommand(command);
          return _smartInputCtrl.text.trim().isEmpty;
        case SmartEntryIntent.query:
          _handleSmartEntryQuery(command);
          return _smartInputCtrl.text.trim().isEmpty;
        case SmartEntryIntent.searchEntries:
          _handleSmartEntrySearch(command);
          return _smartInputCtrl.text.trim().isEmpty;
        case SmartEntryIntent.navigate:
          await _handleSmartEntryNavigation(command);
          return _smartInputCtrl.text.trim().isEmpty;
        case SmartEntryIntent.unknown:
          title = 'Command not recognized';
          message = 'Try an expense or income command with an amount.';
          break;
        case SmartEntryIntent.deleteEntry:
        case SmartEntryIntent.editEntry:
        case SmartEntryIntent.addExpense:
        case SmartEntryIntent.addIncome:
          return false;
      }
      _showTransactionInfo(message, title: title);
      return false;
    }

    final result = command.toLegacyMap();
    final learnedPreference = _learnedPreferenceFor(command.title);
    if (result['type'] == 'expense' &&
        result['category'] == 'General' &&
        learnedPreference != null &&
        categories.contains(learnedPreference.category)) {
      result['category'] = learnedPreference.category;
    }
    final amount = result['amount'];
    if (amount is! num || !amount.isFinite || amount <= 0) {
      _showTransactionError(
        "Include an amount, for example: '500 biryani' or '1.5k petrol from JazzCash'.",
        title: 'Amount not detected',
      );
      return false;
    }

    final wallets = ref.read(walletProvider);
    if (wallets.isEmpty) {
      _showTransactionError(
        'Create a Cash or JazzCash wallet before using Smart Entry.',
        title: 'Wallet required',
      );
      return false;
    }

    final type = result['type'] == 'income' ? 'income' : 'expense';
    final amountValue = amount.toDouble();
    final walletNotifier = ref.read(walletProvider.notifier);
    final smartAccounts = wallets
        .map(
          (wallet) => SmartEntryAccount(
        id: wallet.id,
        name: wallet.name,
        type: wallet.walletType,
        availableBalance:
        walletNotifier.getBalanceForWallet(wallet.id),
        isBackup: wallet.isBackup,
      ),
    )
        .toList(growable: false);
    final mentionedWalletId =
    findMentionedSmartEntryAccountId(canonicalInput, smartAccounts);
    final configuredDefaultWallet =
    _selectedSmartEntryWallet(wallets);
    String? learnedWalletId;
    if (mentionedWalletId == null && configuredDefaultWallet == null) {
      final candidateId = learnedPreference?.walletId;
      if (candidateId != null &&
          wallets.any((wallet) => wallet.id == candidateId)) {
        learnedWalletId = candidateId;
      }
    }
    final resolvedWalletId = resolveSmartEntryAccount(
      input: canonicalInput,
      accounts: smartAccounts,
      transactionType: type,
      amount: amountValue,
      preferredAccountId: configuredDefaultWallet?.id ?? learnedWalletId,
    );

    final semanticConfidence = const ConfidenceEvaluator().evaluate(
      plan.command,
      context: ConfidenceContext(
        hasResolvedWallet: resolvedWalletId != null,
        hasExactAmount:
        (command.confidenceByField['amount'] ?? 0) >= 0.9,
      ),
    );
    assert(() {
      debugPrint(
        '[SmartEntry confidence] '
            'disposition=${semanticConfidence.disposition} '
            'score=${semanticConfidence.score.toStringAsFixed(3)} '
            'reasons=${semanticConfidence.reasons.join(' | ')}',
      );
      return true;
    }());

    if (!plan.requiresAsrReview &&
        semanticConfidence.canAutoExecute &&
        shouldAutoSaveSmartEntry(
          result,
          hasResolvedWallet: resolvedWalletId != null,
          semanticConfidence: semanticConfidence.score,
        )) {
      final wallet = wallets.firstWhere(
            (item) => item.id == resolvedWalletId,
      );
      final entry = Expense(
        id: const Uuid().v4(),
        title: _smartEntryTitle(result, wallet, type),
        amount: amountValue,
        category: type == 'income'
            ? 'Income / Allowance'
            : result['category']?.toString() ?? 'General',
        date: result['date'] is DateTime
            ? result['date'] as DateTime
            : DateTime.now(),
        colorValue:
        Color(ref.read(settingsProvider).profileColorValue).toARGB32(),
        type: type,
        walletId: resolvedWalletId!,
      );

      final execution = await ref
          .read(transactionExecutorProvider)
          .execute(CreateTransactionCommand(entry));
      if (!mounted) return false;
      if (!execution.succeeded) {
        _showTransactionError(
          'The selected wallet changed or no longer has enough balance. Try the entry again.',
          title: 'Smart Entry not saved',
        );
        return false;
      }

      _smartInputCtrl.clear();
      FocusScope.of(context).unfocus();
      _showTopMessage(
        title: type == 'income' ? 'Income added' : 'Expense saved',
        message:
            '${entry.title} — Rs. ${entry.amount.toStringAsFixed(0)} · ${wallet.name}',
        tone: type == 'income' ? _MessageTone.income : _MessageTone.expense,
        actionLabel: 'Undo',
        onAction: () async {
          final deleteResult = await ref
              .read(transactionExecutorProvider)
              .execute(DeleteTransactionCommand(entry.id));
          if (!mounted) return;
          if (deleteResult.succeeded) {
            _showTransactionInfo(
              'The instant Smart Entry was removed.',
              title: 'Entry undone',
            );
          }
        },
      );
      unawaited(_rememberSmartEntryPreference(entry));
      unawaited(HapticFeedback.lightImpact());
      return true;
    }

    final defaultAccounts = smartAccounts.where((account) {
      final accountType = account.type.toLowerCase();
      return !account.isBackup &&
          (accountType == 'cash' || accountType == 'jazzcash');
    }).toList(growable: false);
    final defaultsAreEmpty = defaultAccounts.isEmpty ||
        defaultAccounts.every((account) => account.availableBalance <= 0);
    final reviewMessage = plan.requiresAsrReview
        ? 'Voice recognition corrected a similar-sounding financial word. Verify the title and amount before saving.'
        : resolvedWalletId != null &&
        !semanticConfidence.canAutoExecute
        ? 'Review the detected title, amount, category, date, and wallet before saving.'
        : mentionedWalletId != null
        ? 'The named wallet cannot cover this expense. Choose another wallet before saving.'
        : configuredDefaultWallet != null
        ? 'Your default wallet, ${configuredDefaultWallet.name}, cannot cover this expense. Choose another funded account.'
        : learnedWalletId != null
        ? 'The wallet previously used for this entry cannot cover it. Choose another funded wallet.'
        : defaultsAreEmpty
        ? 'Cash and JazzCash are empty. Choose the wallet that should receive or pay this entry.'
        : 'Cash and JazzCash cannot cover this amount. Choose another funded wallet.';

    final confirmed = await _showAddOrEditModal(
      prefilledAmount:
      amountValue == amountValue.truncateToDouble()
          ? amountValue.toStringAsFixed(0)
          : amountValue.toStringAsFixed(2),
      prefilledTitle: result['title']?.toString(),
      prefilledCategory: result['category']?.toString(),
      prefilledDate: result['date'] is DateTime
          ? result['date'] as DateTime
          : DateTime.now(),
      preselectedWalletId: mentionedWalletId ??
          configuredDefaultWallet?.id ??
          learnedWalletId,
      initialType: type,
      reviewMessage: reviewMessage,
    );

    if (confirmed == true && mounted) {
      _smartInputCtrl.clear();
      if (type == 'income') {
        _showIncomeMessage('The Smart Entry was saved to the selected wallet.');
      } else {
        _showExpenseMessage('The Smart Entry was saved to the selected wallet.');
      }
    }
    if (mounted) FocusScope.of(context).unfocus();
    return confirmed == true && mounted;
  }

  void _debugSmartInputPlan(SmartInputPlan plan) {
    assert(() {
      final smartCommand = plan.command;
      var selector = 'none';
      var patch = 'none';
      if (smartCommand is MutationCommand) {
        selector = '{title: ${smartCommand.selector.title}, '
            'amount: ${smartCommand.selector.amount}, '
            'date: ${smartCommand.selector.date}, '
            'type: ${smartCommand.selector.transactionType}}';
        patch = '{title: ${smartCommand.patch.title}, '
            'amount: ${smartCommand.patch.amount}, '
            'category: ${smartCommand.patch.category}, '
            'date: ${smartCommand.patch.date}, '
            'wallet: ${smartCommand.patch.walletId}}';
      }
      debugPrint(
        '[SmartEntry parse] original="${plan.originalText}" '
            'normalized="${plan.normalizedText}" '
            'intent=${plan.parsed.intent.wireName} '
            'selector=$selector patch=$patch '
            'amount=${plan.parsed.amount} title="${plan.parsed.title}" '
            'confidence=${plan.parsed.confidence.toStringAsFixed(3)} '
            'requiresAsrReview=${plan.requiresAsrReview}',
      );
      return true;
    }());
  }

  String _smartEntryTitle(
      Map<String, dynamic> result,
      Wallet wallet,
      String type,
      ) {
    var title = result['title']?.toString().trim() ?? '';
    final removable = <String>[
      wallet.name,
      wallet.walletType,
      'cash in hand',
      'jazz cash',
      'jazzcash',
    ];

    for (final phrase in removable) {
      final normalized = phrase.trim();
      if (normalized.isEmpty) continue;
      title = title.replaceAll(
        RegExp(
          '\\b${RegExp.escape(normalized)}\\b',
          caseSensitive: false,
        ),
        ' ',
      );
    }
    title = title
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'^(From|Via|Using)\s+', caseSensitive: false), '');

    if (title.isEmpty || title.toLowerCase() == 'quick expense') {
      if (type == 'income') return 'Income Allowance';
      final category = result['category']?.toString().trim() ?? '';
      final fallback = category.isEmpty || category.toLowerCase() == 'general'
          ? 'Quick Expense'
          : category;
      return coreTransactionTitle(fallback);
    }
    return coreTransactionTitle(title);
  }

}

String _normalizeLearningTitle(String value) {
  final normalized = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  const ignored = {
    '',
    'quick expense',
    'income allowance',
    'transaction',
    'general',
  };
  return ignored.contains(normalized) ? '' : normalized;
}

class _LearnedSmartEntryPreference {
  final String category;
  final String walletId;
  final int uses;
  final int updatedAt;

  const _LearnedSmartEntryPreference({
    required this.category,
    required this.walletId,
    required this.uses,
    required this.updatedAt,
  });

  static _LearnedSmartEntryPreference? fromStored(dynamic value) {
    if (value is! Map) return null;
    final category = value['category']?.toString().trim() ?? '';
    final walletId = value['walletId']?.toString().trim() ?? '';
    final uses = value['uses'];
    final updatedAt = value['updatedAt'];
    if (category.isEmpty || walletId.isEmpty) return null;
    return _LearnedSmartEntryPreference(
      category: category,
      walletId: walletId,
      uses: uses is num ? uses.toInt() : 1,
      updatedAt: updatedAt is num ? updatedAt.toInt() : 0,
    );
  }

  Map<String, dynamic> toStored() => {
    'category': category,
    'walletId': walletId,
    'uses': uses,
    'updatedAt': updatedAt,
  };
}


enum _MessageTone {
  error,
  deletion,
  expense,
  income,
  transfer,
  success,
  info,
  warning,
}

class _TopMessageCard extends StatelessWidget {
  final String title;
  final String message;
  final _MessageTone tone;
  final String? actionLabel;
  final Future<void> Function()? onAction;
  final VoidCallback onDismiss;

  const _TopMessageCard({
    required this.title,
    required this.message,
    required this.tone,
    required this.actionLabel,
    required this.onAction,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color accent;
    final Color background;
    final Color foreground;
    final IconData icon;

    switch (tone) {
      case _MessageTone.error:
        accent = scheme.error;
        background = scheme.errorContainer;
        foreground = scheme.onErrorContainer;
        icon = Icons.error_outline_rounded;
      case _MessageTone.deletion:
        accent = const Color(0xFFB91C1C);
        background = isDark ? const Color(0xFF3F1117) : const Color(0xFFFEF2F2);
        foreground = isDark ? const Color(0xFFFECACA) : const Color(0xFF7F1D1D);
        icon = Icons.delete_outline_rounded;
      case _MessageTone.expense:
        accent = const Color(0xFFDC2626);
        background = isDark ? const Color(0xFF35161A) : const Color(0xFFFFF1F2);
        foreground = isDark ? const Color(0xFFFDA4AF) : const Color(0xFF881337);
        icon = Icons.north_east_rounded;
      case _MessageTone.income:
        accent = const Color(0xFF16A34A);
        background = isDark ? const Color(0xFF123524) : const Color(0xFFF0FDF4);
        foreground = isDark ? const Color(0xFFDCFCE7) : const Color(0xFF14532D);
        icon = Icons.south_west_rounded;
      case _MessageTone.transfer:
        accent = const Color(0xFF2563EB);
        background = isDark ? const Color(0xFF12264B) : const Color(0xFFEFF6FF);
        foreground = isDark ? const Color(0xFFDBEAFE) : const Color(0xFF1E3A8A);
        icon = Icons.swap_horiz_rounded;
      case _MessageTone.success:
        accent = const Color(0xFF16A34A);
        background = isDark ? const Color(0xFF123524) : const Color(0xFFF0FDF4);
        foreground = isDark ? const Color(0xFFDCFCE7) : const Color(0xFF14532D);
        icon = Icons.check_circle_outline_rounded;
      case _MessageTone.info:
        accent = scheme.primary;
        background = scheme.primaryContainer;
        foreground = scheme.onPrimaryContainer;
        icon = Icons.info_outline_rounded;
      case _MessageTone.warning:
        accent = const Color(0xFFD97706);
        background = isDark ? const Color(0xFF3A260B) : const Color(0xFFFFFBEB);
        foreground = isDark ? const Color(0xFFFDE68A) : const Color(0xFF78350F);
        icon = Icons.warning_amber_rounded;
    }

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, -14 * (1 - value)),
          child: child,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Material(
          color: Colors.transparent,
          child: Semantics(
            container: true,
            liveRegion: true,
            label: '$title. $message',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accent.withValues(alpha: 0.28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.14),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: accent, size: 21),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: foreground,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          message,
                          style: TextStyle(
                            color: foreground.withValues(alpha: 0.82),
                            fontSize: 13,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (actionLabel != null && onAction != null) ...[
                          const SizedBox(height: 7),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: accent,
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 30),
                              tapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () async {
                              onDismiss();
                              await onAction!();
                            },
                            child: Text(
                              actionLabel!,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Dismiss message',
                    onPressed: onDismiss,
                    icon: Icon(
                      Icons.close_rounded,
                      color: foreground.withValues(alpha: 0.65),
                      size: 19,
                    ),
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

String _mergeSpeechTranscripts(String previous, String next) {
  final left = previous.trim();
  final right = next.trim();
  if (left.isEmpty) return right;
  if (right.isEmpty) return left;

  final leftWords = left.split(RegExp(r'\s+'));
  final rightWords = right.split(RegExp(r'\s+'));
  final maximumOverlap = leftWords.length < rightWords.length
      ? leftWords.length
      : rightWords.length;
  var overlap = 0;

  for (var size = maximumOverlap; size > 0; size--) {
    var matches = true;
    for (var index = 0; index < size; index++) {
      final leftWord = leftWords[leftWords.length - size + index];
      final rightWord = rightWords[index];
      if (leftWord.toLowerCase() != rightWord.toLowerCase()) {
        matches = false;
        break;
      }
    }
    if (matches) {
      overlap = size;
      break;
    }
  }

  return [...leftWords, ...rightWords.skip(overlap)].join(' ');
}

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double minHeight;
  final double maxHeight;
  final Widget child;
  _StickyHeaderDelegate({required this.minHeight, required this.maxHeight, required this.child});
  @override double get minExtent => minHeight;
  @override double get maxExtent => maxHeight;
  @override Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => SizedBox.expand(child: child);
  @override bool shouldRebuild(_StickyHeaderDelegate oldDelegate) => maxHeight != oldDelegate.maxHeight || minHeight != oldDelegate.minHeight || child != oldDelegate.child;
}

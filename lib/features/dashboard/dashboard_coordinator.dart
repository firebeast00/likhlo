part of '../../screens/home_screen.dart';

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin {
  static const platform = MethodChannel('com.likhlo/quick_tile');
  static const _smartEntryDefaultAccountKey =
      'smart_entry_default_wallet_id';
  static const _homeVisibleWalletsKey = 'home_visible_wallet_ids_v1';
  static const _smartEntryLearningKey = 'smart_entry_learning_v1';
  DateTime _focusedMonth = DateTime.now();
  String _selectedCategoryTab = 'All';
  bool _isSearching = false;
  String _searchQuery = "";
  String? _smartEntryTypeFilter;
  SmartEntryTimeRange? _smartEntrySearchRange;
  bool _smartEntrySearchAllHistory = false;
  final ScrollController _categoryScrollCtrl = ScrollController();
  final PrimaryLedgerTabsController _primaryTabsController =
      PrimaryLedgerTabsController();
  PrimaryLedgerTab _activePrimaryTab = PrimaryLedgerTab.main;

  late AnimationController _fabController;
  late Animation<double> _fabScale;

  final VoiceEntryController _voiceEntry = VoiceEntryController();
  final FeedbackCoordinator _feedback = FeedbackCoordinator();
  bool _isListening = false;
  bool _handlingSpeechError = false;
  bool _restartingSpeech = false;
  bool _speechInitialized = false;
  bool _speechLocalesLoaded = false;
  String? _speechLocaleLanguage;
  List<String?> _speechLocaleCandidates = const [null];
  int _speechLocaleCandidateIndex = 0;
  bool _isScanningReceipt = false;
  final TextEditingController _smartInputCtrl = TextEditingController();
  String? _smartEntryDefaultWalletId;
  List<String> _homeVisibleWalletIds = const [];
  final Map<String, _LearnedSmartEntryPreference>
  _learnedSmartEntryPreferences = {};
  Timer? _notificationUpdateTimer;
  Timer? _speechStabilityTimer;
  Timer? _speechDeadlineTimer;
  Timer? _speechStartupTimer;
  DateTime? _speechListenStartedAt;
  bool _recognizerReportedListening = false;
  bool _finalizingRecognizerStop = false;
  bool _isProcessingVoiceCommand = false;

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

    NotificationService().onActionTriggered = _handleNotificationAction;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pendingAction = NotificationService().takePendingAction();
      if (pendingAction != null) _handleNotificationAction(pendingAction);

      unawaited(_recoverLostReceiptScan());

      _queuePersistentNotificationUpdate(
        delay: const Duration(seconds: 2),
      );
    });
  }

  @override
  void dispose() {
    NotificationService().onActionTriggered = null;
    _voiceEntry.speech.cancel();
    _fabController.dispose();
    _notificationUpdateTimer?.cancel();
    _speechStabilityTimer?.cancel();
    _speechDeadlineTimer?.cancel();
    _speechStartupTimer?.cancel();
    _feedback.dispose();
    _categoryScrollCtrl.dispose();
    _primaryTabsController.dispose();
    _smartInputCtrl.dispose();
    super.dispose();
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
    final currentSection = ref.watch(appNavigationProvider);

    if (currentSection != AppSection.dashboard) {
      return AppShell(
        currentSection: currentSection,
        onSectionChanged: _changeSection,
      );
    }

    final ledger = ref.watch(monthlyLedgerProvider(_focusedMonth));
    final categories = ref.watch(categoryProvider);
    final wallets = ref.watch(walletProvider);
    final allExpenses = ref.watch(
      expenseProvider.select((state) => state.allExpenses),
    );

    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final monthlyTransactions = ledger.transactions;
    final globalSpent = ledger.spent;

    final walletNotifier = ref.read(walletProvider.notifier);
    final totalAvailable = wallets.fold<double>(
      0,
      (sum, wallet) => sum + walletNotifier.getBalanceForWallet(wallet.id),
    );
    final showMoneySetup =
        totalAvailable.abs() < 0.000001 && allExpenses.isEmpty;

    var displayExpenses = List<Expense>.from(
      _isSearching && _smartEntrySearchAllHistory
          ? visibleTransactions(allExpenses)
          : monthlyTransactions,
    );

    if (_selectedCategoryTab != 'All' &&
        !categories.contains(_selectedCategoryTab)) {
      _selectedCategoryTab = 'All';
    }

    if (_selectedCategoryTab != 'All') {
      displayExpenses = displayExpenses
          .where((entry) => entry.category == _selectedCategoryTab)
          .toList();
    }
    if (_searchQuery.isNotEmpty) {
      displayExpenses = displayExpenses
          .where(
            (entry) =>
                entry.title.toLowerCase().contains(_searchQuery.toLowerCase()),
          )
          .toList();
    }
    if (_smartEntryTypeFilter != null) {
      displayExpenses = displayExpenses
          .where((entry) => entry.type == _smartEntryTypeFilter)
          .toList();
    }
    if (_smartEntrySearchRange != null) {
      displayExpenses = displayExpenses
          .where(
            (entry) => matchesSmartEntryTimeRange(
              entry.date,
              _smartEntrySearchRange!,
            ),
          )
          .toList();
    }

    return AppShell(
      currentSection: currentSection,
      onSectionChanged: _changeSection,
      dashboardAppBar: DashboardAppBar(
        activeTab: _activePrimaryTab,
        isSearching: _isSearching,
        onSearchChanged: (value) => setState(() => _searchQuery = value),
        onBeforeOpenDrawer: _dismissKeyboard,
        onOpenWallets: _openIncomeAccounts,
        onToggleSearch: () {
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
      dashboardBody: DashboardScreen(
        controller: _primaryTabsController,
        onTabChanged: (tab) {
          if (!mounted || _activePrimaryTab == tab) return;
          setState(() {
            _activePrimaryTab = tab;
            if (tab == PrimaryLedgerTab.udhar) {
              _isSearching = false;
              _searchQuery = '';
              _smartEntryTypeFilter = null;
              _smartEntrySearchRange = null;
              _smartEntrySearchAllHistory = false;
            }
          });
        },
        isLandscape: isLandscape,
        isSearching: _isSearching,
        moneySetupCard:
            showMoneySetup ? _buildMoneySetupCard(primaryColor) : null,
        monthSelector: _buildMonthSelector(isDark),
        heroCard: _buildHeroCard(
          totalAvailable,
          globalSpent,
          wallets,
          primaryColor,
        ),
        smartInputBar: _buildSmartInputBar(primaryColor, isDark, wallets),
        categoryTabs: _buildCategoryTabsWidget(
          categories,
          primaryColor,
          isDark,
        ),
        transactionListBuilder: (isSliver) => _buildExpenseList(
          displayExpenses,
          primaryColor,
          isDark,
          isSliver: isSliver,
        ),
      ),
      dashboardFloatingActionButton:
          _activePrimaryTab == PrimaryLedgerTab.main
              ? GestureDetector(
                  onTapDown: (_) => _fabController.forward(),
                  onTapUp: (_) {
                    _fabController.reverse();
                    _showAddOrEditModal();
                  },
                  onTapCancel: () => _fabController.reverse(),
                  child: ScaleTransition(
                    scale: _fabScale,
                    child: Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            primaryColor,
                            primaryColor.withValues(alpha: 0.8),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Add Transaction',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : null,
    );
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

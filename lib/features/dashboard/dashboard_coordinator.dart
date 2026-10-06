part of '../../screens/home_screen.dart';

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin {
  static const platform = MethodChannel('com.likhlo/quick_tile');
  static const _smartEntryDefaultAccountKey =
      'smart_entry_default_wallet_id';
  static const _homeVisibleWalletsKey = 'home_visible_wallet_ids_v1';
  static const _smartEntryLearningKey = 'smart_entry_learning_v1';
  DateTime _focusedMonth = DateTime.now();
  String _selectedCategoryTab = 'All';
  final ValueNotifier<String> _categorySelectionNotifier =
      ValueNotifier<String>('All');
  bool _isSearching = false;
  String _searchQuery = "";
  final ValueNotifier<String> _searchQueryNotifier = ValueNotifier<String>('');
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
  final SpeechNetworkRecovery _speechNetworkRecovery = SpeechNetworkRecovery();
  int _speechAttempt = 0;
  String? _voiceDiagnosticId;
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
  final ValueNotifier<int> _smartInputUiRevision = ValueNotifier<int>(0);
  final TextEditingController _smartInputCtrl = TextEditingController();
  String? _smartEntryDefaultWalletId;
  List<String> _homeVisibleWalletIds = const [];
  final Map<String, _LearnedSmartEntryPreference>
  _learnedSmartEntryPreferences = {};
  Timer? _notificationUpdateTimer;
  Timer? _audioWarmupTimer;
  Timer? _speechStabilityTimer;
  String _speechStableTranscript = '';
  String _speechStableReason = '';
  Timer? _speechDeadlineTimer;
  Timer? _speechStartupTimer;
  DateTime? _speechListenStartedAt;
  bool _recognizerReportedListening = false;
  bool _finalizingRecognizerStop = false;
  bool _isProcessingVoiceCommand = false;

  void _setListening(bool value) {
    if (_isListening == value) return;
    _isListening = value;
    _smartInputUiRevision.value++;
  }

  void _setScanningReceipt(bool value) {
    if (_isScanningReceipt == value) return;
    _isScanningReceipt = value;
    _smartInputUiRevision.value++;
  }

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
          _listenForExpense(entryPoint: 'quick_action');
        } else if (shortcutType == 'action_add_expense') {
          _showAddOrEditModal();
        }
      });
    });

    quickActions.setShortcutItems(<ShortcutItem>[
      ShortcutItem(type: 'action_voice_log', localizedTitle: AppStrings.current.text('voice_log_250101'), icon: 'ic_mic'),
      ShortcutItem(type: 'action_add_expense', localizedTitle: AppStrings.current.text('add_transaction_ea77fd'), icon: 'ic_add'),
    ]);
    _setupNativeQuickTile();

    NotificationService().onActionTriggered = _handleNotificationAction;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _audioWarmupTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) unawaited(AudioFeedbackService().prepare());
      });

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
    VoiceDiagnosticsService.instance.finish(_voiceDiagnosticId, 'interrupted', reason: 'screen_disposed');
    _audioWarmupTimer?.cancel();
    NotificationService().onActionTriggered = null;
    _voiceEntry.speech.cancel();
    _fabController.dispose();
    _notificationUpdateTimer?.cancel();
    _speechStabilityTimer?.cancel();
    _speechDeadlineTimer?.cancel();
    _speechStartupTimer?.cancel();
    _feedback.dispose();
    _categoryScrollCtrl.dispose();
    _categorySelectionNotifier.dispose();
    _primaryTabsController.dispose();
    _searchQueryNotifier.dispose();
    _smartInputUiRevision.dispose();
    _smartInputCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppStrings.of(context);
    ref.listen<PersistentNotificationSnapshot>(
      persistentNotificationSnapshotProvider,
      (_, next) {
        _queuePersistentNotificationUpdate(snapshot: next);
      },
    );

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final currentSection = ref.watch(appNavigationProvider);

    if (currentSection != AppSection.dashboard) {
      return AppShell(
        currentSection: currentSection,
        onSectionChanged: _changeSection,
      );
    }

    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final showMoneySetup = ref.watch(showMoneySetupProvider);

    return AppShell(
      currentSection: currentSection,
      onSectionChanged: _changeSection,
      dashboardAppBar: DashboardAppBar(
        activeTab: _activePrimaryTab,
        isSearching: _isSearching,
        onSearchChanged: (value) {
          _searchQuery = value;
          _searchQueryNotifier.value = value;
        },
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
          if (!_isSearching) _searchQueryNotifier.value = '';
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
          if (tab == PrimaryLedgerTab.udhar) {
            _searchQueryNotifier.value = '';
          }
        },
        isLandscape: isLandscape,
        isSearching: _isSearching,
        moneySetupCard:
            showMoneySetup ? _buildMoneySetupCard(primaryColor) : null,
        monthSelector: _buildMonthSelector(isDark),
        heroCard: _DashboardHeroSection(
          owner: this,
          focusedMonth: _focusedMonth,
        ),
        smartInputBar: _DashboardSmartInputSection(owner: this),
        categoryTabs: _DashboardCategorySection(owner: this),
        transactionListBuilder: (isSliver) => _DashboardTransactionSection(
          owner: this,
          focusedMonth: _focusedMonth,
          typeFilter: _smartEntryTypeFilter,
          searchRange: _smartEntrySearchRange,
          searchAllHistory:
              _isSearching && _smartEntrySearchAllHistory,
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                          SizedBox(width: 8),
                          Text(
                            AppStrings.current.text('add_transaction_ea77fd'),
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

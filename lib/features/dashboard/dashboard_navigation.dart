part of '../../screens/home_screen.dart';

extension _DashboardNavigationMethods on _HomeScreenState {
  void _changeSection(AppSection section) {
    _dismissKeyboard();
    if (!mounted || section == ref.read(appNavigationProvider)) return;
    setState(() {
      _isSearching = false;
      _searchQuery = '';
      _smartEntryTypeFilter = null;
      _smartEntrySearchRange = null;
      _smartEntrySearchAllHistory = false;
    });
    ref.read(appNavigationProvider.notifier).open(section);
  }

  void _openPrimaryLedgerTab(PrimaryLedgerTab tab) {
    _dismissKeyboard();
    if (!mounted) return;
    ref.read(appNavigationProvider.notifier).openDashboard();
    setState(() {
      _activePrimaryTab = tab;
      _isSearching = false;
      _searchQuery = '';
      _smartEntryTypeFilter = null;
      _smartEntrySearchRange = null;
      _smartEntrySearchAllHistory = false;
    });
    _primaryTabsController.select(tab);
    if (tab == PrimaryLedgerTab.main) {
      _queuePersistentNotificationUpdate();
    }
  }

  Future<void> _openIncomeAccounts() async {
    _dismissKeyboard();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const IncomeAccountsScreen()),
    );
    if (mounted) _queuePersistentNotificationUpdate();
  }


}

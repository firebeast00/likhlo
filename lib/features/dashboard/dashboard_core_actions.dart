part of '../../screens/home_screen.dart';

extension _DashboardCoreActions on _HomeScreenState {
  void _queuePersistentNotificationUpdate({
    Duration delay = const Duration(milliseconds: 700),
    PersistentNotificationSnapshot? snapshot,
  }) {
    _notificationUpdateTimer?.cancel();
    _notificationUpdateTimer = Timer(delay, () async {
      if (!mounted) return;
      final PersistentNotificationSnapshot current =
          snapshot ?? ref.read(persistentNotificationSnapshotProvider);
      await NotificationService().updatePersistentStatusBarWidget(
        remainingToday: current.remainingToday,
        spentToday: current.spentToday,
      );
    });
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _loadSmartEntryLearning() {
    final stored = Hive.box('preferences').get(_HomeScreenState._smartEntryLearningKey);
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
        _HomeScreenState._smartEntryLearningKey,
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


}

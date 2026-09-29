part of '../../screens/home_screen.dart';

extension _DashboardNotificationMethods on _HomeScreenState {
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
              'Speak one complete expense, income, or transfer. A failed attempt is discarded so the next command starts clean.',
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
    _HomeScreenState.platform.invokeMethod<String>('getQuickAction').then((action) {
      if (action == 'add_expense') {
        Future.delayed(const Duration(milliseconds: 500), () => _showAddOrEditModal());
      }
    }).catchError((Object error) {
      debugPrint("Quick Tile Error: $error");
      return null;
    });

    _HomeScreenState.platform.setMethodCallHandler((call) async {
      if (call.method == 'triggerAction' && call.arguments == 'add_expense') {
        _showAddOrEditModal();
      }
    });
  }


}

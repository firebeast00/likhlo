part of '../../screens/home_screen.dart';

extension _DashboardWalletActionMethods on _HomeScreenState {
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


}

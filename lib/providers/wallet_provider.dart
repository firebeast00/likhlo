import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/wallet_model.dart';
import 'expense_provider.dart';

class WalletNotifier extends StateNotifier<List<Wallet>> {
  final Box<Wallet> _box = Hive.box<Wallet>('wallets');
  final Ref _ref;

  WalletNotifier(this._ref) : super([]) {
    _loadWallets();
  }

  void _loadWallets() {
    if (_box.isEmpty) {
      final initialWallets = [
        Wallet(
            id: 'default_cash',
            name: 'Cash in Hand',
            balance: 0.0,
            isBackup: false,
            colorValue: 0xFF10B981,
            walletType: 'cash'),
        Wallet(
            id: 'default_jazzcash',
            name: 'JazzCash',
            balance: 0.0,
            isBackup: false,
            colorValue: 0xFFEF4444,
            walletType: 'jazzcash'),
        Wallet(
            id: 'default_bank',
            name: 'Bank Account',
            balance: 0.0,
            isBackup: false,
            colorValue: 0xFF3B82F6,
            walletType: 'bank'),
        Wallet(
            id: 'default_backup',
            name: 'Emergency Stash',
            balance: 0.0,
            isBackup: true,
            colorValue: 0xFFF59E0B,
            walletType: 'reserve'),
      ];
      for (var w in initialWallets) {
        _box.put(w.id, w);
      }
    }
    state = _box.values.toList();
  }

  bool nameExists(String name, {String? excludingId}) {
    final normalized = name.trim().toLowerCase();
    return state.any(
      (wallet) =>
          wallet.id != excludingId &&
          wallet.name.trim().toLowerCase() == normalized,
    );
  }

  Future<bool> addWallet(Wallet wallet) async {
    if (wallet.name.trim().isEmpty ||
        !wallet.balance.isFinite ||
        wallet.balance < 0 ||
        nameExists(wallet.name)) {
      return false;
    }
    await _box.put(wallet.id, wallet);
    state = _box.values.toList();
    return true;
  }

  Future<bool> updateWallet(
    Wallet wallet, {
    double? currentBalance,
  }) async {
    if (wallet.name.trim().isEmpty ||
        nameExists(wallet.name, excludingId: wallet.id) ||
        (currentBalance != null &&
            (!currentBalance.isFinite || currentBalance < 0))) {
      return false;
    }

    var updatedWallet = wallet;
    if (currentBalance != null) {
      final storedWallet = _box.get(wallet.id);
      if (storedWallet == null) return false;
      final balanceAdjustment = currentBalance - getBalanceForWallet(wallet.id);
      updatedWallet = wallet.copyWith(
        balance: storedWallet.balance + balanceAdjustment,
      );
    }

    await _box.put(wallet.id, updatedWallet);
    state = _box.values.toList();
    return true;
  }

  Future<bool> deleteWallet(String id) async {
    if (state.length <= 1 || !_box.containsKey(id)) return false;
    await _box.delete(id);
    state = _box.values.toList();
    return true;
  }

  double getBalanceForWallet(String walletId) {
    final wallet = _box.get(walletId);
    if (wallet == null) return 0.0;
    return wallet.balance +
        (_ref.read(walletMovementsProvider)[walletId] ?? 0.0);
  }

  Future<void> clearBalance(String walletId) async {
    final wallet = _box.get(walletId);
    if (wallet == null) return;

    final currentBalance = getBalanceForWallet(walletId);
    await _box.put(
      walletId,
      wallet.copyWith(balance: wallet.balance - currentBalance),
    );
    state = _box.values.toList();
  }
}

final walletProvider =
    StateNotifierProvider<WalletNotifier, List<Wallet>>((ref) {
  return WalletNotifier(ref);
});


final walletBalanceProvider =
    Provider.family<double, String>((ref, walletId) {
  final openingBalance = ref.watch(
    walletProvider.select((wallets) {
      for (final wallet in wallets) {
        if (wallet.id == walletId) return wallet.balance;
      }
      return 0.0;
    }),
  );
  final movement = ref.watch(walletMovementProvider(walletId));
  return openingBalance + movement;
});

final totalAvailableProvider = Provider<double>((ref) {
  final wallets = ref.watch(walletProvider);
  final movements = ref.watch(walletMovementsProvider);
  return wallets.fold<double>(
    0,
    (sum, wallet) => sum + wallet.balance + (movements[wallet.id] ?? 0.0),
  );
});

final walletCountProvider = Provider<int>((ref) {
  return ref.watch(walletProvider.select((wallets) => wallets.length));
});

typedef PersistentNotificationSnapshot = ({
  double remainingToday,
  double spentToday,
});

final persistentNotificationSnapshotProvider =
    Provider<PersistentNotificationSnapshot>((ref) {
  return (
    remainingToday: ref.watch(totalAvailableProvider),
    spentToday: ref.watch(todaySpentProvider),
  );
});


final showMoneySetupProvider = Provider<bool>((ref) {
  final total = ref.watch(totalAvailableProvider);
  final count = ref.watch(activeTransactionCountProvider);
  return total.abs() < 0.000001 && count == 0;
});

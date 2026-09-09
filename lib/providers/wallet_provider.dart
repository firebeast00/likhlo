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
        Wallet(id: 'default_cash', name: 'Cash in Hand', balance: 0.0, isBackup: false, colorValue: 0xFF10B981, walletType: 'cash'),
        Wallet(id: 'default_jazzcash', name: 'JazzCash', balance: 0.0, isBackup: false, colorValue: 0xFFEF4444, walletType: 'jazzcash'),
        Wallet(id: 'default_bank', name: 'Bank Account', balance: 0.0, isBackup: false, colorValue: 0xFF3B82F6, walletType: 'bank'),
        Wallet(id: 'default_backup', name: 'Emergency Stash', balance: 0.0, isBackup: true, colorValue: 0xFFF59E0B, walletType: 'reserve'),
      ];
      for (var w in initialWallets) {
        _box.put(w.id, w);
      }
    }
    state = _box.values.toList();
  }

  void addWallet(Wallet wallet) {
    _box.put(wallet.id, wallet);
    state = _box.values.toList();
  }

  void updateWallet(Wallet wallet) {
    _box.put(wallet.id, wallet);
    state = _box.values.toList();
  }

  void deleteWallet(String id) {
    _box.delete(id);
    state = _box.values.toList();
  }

  double getBalanceForWallet(String walletId) {
    final expenses = _ref.read(expenseProvider).allExpenses;

    double totalIncome = expenses
        .where((e) => e.walletId == walletId && e.type == 'income')
        .fold(0.0, (sum, e) => sum + e.amount);

    double totalExpense = expenses
        .where((e) => e.walletId == walletId && e.type == 'expense')
        .fold(0.0, (sum, e) => sum + e.amount);

    return totalIncome - totalExpense;
  }
}

final walletProvider = StateNotifierProvider<WalletNotifier, List<Wallet>>((ref) {
  return WalletNotifier(ref);
});
import 'package:hive_flutter/hive_flutter.dart';

import '../models/debt_model.dart';
import '../models/expense_model.dart';

Set<String> linkedUdharLedgerIds() {
  if (!Hive.isBoxOpen('debts')) return const {};
  return {
    for (final debt in Hive.box<DebtEntry>('debts').values) ...[
      debt.id,
      UdharLedgerLinkService.settlementId(debt.id),
    ],
  };
}

/// Keeps debt metadata in step with the ledger without treating ordinary
/// transactions whose category happens to be Udhaar as linked debt records.
class UdharLedgerLinkService {
  const UdharLedgerLinkService();

  static String settlementId(String debtId) => '${debtId}_settlement';

  static String personFromTitle(String title) => title.replaceFirst(
    RegExp(r'^(?:udhaar:\s*|borrowed from\s*)', caseSensitive: false),
    '',
  ).trim();

  Box<DebtEntry>? get _box =>
      Hive.isBoxOpen('debts') ? Hive.box<DebtEntry>('debts') : null;

  DebtEntry? find(String id) {
    final box = _box;
    if (box == null) return null;
    for (final debt in box.values) {
      if (debt.id == id) return debt;
    }
    return null;
  }

  Future<void> updated(Expense entry) async {
    final debt = find(entry.id);
    if (debt == null) return;
    final name = personFromTitle(entry.title);
    await _box!.put(
      debt.key ?? debt.id,
      debt.copyWith(
        borrowerName: name.isEmpty ? debt.borrowerName : name,
        amount: entry.amount,
        type: entry.type == 'income' ? 'borrowed' : 'lent',
        walletId: entry.walletId,
      ),
    );
  }

  Future<void> deleted(String id, DateTime time) async {
    if (id.endsWith('_settlement')) {
      final debt = find(id.substring(0, id.length - '_settlement'.length));
      if (debt != null) {
        await _box!.put(debt.key ?? debt.id, debt.copyWith(clearSettledAt: true));
      }
      return;
    }
    final debt = find(id);
    if (debt != null) {
      await _box!.put(debt.key ?? debt.id, debt.copyWith(deletedAt: time));
    }
  }

  Future<void> restored(String id) async {
    if (id.endsWith('_settlement')) {
      final debt = find(id.substring(0, id.length - '_settlement'.length));
      if (debt != null) {
        await _box!.put(
          debt.key ?? debt.id,
          debt.copyWith(settledAt: DateTime.now()),
        );
      }
      return;
    }
    final debt = find(id);
    if (debt != null) {
      await _box!.put(debt.key ?? debt.id, debt.copyWith(clearDeletedAt: true));
    }
  }

  Future<void> permanentlyDeleted(String id) async {
    final debt = find(id);
    if (debt != null) await _box!.delete(debt.key ?? debt.id);
  }

  Future<void> reassignWallet(String fromId, String toId) async {
    final box = _box;
    if (box == null) return;
    for (final debt in box.values.where((entry) => entry.walletId == fromId)) {
      await box.put(debt.key ?? debt.id, debt.copyWith(walletId: toId));
    }
  }
}

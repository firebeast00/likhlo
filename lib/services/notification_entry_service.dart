import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/expense_model.dart';
import '../models/wallet_model.dart';
import '../providers/expense_provider.dart';
import 'confidence_evaluator.dart';
import 'local_nlp_service.dart';
import 'smart_command.dart';
import 'smart_input_engine.dart';
import 'transaction_executor.dart';
import 'transaction_title_policy.dart';

enum NotificationEntryDisposition { saved, review, duplicate, failed }

class NotificationEntryResult {
  final NotificationEntryDisposition disposition;
  final String message;

  const NotificationEntryResult(this.disposition, this.message);
}

/// Handles text entered directly in the Android notification without needing
/// the dashboard isolate. All writes still pass through [TransactionExecutor].
class NotificationEntryService {
  static const pendingReviewKey = 'pending_notification_entry_v1';
  static const _dedupeKey = 'notification_entry_dedupe_v1';

  Future<NotificationEntryResult> process({
    required String input,
    required int notificationId,
  }) async {
    final normalizedInput = input.trim();
    if (normalizedInput.isEmpty) {
      return const NotificationEntryResult(
        NotificationEntryDisposition.failed,
        'No entry text was provided.',
      );
    }

    try {
      await _openStorage();
      final preferences = Hive.box('preferences');
      if (await _isDuplicate(preferences, notificationId, normalizedInput)) {
        return const NotificationEntryResult(
          NotificationEntryDisposition.duplicate,
          'This notification entry was already handled.',
        );
      }

      final storedCategories = preferences.get('categories');
      final categories = storedCategories is Iterable
          ? storedCategories.whereType<String>().toList()
          : <String>[
              'General',
              'Food',
              'Transport',
              'Shopping',
              'Entertainment',
              'Health',
              'Education',
            ];
      final plan = SmartInputEngine().parse(
        normalizedInput,
        categories,
        source: SmartInputSource.notification,
      );
      if (plan.command is! AddSmartTransactionCommand) {
        await _queueReview(preferences, normalizedInput);
        return const NotificationEntryResult(
          NotificationEntryDisposition.review,
          'Open Likhlo to review this command.',
        );
      }

      final parsed = plan.parsed;
      final wallets = Hive.box<Wallet>('wallets').values.toList();
      final entries = Hive.box<Expense>('expenses')
          .values
          .where((entry) => entry.deletedAt == null)
          .toList();
      final accounts = wallets
          .map(
            (wallet) => SmartEntryAccount(
              id: wallet.id,
              name: wallet.name,
              type: wallet.walletType,
              availableBalance: wallet.balance +
                  entries
                      .where((entry) => entry.walletId == wallet.id)
                      .fold<double>(
                        0,
                        (sum, entry) =>
                            sum +
                            (entry.type == 'income'
                                ? entry.amount
                                : -entry.amount),
                      ),
              isBackup: wallet.isBackup,
            ),
          )
          .toList();
      final type = parsed.intent == SmartEntryIntent.addIncome
          ? 'income'
          : 'expense';
      final preferred = preferences.get('smart_entry_default_wallet_id');
      final walletId = resolveSmartEntryAccount(
        input: plan.normalizedText,
        accounts: accounts,
        transactionType: type,
        amount: parsed.amount,
        preferredAccountId: preferred is String ? preferred : null,
      );
      final confidence = const ConfidenceEvaluator().evaluate(
        plan.command,
        context: ConfidenceContext(
          hasResolvedWallet: walletId != null,
          hasExactAmount:
              (parsed.confidenceByField['amount'] ?? 0) >= 0.9,
        ),
      );
      if (!confidence.canAutoExecute ||
          !shouldAutoSaveSmartEntry(
            parsed.toLegacyMap(),
            hasResolvedWallet: walletId != null,
            semanticConfidence: confidence.score,
          )) {
        await _queueReview(preferences, normalizedInput);
        return const NotificationEntryResult(
          NotificationEntryDisposition.review,
          'Entry needs review before it can be saved.',
        );
      }

      final entry = Expense(
        id: const Uuid().v4(),
        title: coreTransactionTitle(parsed.title),
        amount: parsed.amount,
        date: parsed.date,
        category: type == 'income' ? 'Income / Allowance' : parsed.category,
        colorValue: 0xFF009688,
        type: type,
        walletId: walletId!,
      );
      final execution = await TransactionExecutor(
        _HeadlessTransactionStore(),
        enableAudio: false,
      ).execute(CreateTransactionCommand(entry));
      if (!execution.succeeded) {
        await _queueReview(preferences, normalizedInput);
        return NotificationEntryResult(
          NotificationEntryDisposition.failed,
          execution.reason ?? 'The entry could not be saved.',
        );
      }
      await preferences.delete(pendingReviewKey);
      return NotificationEntryResult(
        NotificationEntryDisposition.saved,
        '${entry.title} — Rs. ${entry.amount.toStringAsFixed(0)} saved.',
      );
    } catch (error, stackTrace) {
      debugPrint('Background notification entry failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return const NotificationEntryResult(
        NotificationEntryDisposition.failed,
        'The entry could not be saved. Open Likhlo to try again.',
      );
    }
  }

  Future<void> _openStorage() async {
    if (!Hive.isBoxOpen('preferences') &&
        !Hive.isBoxOpen('expenses') &&
        !Hive.isBoxOpen('wallets')) {
      await Hive.initFlutter();
    }
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ExpenseAdapter());
    if (!Hive.isAdapterRegistered(8)) Hive.registerAdapter(WalletAdapter());
    if (!Hive.isBoxOpen('preferences')) await Hive.openBox('preferences');
    if (!Hive.isBoxOpen('expenses')) {
      await Hive.openBox<Expense>('expenses');
    }
    if (!Hive.isBoxOpen('wallets')) await Hive.openBox<Wallet>('wallets');
  }

  Future<bool> _isDuplicate(Box preferences, int id, String input) async {
    final signature = '$id:${_stableHash(input.toLowerCase())}';
    final now = DateTime.now().millisecondsSinceEpoch;
    final stored = preferences.get(_dedupeKey);
    if (stored is Map &&
        stored['signature'] == signature &&
        stored['at'] is num &&
        now - (stored['at'] as num).toInt() < 15000) {
      return true;
    }
    await preferences.put(_dedupeKey, {'signature': signature, 'at': now});
    return false;
  }

  int _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  Future<void> _queueReview(Box preferences, String input) => preferences.put(
        pendingReviewKey,
        {'text': input, 'createdAt': DateTime.now().toIso8601String()},
      );
}

class _HeadlessTransactionStore implements TransactionStore {
  Box<Expense> get _box => Hive.box<Expense>('expenses');
  List<Expense> get _active =>
      _box.values.where((entry) => entry.deletedAt == null).toList();

  dynamic _keyFor(String id) {
    if (_box.containsKey(id) && _box.get(id)?.id == id) return id;
    for (final key in _box.keys) {
      if (_box.get(key)?.id == id) return key;
    }
    return null;
  }

  Map<String, double> get _openingBalances => {
        for (final wallet in Hive.box<Wallet>('wallets').values)
          wallet.id: wallet.balance,
      };

  @override
  Future<bool> add(Expense entry) => addAll([entry]);

  @override
  Future<bool> addAll(Iterable<Expense> entries) async {
    final additions = entries.toList();
    if (!isValidTransactionBatch(
          additions,
          existingIds: _box.values.map((entry) => entry.id).toSet(),
        ) ||
        !keepsWalletBalancesNonNegative(
          openingBalances: _openingBalances,
          existingEntries: _active,
          proposedEntries: additions,
        )) {
      return false;
    }
    await _box.putAll({for (final entry in additions) entry.id: entry});
    return true;
  }

  @override
  Future<bool> update(String id, Expense entry) async {
    final key = _keyFor(id);
    if (key == null ||
        !keepsWalletBalancesNonNegative(
          openingBalances: _openingBalances,
          existingEntries: _active,
          proposedEntries: [entry],
          replacedIds: {id},
        )) {
      return false;
    }
    await _box.put(key, entry);
    return true;
  }

  @override
  Future<bool> delete(String id) async {
    final entry = findById(id);
    final key = _keyFor(id);
    if (entry == null || key == null) return false;
    await _box.put(key, entry.copyWith(deletedAt: DateTime.now()));
    return true;
  }

  @override
  Future<bool> deleteTransfer(String transactionId) async {
    final base = _transferBase(transactionId);
    final records = _active
        .where((entry) =>
            entry.id == '${base}_out' || entry.id == '${base}_in')
        .toList();
    if (records.length != 2) return false;
    final deletedAt = DateTime.now();
    await _box.putAll({
      for (final entry in records)
        entry.id: entry.copyWith(deletedAt: deletedAt),
    });
    return true;
  }

  @override
  Expense? findById(String id) {
    for (final entry in _active) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  @override
  Expense? findDeletedById(String id) {
    for (final entry in _box.values) {
      if (entry.id == id && entry.deletedAt != null) return entry;
    }
    return null;
  }

  @override
  Future<bool> restore(String id) async {
    final entry = findDeletedById(id);
    final key = _keyFor(id);
    if (entry == null || key == null) return false;
    final restored = entry.copyWith(clearDeletedAt: true);
    if (!keepsWalletBalancesNonNegative(
      openingBalances: _openingBalances,
      existingEntries: _active,
      proposedEntries: [restored],
    )) {
      return false;
    }
    await _box.put(key, restored);
    return true;
  }

  @override
  Future<bool> restoreTransfer(String transactionId) async {
    final base = _transferBase(transactionId);
    final records = _box.values
        .where((entry) =>
            entry.deletedAt != null &&
            (entry.id == '${base}_out' || entry.id == '${base}_in'))
        .map((entry) => entry.copyWith(clearDeletedAt: true))
        .toList();
    if (records.length != 2 ||
        !keepsWalletBalancesNonNegative(
          openingBalances: _openingBalances,
          existingEntries: _active,
          proposedEntries: records,
        )) {
      return false;
    }
    await _box.putAll({for (final entry in records) entry.id: entry});
    return true;
  }

  @override
  Future<bool> permanentlyDelete(String id) async {
    final entry = findDeletedById(id);
    if (entry == null) return false;
    final ids = entry.category == 'Transfer'
        ? {'${_transferBase(id)}_out', '${_transferBase(id)}_in'}
        : {id};
    for (final key in _box.keys.toList()) {
      if (ids.contains(_box.get(key)?.id)) await _box.delete(key);
    }
    return true;
  }

  @override
  Future<void> emptyTrash() async {
    for (final key in _box.keys.toList()) {
      if (_box.get(key)?.deletedAt != null) await _box.delete(key);
    }
  }

  String _transferBase(String id) => id.endsWith('_out')
      ? id.substring(0, id.length - 4)
      : id.endsWith('_in')
          ? id.substring(0, id.length - 3)
          : id;
}

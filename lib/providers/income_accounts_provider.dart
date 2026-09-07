import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'budget_provider.dart';

class IncomeAccount {
  const IncomeAccount({
    required this.id,
    required this.name,
    required this.balance,
  });

  final String id;
  final String name;
  final double balance;

  IncomeAccount copyWith({String? name, double? balance}) => IncomeAccount(
        id: id,
        name: name ?? this.name,
        balance: balance ?? this.balance,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'balance': balance,
      };

  factory IncomeAccount.fromMap(Map<dynamic, dynamic> map) => IncomeAccount(
        id: map['id']?.toString() ?? '',
        name: map['name']?.toString() ?? 'Income source',
        balance: (map['balance'] as num?)?.toDouble() ?? 0,
      );
}

class IncomeEntry {
  const IncomeEntry({
    required this.id,
    required this.type,
    required this.amount,
    required this.date,
    required this.fromAccountId,
    this.toAccountId,
    this.note = '',
  });

  final String id;
  final String type;
  final double amount;
  final DateTime date;
  final String fromAccountId;
  final String? toAccountId;
  final String note;

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'amount': amount,
        'date': date.toIso8601String(),
        'fromAccountId': fromAccountId,
        'toAccountId': toAccountId,
        'note': note,
      };

  factory IncomeEntry.fromMap(Map<dynamic, dynamic> map) => IncomeEntry(
        id: map['id']?.toString() ?? '',
        type: map['type']?.toString() ?? 'income',
        amount: (map['amount'] as num?)?.toDouble() ?? 0,
        date: DateTime.tryParse(map['date']?.toString() ?? '') ?? DateTime.now(),
        fromAccountId: map['fromAccountId']?.toString() ?? '',
        toAccountId: map['toAccountId']?.toString(),
        note: map['note']?.toString() ?? '',
      );
}

class IncomeAccountsState {
  const IncomeAccountsState({
    this.accounts = const [],
    this.entries = const [],
  });

  final List<IncomeAccount> accounts;
  final List<IncomeEntry> entries;

  IncomeAccountsState copyWith({
    List<IncomeAccount>? accounts,
    List<IncomeEntry>? entries,
  }) =>
      IncomeAccountsState(
        accounts: accounts ?? this.accounts,
        entries: entries ?? this.entries,
      );
}

class IncomeAccountsNotifier extends StateNotifier<IncomeAccountsState> {
  IncomeAccountsNotifier(this.ref) : super(const IncomeAccountsState()) {
    _load();
  }

  static const _accountsKey = 'income_accounts_v1';
  static const _entriesKey = 'income_entries_v1';
  final Ref ref;

  Box get _box => Hive.box('preferences');

  void _load() {
    final rawAccounts = (_box.get(_accountsKey, defaultValue: const []) as List)
        .whereType<Map>()
        .map(IncomeAccount.fromMap)
        .where((account) => account.id.isNotEmpty)
        .toList();

    final rawEntries = (_box.get(_entriesKey, defaultValue: const []) as List)
        .whereType<Map>()
        .map(IncomeEntry.fromMap)
        .where((entry) => entry.id.isNotEmpty)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    state = IncomeAccountsState(accounts: rawAccounts, entries: rawEntries);
  }

  Future<void> _persist(IncomeAccountsState next) async {
    await Future.wait([
      _box.put(_accountsKey, next.accounts.map((e) => e.toMap()).toList()),
      _box.put(_entriesKey, next.entries.map((e) => e.toMap()).toList()),
    ]);
    state = next;
  }

  Future<void> addAccount(String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw ArgumentError('Account name is required.');
    }
    if (state.accounts.any(
        (account) => account.name.toLowerCase() == cleanName.toLowerCase())) {
      throw ArgumentError('An account with this name already exists.');
    }

    final account = IncomeAccount(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: cleanName,
      balance: 0,
    );
    await _persist(state.copyWith(accounts: [...state.accounts, account]));
  }

  Future<void> updateAccount(String id, String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw ArgumentError('Account name is required.');
    }
    if (state.accounts.any((account) =>
        account.id != id &&
        account.name.toLowerCase() == cleanName.toLowerCase())) {
      throw ArgumentError('An account with this name already exists.');
    }

    var found = false;
    final accounts = state.accounts.map((account) {
      if (account.id != id) return account;
      found = true;
      return account.copyWith(name: cleanName);
    }).toList();
    if (!found) throw StateError('Income account was not found.');
    await _persist(state.copyWith(accounts: accounts));
  }

  Future<void> addIncome({
    required String accountId,
    required double amount,
    required DateTime date,
    String note = '',
  }) async {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError('Income must be greater than zero.');
    }

    var found = false;
    final accounts = state.accounts.map((account) {
      if (account.id != accountId) return account;
      found = true;
      return account.copyWith(balance: account.balance + amount);
    }).toList();
    if (!found) throw StateError('Income account was not found.');

    final entry = IncomeEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: 'income',
      amount: amount,
      date: date,
      fromAccountId: accountId,
      note: note.trim(),
    );

    await ref.read(budgetProvider.notifier).adjustBudget(amount, date);
    await _persist(state.copyWith(
      accounts: accounts,
      entries: [entry, ...state.entries],
    ));
  }

  Future<void> transfer({
    required String fromAccountId,
    required String toAccountId,
    required double amount,
    String note = '',
  }) async {
    if (fromAccountId == toAccountId) {
      throw ArgumentError('Choose two different accounts.');
    }
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError('Transfer amount must be greater than zero.');
    }

    final source = state.accounts
        .where((account) => account.id == fromAccountId)
        .firstOrNull;
    if (source == null) throw StateError('Source account was not found.');
    if (!state.accounts.any((account) => account.id == toAccountId)) {
      throw StateError('Destination account was not found.');
    }
    if (source.balance < amount) {
      throw ArgumentError('The source account has insufficient balance.');
    }

    final accounts = state.accounts.map((account) {
      if (account.id == fromAccountId) {
        return account.copyWith(balance: account.balance - amount);
      }
      if (account.id == toAccountId) {
        return account.copyWith(balance: account.balance + amount);
      }
      return account;
    }).toList();

    final entry = IncomeEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: 'transfer',
      amount: amount,
      date: DateTime.now(),
      fromAccountId: fromAccountId,
      toAccountId: toAccountId,
      note: note.trim(),
    );

    // A transfer only changes where money is held. It must not inflate the
    // user's total monthly budget.
    await _persist(state.copyWith(
      accounts: accounts,
      entries: [entry, ...state.entries],
    ));
  }

  Future<void> clearAccount(String id, DateTime budgetMonth) async {
    final account = state.accounts.where((item) => item.id == id).firstOrNull;
    if (account == null) throw StateError('Income account was not found.');

    if (account.balance != 0) {
      await ref
          .read(budgetProvider.notifier)
          .adjustBudget(-account.balance, budgetMonth);
    }

    final accounts = state.accounts
        .map((item) => item.id == id ? item.copyWith(balance: 0) : item)
        .toList();
    await _persist(state.copyWith(accounts: accounts));
  }

  Future<void> deleteAccount(String id, DateTime budgetMonth) async {
    final account = state.accounts.where((item) => item.id == id).firstOrNull;
    if (account == null) return;

    if (account.balance != 0) {
      await ref
          .read(budgetProvider.notifier)
          .adjustBudget(-account.balance, budgetMonth);
    }

    await _persist(state.copyWith(
      accounts: state.accounts.where((item) => item.id != id).toList(),
    ));
  }
}

final incomeAccountsProvider =
    StateNotifierProvider<IncomeAccountsNotifier, IncomeAccountsState>(
  (ref) => IncomeAccountsNotifier(ref),
);

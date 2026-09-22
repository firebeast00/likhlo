import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/debt_model.dart';
import '../models/expense_model.dart';
import '../models/mess_entry_model.dart';
import '../models/wallet_model.dart';
import '../models/workspace_model.dart';
import 'backup_codec.dart';
import 'biometric_service.dart';

class BackupPreview {
  final DateTime createdAt;
  final int expenses;
  final int wallets;
  final int debts;
  final int messEntries;
  final int categories;

  const BackupPreview({
    required this.createdAt,
    required this.expenses,
    required this.wallets,
    required this.debts,
    required this.messEntries,
    required this.categories,
  });
}

class ValidatedBackup {
  final Map<String, dynamic> payload;
  final BackupPreview preview;
  final List<Expense> expenses;
  final List<Wallet> wallets;
  final List<DebtEntry> debts;
  final List<MessEntry> messEntries;
  final List<Workspace> workspaces;
  final Map<dynamic, dynamic> settings;
  final Map<dynamic, dynamic> preferences;

  const ValidatedBackup({
    required this.payload,
    required this.preview,
    required this.expenses,
    required this.wallets,
    required this.debts,
    required this.messEntries,
    required this.workspaces,
    required this.settings,
    required this.preferences,
  });
}

class BackupService {
  static const int schemaVersion = 2;
  static const int maxBackupBytes = 25 * 1024 * 1024;
  static const String _recoveryBoxName = 'restore_recovery';
  static const String _recoveryKey = 'latest_snapshot';

  Future<Map<String, dynamic>> createPayload() async {
    final boxes = await _openBoxes();
    return <String, dynamic>{
      'schemaVersion': schemaVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'app': 'Likhlo',
      'data': <String, dynamic>{
        'expenses': boxes.expenses.values.map(_expenseToJson).toList(),
        'wallets': boxes.wallets.values.map(_walletToJson).toList(),
        'debts': boxes.debts.values.map(_debtToJson).toList(),
        'messEntries': boxes.mess.values.map(_messToJson).toList(),
        'workspaces': boxes.workspaces.values.map(_workspaceToJson).toList(),
        'settings': _entriesToJson(boxes.settings),
        'preferences': _entriesToJson(boxes.preferences),
      },
    };
  }

  ValidatedBackup validate(Map<String, dynamic> payload) {
    final incomingVersion = payload['schemaVersion'];
    if ((incomingVersion != 1 && incomingVersion != schemaVersion) ||
        payload['app'] != 'Likhlo') {
      throw const BackupException(
        'This backup version is not supported by this Likhlo release.',
      );
    }
    final createdAt = DateTime.tryParse(_requiredString(payload['createdAt']));
    final data = _requiredMap(payload['data']);
    if (createdAt == null) {
      throw const BackupException('The backup creation date is invalid.');
    }

    final expenses = _requiredList(data['expenses'])
        .map((item) => _expenseFromJson(_requiredMap(item)))
        .toList(growable: false);
    final wallets = _requiredList(data['wallets'])
        .map((item) => _walletFromJson(_requiredMap(item)))
        .toList(growable: false);
    final debts = _requiredList(data['debts'])
        .map((item) => _debtFromJson(_requiredMap(item)))
        .toList(growable: false);
    final messEntries = _requiredList(data['messEntries'])
        .map((item) => _messFromJson(_requiredMap(item)))
        .toList(growable: false);
    final workspaces = data['workspaces'] is List
        ? _requiredList(data['workspaces'])
            .map((item) => _workspaceFromJson(_requiredMap(item)))
            .toList(growable: false)
        : <Workspace>[
            Workspace(
              id: 'personal',
              name: 'Personal',
              colorValue: 0xFF2563EB,
              iconCodePoint: 0xe491,
              position: 0,
              isDefault: true,
            ),
          ];
    final settings = _entriesFromJson(_requiredList(data['settings']));
    final preferences = _entriesFromJson(_requiredList(data['preferences']));

    _requireUnique(expenses.map((e) => e.id), 'transaction');
    _requireUnique(wallets.map((e) => e.id), 'wallet');
    _requireUnique(debts.map((e) => e.id), 'Udhar');
    _requireUnique(messEntries.map((e) => e.id), 'Mess Khata');
    _requireUnique(workspaces.map((e) => e.id), 'workspace');
    if (wallets.isEmpty) {
      throw const BackupException('A backup must contain a wallet.');
    }
    final walletIds = wallets.map((wallet) => wallet.id).toSet();
    final workspaceIds = workspaces.map((workspace) => workspace.id).toSet();
    if (expenses.any((entry) => !walletIds.contains(entry.walletId))) {
      throw const BackupException(
        'A transaction refers to a missing wallet.',
      );
    }
    if (!workspaceIds.contains('personal') ||
        expenses.any((entry) => !workspaceIds.contains(entry.workspaceId))) {
      throw const BackupException(
        'A transaction refers to a missing workspace.',
      );
    }
    final categories = preferences['categories'];
    final categoryCount = categories is Iterable
        ? categories.whereType<String>().toSet().length
        : 0;

    return ValidatedBackup(
      payload: payload,
      preview: BackupPreview(
        createdAt: createdAt.toLocal(),
        expenses: expenses.length,
        wallets: wallets.length,
        debts: debts.length,
        messEntries: messEntries.length,
        categories: categoryCount,
      ),
      expenses: expenses,
      wallets: wallets,
      debts: debts,
      messEntries: messEntries,
      workspaces: workspaces,
      settings: settings,
      preferences: preferences,
    );
  }

  Future<void> restore(ValidatedBackup backup) async {
    final currentPayload = await createPayload();
    final recovery = await Hive.openBox(_recoveryBoxName);
    await recovery.put(_recoveryKey, jsonEncode(currentPayload));
    try {
      await _writeValidated(backup);
    } catch (_) {
      try {
        await _writeValidated(validate(currentPayload));
      } catch (_) {
        // Preserve the original restore error. The recovery snapshot remains.
      }
      rethrow;
    }
  }

  Future<bool> hasRecoverySnapshot() async {
    final recovery = await Hive.openBox(_recoveryBoxName);
    return recovery.get(_recoveryKey) is String;
  }

  Future<ValidatedBackup?> readRecoverySnapshot() async {
    final recovery = await Hive.openBox(_recoveryBoxName);
    final raw = recovery.get(_recoveryKey);
    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      return validate(_requiredMap(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> restoreRecoverySnapshot(ValidatedBackup backup) async {
    // Use the same guarded path so the currently restored data becomes the
    // next recovery snapshot and any write failure is rolled back.
    await restore(backup);
  }

  Future<void> _writeValidated(ValidatedBackup backup) async {
    final boxes = await _openBoxes();
    // App Lock belongs to this physical device. Never import another phone's
    // lock preference, because its enrolled biometrics are not transferable.
    final localAppLockEnabled = boxes.preferences.get(
          BiometricService.preferenceKey,
          defaultValue: false,
        ) ==
        true;
    await boxes.expenses.clear();
    await boxes.expenses.putAll({for (final e in backup.expenses) e.id: e});
    await boxes.wallets.clear();
    await boxes.wallets.putAll({for (final e in backup.wallets) e.id: e});
    await boxes.debts.clear();
    await boxes.debts.putAll({for (final e in backup.debts) e.id: e});
    await boxes.mess.clear();
    await boxes.mess.putAll({for (final e in backup.messEntries) e.id: e});
    await boxes.workspaces.clear();
    await boxes.workspaces.putAll({
      for (final workspace in backup.workspaces) workspace.id: workspace,
    });
    await boxes.settings.clear();
    await boxes.settings.putAll(backup.settings);
    await boxes.preferences.clear();
    await boxes.preferences.putAll(backup.preferences);
    await boxes.preferences.put(
      BiometricService.preferenceKey,
      localAppLockEnabled,
    );
  }

  Future<_BackupBoxes> _openBoxes() async {
    final debts = Hive.isBoxOpen('debts')
        ? Hive.box<DebtEntry>('debts')
        : await Hive.openBox<DebtEntry>('debts');
    final mess = Hive.isBoxOpen('mess_khata')
        ? Hive.box<MessEntry>('mess_khata')
        : await Hive.openBox<MessEntry>('mess_khata');
    final workspaces = Hive.isBoxOpen('workspaces')
        ? Hive.box<Workspace>('workspaces')
        : await Hive.openBox<Workspace>('workspaces');
    return _BackupBoxes(
      expenses: Hive.box<Expense>('expenses'),
      wallets: Hive.box<Wallet>('wallets'),
      debts: debts,
      mess: mess,
      workspaces: workspaces,
      settings: Hive.box('settings'),
      preferences: Hive.box('preferences'),
    );
  }

  static List<Map<String, dynamic>> _entriesToJson(Box box) => box.keys
      .map((key) => <String, dynamic>{
            'key': _jsonSafe(key),
            'value': _jsonSafe(box.get(key)),
          })
      .toList(growable: false);

  static Map<dynamic, dynamic> _entriesFromJson(List<dynamic> entries) {
    final result = <dynamic, dynamic>{};
    for (final raw in entries) {
      final entry = _requiredMap(raw);
      final key = _fromJsonSafe(entry['key']);
      if (key is! String && key is! int) {
        throw const BackupException('A settings key is invalid.');
      }
      if (result.containsKey(key)) {
        throw const BackupException('The backup contains duplicate settings.');
      }
      result[key] = _fromJsonSafe(entry['value']);
    }
    return result;
  }

  static dynamic _jsonSafe(dynamic value) {
    if (value == null || value is String || value is bool || value is num) {
      return value;
    }
    if (value is DateTime) {
      return <String, dynamic>{
        r'$type': 'dateTime',
        'value': value.toUtc().toIso8601String(),
      };
    }
    if (value is Iterable) return value.map(_jsonSafe).toList();
    if (value is Map) {
      return <String, dynamic>{
        r'$type': 'map',
        'entries': value.entries
            .map((entry) => <String, dynamic>{
                  'key': _jsonSafe(entry.key),
                  'value': _jsonSafe(entry.value),
                })
            .toList(),
      };
    }
    throw BackupException(
      'A stored setting (${value.runtimeType}) cannot be backed up safely.',
    );
  }

  static dynamic _fromJsonSafe(dynamic value) {
    if (value is Map<String, dynamic> && value[r'$type'] == 'dateTime') {
      final parsed = DateTime.tryParse(_requiredString(value['value']));
      if (parsed == null) throw const BackupException('Invalid stored date.');
      return parsed;
    }
    if (value is Map<String, dynamic> && value[r'$type'] == 'map') {
      final entries = _requiredList(value['entries']);
      return <dynamic, dynamic>{
        for (final raw in entries)
          _fromJsonSafe(_requiredMap(raw)['key']):
              _fromJsonSafe(_requiredMap(raw)['value']),
      };
    }
    if (value is List) return value.map(_fromJsonSafe).toList();
    return value;
  }

  static Map<String, dynamic> _expenseToJson(Expense e) => {
        'id': e.id,
        'title': e.title,
        'amount': e.amount,
        'date': e.date.toUtc().toIso8601String(),
        'category': e.category,
        'colorValue': e.colorValue,
        'type': e.type,
        'walletId': e.walletId,
        'workspaceId': e.workspaceId,
        'deletedAt': e.deletedAt?.toUtc().toIso8601String(),
      };

  static Expense _expenseFromJson(Map<String, dynamic> value) {
    final amount = _positiveDouble(value['amount'], 'transaction amount');
    final date = DateTime.tryParse(_requiredString(value['date']));
    final type = _requiredString(value['type']);
    final deletedAtValue = value['deletedAt'];
    final deletedAt = deletedAtValue == null
        ? null
        : DateTime.tryParse(_requiredString(deletedAtValue))?.toLocal();
    if (date == null ||
        (type != 'expense' && type != 'income') ||
        (deletedAtValue != null && deletedAt == null)) {
      throw const BackupException('A transaction is invalid.');
    }
    return Expense(
      id: _requiredString(value['id']),
      title: _requiredString(value['title']),
      amount: amount,
      date: date.toLocal(),
      category: _requiredString(value['category']),
      colorValue: _requiredInt(value['colorValue']),
      type: type,
      walletId: _requiredString(value['walletId']),
      workspaceId: value['workspaceId'] is String &&
              (value['workspaceId'] as String).trim().isNotEmpty
          ? value['workspaceId'] as String
          : 'personal',
      deletedAt: deletedAt,
    );
  }

  static Map<String, dynamic> _workspaceToJson(Workspace workspace) => {
        'id': workspace.id,
        'name': workspace.name,
        'colorValue': workspace.colorValue,
        'iconCodePoint': workspace.iconCodePoint,
        'position': workspace.position,
        'isDefault': workspace.isDefault,
      };

  static Workspace _workspaceFromJson(Map<String, dynamic> value) {
    return Workspace(
      id: _requiredString(value['id']),
      name: _requiredString(value['name']),
      colorValue: _requiredInt(value['colorValue']),
      iconCodePoint: _requiredInt(value['iconCodePoint']),
      position: _requiredInt(value['position']),
      isDefault: value['isDefault'] == true,
    );
  }

  static Map<String, dynamic> _walletToJson(Wallet w) => {
        'id': w.id,
        'name': w.name,
        'balance': w.balance,
        'isBackup': w.isBackup,
        'colorValue': w.colorValue,
        'walletType': w.walletType,
      };

  static Wallet _walletFromJson(Map<String, dynamic> value) {
    final balance = _finiteDouble(value['balance'], 'wallet balance');
    return Wallet(
      id: _requiredString(value['id']),
      name: _requiredString(value['name']),
      balance: balance,
      isBackup: value['isBackup'] is bool ? value['isBackup'] as bool : false,
      colorValue: _requiredInt(value['colorValue']),
      walletType: _requiredString(value['walletType']),
    );
  }

  static Map<String, dynamic> _debtToJson(DebtEntry d) => {
        'id': d.id,
        'borrowerName': d.borrowerName,
        'amount': d.amount,
        'type': d.type,
        'dueDate': d.dueDate?.toUtc().toIso8601String(),
        'deletedAt': d.deletedAt?.toUtc().toIso8601String(),
      };

  static DebtEntry _debtFromJson(Map<String, dynamic> value) {
    final type = _requiredString(value['type']);
    final dueDateValue = value['dueDate'];
    final dueDate = dueDateValue == null
        ? null
        : DateTime.tryParse(_requiredString(dueDateValue))?.toLocal();
    final deletedAtValue = value['deletedAt'];
    final deletedAt = deletedAtValue == null
        ? null
        : DateTime.tryParse(_requiredString(deletedAtValue))?.toLocal();
    if ((type != 'lent' && type != 'borrowed') ||
        (dueDateValue != null && dueDate == null) ||
        (deletedAtValue != null && deletedAt == null)) {
      throw const BackupException('An Udhar record is invalid.');
    }
    return DebtEntry(
      id: _requiredString(value['id']),
      borrowerName: _requiredString(value['borrowerName']),
      amount: _positiveDouble(value['amount'], 'Udhar amount'),
      type: type,
      dueDate: dueDate,
      deletedAt: deletedAt,
    );
  }

  static Map<String, dynamic> _messToJson(MessEntry m) => {
        'id': m.id,
        'title': m.title,
        'totalAmount': m.totalAmount,
        'paidBy': m.paidBy,
        'splitCount': m.splitCount,
        'date': m.date.toUtc().toIso8601String(),
        'deletedAt': m.deletedAt?.toUtc().toIso8601String(),
      };

  static MessEntry _messFromJson(Map<String, dynamic> value) {
    final date = DateTime.tryParse(_requiredString(value['date']));
    final splitCount = _requiredInt(value['splitCount']);
    final deletedAtValue = value['deletedAt'];
    final deletedAt = deletedAtValue == null
        ? null
        : DateTime.tryParse(_requiredString(deletedAtValue))?.toLocal();
    if (date == null ||
        splitCount <= 0 ||
        (deletedAtValue != null && deletedAt == null)) {
      throw const BackupException('A Mess Khata record is invalid.');
    }
    return MessEntry(
      id: _requiredString(value['id']),
      title: _requiredString(value['title']),
      totalAmount: _positiveDouble(value['totalAmount'], 'Mess amount'),
      paidBy: _requiredString(value['paidBy']),
      splitCount: splitCount,
      date: date.toLocal(),
      deletedAt: deletedAt,
    );
  }

  static Map<String, dynamic> _requiredMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    throw const BackupException('The backup structure is invalid.');
  }

  static List<dynamic> _requiredList(dynamic value) {
    if (value is List<dynamic>) return value;
    throw const BackupException('The backup structure is invalid.');
  }

  static String _requiredString(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value;
    throw const BackupException('The backup contains missing text.');
  }

  static int _requiredInt(dynamic value) {
    if (value is int) return value;
    throw const BackupException('The backup contains an invalid number.');
  }

  static double _finiteDouble(dynamic value, String label) {
    if (value is num && value.toDouble().isFinite) return value.toDouble();
    throw BackupException('The $label is invalid.');
  }

  static double _positiveDouble(dynamic value, String label) {
    final number = _finiteDouble(value, label);
    if (number > 0) return number;
    throw BackupException('The $label must be greater than zero.');
  }

  static void _requireUnique(Iterable<String> ids, String label) {
    final all = ids.toList(growable: false);
    if (all.any((id) => id.trim().isEmpty) ||
        all.toSet().length != all.length) {
      throw BackupException('The backup contains duplicate $label IDs.');
    }
  }
}

class _BackupBoxes {
  final Box<Expense> expenses;
  final Box<Wallet> wallets;
  final Box<DebtEntry> debts;
  final Box<MessEntry> mess;
  final Box<Workspace> workspaces;
  final Box settings;
  final Box preferences;

  const _BackupBoxes({
    required this.expenses,
    required this.wallets,
    required this.debts,
    required this.mess,
    required this.workspaces,
    required this.settings,
    required this.preferences,
  });
}

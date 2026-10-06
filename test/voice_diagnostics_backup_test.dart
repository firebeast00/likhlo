import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:student_expense_manager/models/debt_model.dart';
import 'package:student_expense_manager/models/expense_model.dart';
import 'package:student_expense_manager/models/mess_entry_model.dart';
import 'package:student_expense_manager/models/wallet_model.dart';
import 'package:student_expense_manager/models/workspace_model.dart';
import 'package:student_expense_manager/services/backup_service.dart';
import 'package:student_expense_manager/services/voice_diagnostic_observer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('diagnostics_backup_');
    Hive.init(directory.path);
    for (final adapter in <TypeAdapter>[
      ExpenseAdapter(), WalletAdapter(), DebtEntryAdapter(), MessEntryAdapter(), WorkspaceAdapter(),
    ]) {
      if (!Hive.isAdapterRegistered(adapter.typeId)) Hive.registerAdapter(adapter);
    }
    await Hive.openBox<Expense>('expenses');
    await Hive.openBox<Wallet>('wallets');
    await Hive.openBox('settings');
    await Hive.openBox('preferences');
  });
  tearDown(() async { await Hive.close(); await directory.delete(recursive: true); });

  test('ledger backups exclude transcript consent and preserve unrelated preferences', () async {
    final preferences = Hive.box('preferences');
    await preferences.put(VoiceDiagnosticObserver.enabledKey, true);
    await preferences.put(VoiceDiagnosticObserver.historyKey, true);
    await preferences.put('other_setting', 'kept');
    final payload = await BackupService().createPayload();
    final entries = payload['data']['preferences'] as List;
    expect(entries.any((dynamic e) => e['key'] == VoiceDiagnosticObserver.enabledKey), false);
    expect(entries.any((dynamic e) => e['key'] == VoiceDiagnosticObserver.historyKey), false);
    expect(entries.any((dynamic e) => e['key'] == 'other_setting' && e['value'] == 'kept'), true);
  });
  test('restoring another device backup cannot enable transcript recording', () async {
    final service = BackupService();
    final payload = await service.createPayload();
    (payload['data']['preferences'] as List).add({'key': VoiceDiagnosticObserver.enabledKey, 'value': true});
    await service.restore(service.validate(payload));
    expect(Hive.box('preferences').get(VoiceDiagnosticObserver.enabledKey), false);
    await Hive.box('preferences').put(VoiceDiagnosticObserver.enabledKey, true);
    final second = await service.createPayload();
    await service.restore(service.validate(second));
    expect(Hive.box('preferences').get(VoiceDiagnosticObserver.enabledKey), true);
  });
}

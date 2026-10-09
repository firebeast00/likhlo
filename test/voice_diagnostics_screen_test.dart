import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:student_expense_manager/models/debt_model.dart';
import 'package:student_expense_manager/models/wallet_model.dart';
import 'package:student_expense_manager/screens/voice_diagnostics_screen.dart';
import 'package:student_expense_manager/services/voice_diagnostics_service.dart';

import 'voice_diagnostics_service_test.dart' show MemoryDiagnosticStorage;

class ExportTestService extends VoiceDiagnosticsService {
  ExportTestService()
      : super(MemoryDiagnosticStorage(), enabled: true, useIsolates: false);
  bool failExport = false;
  Completer<void>? holdFlush;

  @override
  Future<void> flush() async {
    if (holdFlush != null) await holdFlush!.future;
    await super.flush();
  }

  @override
  Map<String, dynamic> export({
    required Iterable<String> ids,
    bool maskNames = true,
    bool deferMasking = false,
    Iterable<String> additionalNames = const [],
  }) {
    if (failExport) throw StateError('export unavailable');
    return super.export(
        ids: ids,
        maskNames: maskNames,
        deferMasking: deferMasking,
        additionalNames: additionalNames);
  }
}

void main() {
  testWidgets(
      'tester reviews a completed command as misunderstood without changing action',
      (tester) async {
    final service = VoiceDiagnosticsService(MemoryDiagnosticStorage(),
        enabled: true, useIsolates: false);
    await service.initialize();
    final id = service.begin(entryPoint: 'test')!;
    service.event(id, 'recognition', {'text': '500 chai'});
    service.finish(id, 'completed');
    await service.flush();
    await tester.pumpWidget(
        MaterialApp(home: VoiceDiagnosticsScreen(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('500 chai'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Misunderstood / wrong'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(0), 'sau chai');
    await tester.enterText(
        find.byType(TextField).at(1), '100 expense for chai');
    await tester.ensureVisible(find.text('Save review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save review'));
    await service.flush();
    await tester.pumpAndSettle();
    expect(service.record(id)!['review']['assessment'], 'wrong');
    expect(service.record(id)!['outcome'], 'completed');
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  }, timeout: const Timeout(Duration(seconds: 45)));
  testWidgets('deselecting the last selected command disables export',
      (tester) async {
    final service = VoiceDiagnosticsService(MemoryDiagnosticStorage(),
        enabled: true, useIsolates: false);
    await service.initialize();
    final id = service.begin(entryPoint: 'test')!;
    service.finish(id, 'completed');
    await service.flush();
    await tester.pumpWidget(
        MaterialApp(home: VoiceDiagnosticsScreen(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.text('Export selected commands'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Export selected commands'))
            .onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  }, timeout: const Timeout(Duration(seconds: 45)));
  for (final boxes in [
    <String>[],
    ['wallets'],
    ['debts'],
    ['wallets', 'debts'],
  ]) {
    testWidgets('export works with typed financial boxes: $boxes',
        (tester) async {
      late Directory directory;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp('diagnostic-boxes-');
        Hive.init(directory.path);
        if (!Hive.isAdapterRegistered(8)) Hive.registerAdapter(WalletAdapter());
        if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(DebtEntryAdapter());
        if (boxes.contains('wallets')) {
          final wallets = await Hive.openBox<Wallet>('wallets');
          await wallets.put('wallet', Wallet(
              id: 'wallet', name: 'Personal Wallet', balance: 1200,
              colorValue: 0xFF009688));
        }
        if (boxes.contains('debts')) {
          final debts = await Hive.openBox<DebtEntry>('debts');
          await debts.put('debt', DebtEntry(
              id: 'debt', borrowerName: 'Hamza', amount: 500, type: 'lent'));
        }
      });
      final service = ExportTestService();
      try {
        await service.initialize();
        final id = service.begin(entryPoint: 'test')!;
        service.event(id, 'recognition',
            {'text': 'Hamza ko Personal Wallet se 500 diya'});
        service.finish(id, 'completed');
        await service.flush();
        await tester.pumpWidget(
            MaterialApp(home: VoiceDiagnosticsScreen(service: service)));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Export filtered commands'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Review JSON export'), findsOneWidget);
        final report = jsonDecode(tester.widget<SelectableText>(
            find.byType(SelectableText)).data!);
        final text = report['commands'][0]['raw_transcript'] as String;
        expect(text.contains('Personal Wallet'), !boxes.contains('wallets'));
        expect(text.contains('Hamza'), !boxes.contains('debts'));
        expect(service.record(id)!['raw_transcript'],
            'Hamza ko Personal Wallet se 500 diya');
        if (boxes.contains('wallets')) {
          expect(Hive.box<Wallet>('wallets').get('wallet')!.balance, 1200);
        }
        if (boxes.contains('debts')) {
          expect(Hive.box<DebtEntry>('debts').get('debt')!.amount, 500);
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        await service.flush();
        service.dispose();
        await tester.runAsync(() async {
          await Hive.close();
          await directory.delete(recursive: true);
        });
      }
    });
  }
  testWidgets('failed regeneration clears stale JSON and can be retried',
      (tester) async {
    final service = ExportTestService();
    await service.initialize();
    final id = service.begin(entryPoint: 'test')!;
    service.finish(id, 'completed');
    await service.flush();
    await tester.pumpWidget(
        MaterialApp(home: VoiceDiagnosticsScreen(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export filtered commands'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    service.failExport = true;
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(SelectableText), findsNothing);
    expect(tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Save JSON')).onPressed, isNull);
    expect(tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Share JSON')).onPressed, isNull);
    service.failExport = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Share JSON')).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
    await service.flush();
    service.dispose();
  });
  testWidgets('repeated export callbacks open only one preview', (tester) async {
    final service = ExportTestService();
    await service.initialize();
    final id = service.begin(entryPoint: 'test')!;
    service.finish(id, 'completed');
    await service.flush();
    await tester.pumpWidget(
        MaterialApp(home: VoiceDiagnosticsScreen(service: service)));
    await tester.pumpAndSettle();
    final callback = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Export filtered commands')).onPressed!;
    final hold = service.holdFlush = Completer<void>();
    callback();
    callback();
    await tester.pump();
    expect(tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Export filtered commands')).onPressed,
        isNull);
    hold.complete();
    service.holdFlush = null;
    await tester.pumpAndSettle();
    expect(find.text('Review JSON export'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Voice diagnostics'), findsOneWidget);
    expect(find.text('Review JSON export'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await service.flush();
    service.dispose();
  });
}


import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/screens/voice_diagnostics_screen.dart';
import 'package:student_expense_manager/services/voice_diagnostics_service.dart';

import 'voice_diagnostics_service_test.dart' show MemoryDiagnosticStorage;

void main() {
  testWidgets('tester reviews a completed command as misunderstood without changing action', (tester) async {
    final service = VoiceDiagnosticsService(MemoryDiagnosticStorage(), enabled: true, useIsolates: false);
    await tester.runAsync(() => service.initialize());
    final id = service.begin(entryPoint: 'test')!;
    service.event(id, 'recognition', {'text': '500 chai'}); service.finish(id, 'completed');
    await tester.runAsync(() => service.flush());
    await tester.pumpWidget(MaterialApp(home: VoiceDiagnosticsScreen(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('500 chai')); await tester.pumpAndSettle();
    await tester.tap(find.text('Misunderstood / wrong')); await tester.pump();
    await tester.enterText(find.byType(TextField).at(0), 'sau chai');
    await tester.enterText(find.byType(TextField).at(1), '100 expense for chai');
    await tester.ensureVisible(find.text('Save review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save review'));
    await tester.runAsync(() => service.flush()); await tester.pumpAndSettle();
    expect(service.record(id)!['review']['assessment'], 'wrong');
    expect(service.record(id)!['outcome'], 'completed');
    await tester.pumpWidget(const SizedBox()); service.dispose();
  });
}

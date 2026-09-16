import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/services/biometric_service.dart';
import 'package:student_expense_manager/widgets/app_lock_gate.dart';

class _FakeAuthenticator implements DeviceAuthenticator {
  final List<Future<DeviceAuthResult> Function()> responses;
  int calls = 0;

  _FakeAuthenticator(this.responses);

  @override
  Future<bool> canUseBiometrics() async => true;

  @override
  Future<DeviceAuthResult> authenticate({
    required String reason,
    required bool biometricOnly,
  }) {
    final response = responses[calls];
    calls += 1;
    return response();
  }
}

Widget _testApp(DeviceAuthenticator authenticator) {
  return MaterialApp(
    home: AppLockGate(
      authenticator: authenticator,
      isLockEnabled: () => true,
      child: const Scaffold(body: Text('Private finance data')),
    ),
  );
}

void main() {
  testWidgets('hides financial content until authentication succeeds',
      (tester) async {
    final pending = Completer<DeviceAuthResult>();
    final authenticator = _FakeAuthenticator([
      () => pending.future,
    ]);

    await tester.pumpWidget(_testApp(authenticator));
    await tester.pump();

    expect(find.text('Likhlo is locked'), findsOneWidget);
    expect(find.text('Private finance data'), findsNothing);

    pending.complete(const DeviceAuthResult.success());
    await tester.pumpAndSettle();

    expect(find.text('Private finance data'), findsOneWidget);
    expect(find.text('Likhlo is locked'), findsNothing);
  });

  testWidgets('keeps content hidden after failure and supports retry',
      (tester) async {
    final authenticator = _FakeAuthenticator([
      () async => const DeviceAuthResult.failure('Authentication failed.'),
      () async => const DeviceAuthResult.success(),
    ]);

    await tester.pumpWidget(_testApp(authenticator));
    await tester.pumpAndSettle();

    expect(find.text('Authentication failed.'), findsOneWidget);
    expect(find.text('Private finance data'), findsNothing);

    await tester.tap(find.text('Unlock Likhlo'));
    await tester.pumpAndSettle();

    expect(find.text('Private finance data'), findsOneWidget);
    expect(authenticator.calls, 2);
  });
}

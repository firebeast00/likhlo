import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/widgets/ledger_entry_content.dart';

void main() {
  for (final width in [280.0, 320.0, 360.0, 400.0]) {
    for (final scale in [1.0, 1.3, 1.8, 2.0]) {
      testWidgets('Income Allowance fits width $width at text scale $scale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: const LedgerEntryContent(
                      title: 'Income Allowance',
                      dateLabel: 'Jumerat, November 5',
                      amountLabel: '+ Rs. 10000',
                      icon: Icons.south_west_rounded,
                      iconColor: Colors.green,
                      iconBackground: Colors.black12,
                      amountColor: Colors.green,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        final date = tester.widget<Text>(find.text('Jumerat, November 5'));
        expect(date.maxLines, 1);
        expect(date.overflow, TextOverflow.ellipsis);
        expect(find.text('+ Rs. 10000'), findsOneWidget);
        expect(
          tester.getRect(find.text('+ Rs. 10000')).right,
          lessThanOrEqualTo(width),
        );
      });
    }
  }
  testWidgets('large expense and transfer amounts keep all digits', (
    tester,
  ) async {
    for (final amount in ['- Rs. 100000000', 'Rs. 999999999999']) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 240,
              child: LedgerEntryContent(
                title: 'Long expense or transfer title',
                dateLabel: 'Wednesday, September 30',
                amountLabel: amount,
                icon: Icons.swap_horiz_rounded,
                iconColor: Colors.blue,
                iconBackground: Colors.black12,
                amountColor: Colors.blue,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text(amount), findsOneWidget);
    }
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/services/udhar_input_service.dart';
import 'package:student_expense_manager/services/local_nlp_service.dart';

void main() {
  const parser = UdharInputService();

  test('lent amount and person are safe for direct entry', () {
    final entry = parser.parse('Ali ko 500 udhaar diya');
    expect(entry?.type, 'lent');
    expect(entry?.person, 'Ali');
    expect(entry?.amount, 500);
    expect(entry?.canSaveImmediately, true);
  });

  test('borrowed money is not mistaken for money lent', () {
    final entry = parser.parse('borrowed 2 hazar from Sara');
    expect(entry?.type, 'borrowed');
    expect(entry?.person, 'Sara');
    expect(entry?.amount, 2000);
    expect(entry?.canSaveImmediately, true);
  });

  test('Urdu script lending and borrowing keep their direction', () {
    final lent = parser.parse('علی کو ۵۰۰ ادھار دیا');
    final borrowed = parser.parse('علی سے ۵۰۰ ادھار لیا');
    expect(lent?.type, 'lent');
    expect(lent?.amount, 500);
    expect(lent?.canSaveImmediately, true);
    expect(borrowed?.type, 'borrowed');
    expect(borrowed?.person, 'علی');
    expect(borrowed?.canSaveImmediately, true);
  });

  test('wallet name is excluded from person name', () {
    final entry = parser.parse(
      'JazzCash se Ali ko 1000 udhaar diya',
      walletNames: ['JazzCash', 'Cash'],
    );
    expect(entry?.person, 'Ali');
  });

  test('spoken wallet aliases are excluded from the person name', () {
    final entry = parser.parse(
      'jazz cash se Ali ko 1000 udhaar diya',
      accounts: const [
        SmartEntryAccount(
          id: 'jazzcash',
          name: 'JazzCash',
          type: 'jazzcash',
          availableBalance: 5000,
        ),
      ],
    );
    expect(entry?.person, 'Ali');
  });

  test('unspoken direction needs review', () {
    final entry = parser.parse('Ali 500');
    expect(entry?.canSaveImmediately, false);
  });

  test('ambiguous ASR money and contradictory direction cannot save', () {
    expect(parser.parse('3:30 lakh ka udhaar Ali ko diya'), isNull);
    expect(parser.parse('borrowed 500 and lent 500 to Ali'), isNull);
  });

  test('Roman Urdu amounts and debt direction use shared number parsing', () {
    final lent = parser.parse('Bilal ko derh lak udhaar diya');
    final borrowed = parser.parse('Sara se assi hazar qarz liya');
    expect(lent?.amount, 150000);
    expect(lent?.type, 'lent');
    expect(borrowed?.amount, 80000);
    expect(borrowed?.type, 'borrowed');
  });

  test('negated or alternative debt requests cannot save automatically', () {
    expect(parser.parse('Ali ko 500 udhaar mat do'), isNull);
    expect(parser.parse('Ali ko 500 diya ya nahi'), isNull);
  });
}

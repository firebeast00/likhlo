import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/services/month_reference_parser.dart';

void main() {
  test('parses relative month references', () {
    final now = DateTime(2026, 10, 5);

    expect(parseReferencedMonth('this month stats', now: now), DateTime(2026, 10));
    expect(parseReferencedMonth('last month stats', now: now), DateTime(2026, 9));
    expect(parseReferencedMonth('next month budget', now: now), DateTime(2026, 11));
    expect(
      parseReferencedMonth('pichlay mahine ka plan', now: now),
      DateTime(2026, 9),
    );
  });

  test('parses named months and explicit years', () {
    final now = DateTime(2026, 10, 5);

    expect(parseReferencedMonth('September stats', now: now), DateTime(2026, 9));
    expect(
      parseReferencedMonth('January 2027 monthly plan', now: now),
      DateTime(2027, 1),
    );
  });

  test('returns null when no month is present', () {
    expect(parseReferencedMonth('open stats'), isNull);
  });
}

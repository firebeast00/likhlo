import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/services/receipt_ocr_parser.dart';
import 'fixtures/jazzcash_receipt.dart';

void main() {
  const parser = ReceiptOcrParser();
  List<ReceiptOcrRow> rows(Iterable<String> texts) =>
      texts.map((text) => ReceiptOcrRow([ReceiptOcrCell(text)])).toList();
  test(
    'reported JazzCash layout extracts 570 and ignores account ending 7632',
    () {
      final r = parser.parseRows(jazzcashRows);
      expect(r.total, 570);
      expect(r.items, isEmpty);
      expect(r.payment!.principal, 570);
      expect(r.payment!.fee, 0);
      expect(r.payment!.recipient, 'Test Recipient');
      expect(r.purchaseTitle, 'Food and Groceries Purchases');
      expect(r.category, 'Food');
      expect(r.needsReview, isFalse);
    },
  );
  test(
    'selecting just Rs 570 and To keeps amount and non-financial context',
    () {
      final r = parser.parseSelection(
        allRows: rows(jazzcashRows),
        selectedRows: rows(['Rs. 570.00', 'To']),
      );
      expect(r.total, 570);
      expect(r.items, isEmpty);
      expect(r.purchaseTitle, 'Food and Groceries Purchases');
      expect(r.payment!.recipient, 'Test Recipient');
      expect(r.needsReview, isFalse);
    },
  );
  test('currency-only selection can be read without full context', () {
    final r = parser.parseRows(['Rs. 570.00', 'To']);
    expect(r.total, 570);
    expect(r.items, isEmpty);
    expect(r.vendor, isNot('To'));
  });
  test('masks and OCR letter noise never become item prices', () {
    for (final mask in [
      '*******7632',
      '*****k **7632',
      'XXXX7632',
      '••••7632',
    ]) {
      expect(parser.isLikelyUsefulLine(mask), isFalse);
      final r = parser.parseRows(['SHOP', 'Items', 'To Test Recipient', mask]);
      expect(r.total, 0, reason: mask);
      expect(r.items, isEmpty, reason: mask);
    }
  });
  test(
    'selection preserves separately recognized currency, digits and decimals',
    () {
      final r = parser.parseRows(jazzcashRows);
      for (final text in ['Rs.', '570.00', '.00', 'Fee', 'Rs. 0.00']) {
        expect(parser.isDigitalSelectionLine(text, r), isTrue, reason: text);
      }
      for (final text in ['*******7632', 'TID: 111222333444', '03001234567']) {
        expect(parser.isDigitalSelectionLine(text, r), isFalse, reason: text);
      }
    },
  );
  test(
    'removing headline does not restore original money or use account digits',
    () {
      final r = parser.parseSelection(
        allRows: rows(jazzcashRows),
        selectedRows: rows(['To Test Recipient', '*******7632', 'Rs. 0.00']),
      );
      expect(r.total, 0);
      expect(r.items, isEmpty);
      expect(r.needsReview, isTrue);
    },
  );
  test('explicitly selected replacement money is respected', () {
    final r = parser.parseSelection(
      allRows: rows(jazzcashRows),
      selectedRows: rows(['Rs. 580.00', 'To']),
    );
    expect(r.total, 580);
  });
  test('fee is included once with or without a printed grand total', () {
    for (final net in [false, true]) {
      final r = parser.parseRows([
        'JazzCash',
        'Transaction Successful',
        'TID: 111222333444',
        'Rs. 570.00',
        'Fee Rs. 20.00',
        if (net) 'Grand Total Rs. 590.00',
        'To Test Recipient',
        '*******7632',
      ]);
      expect(r.total, 590);
      expect(r.payment!.principal, 570);
      expect(r.payment!.fee, 20);
      expect(r.items, isEmpty);
    }
  });
  test('separate fee label, recipient label and superscript decimals', () {
    final r = parser.parseSpatialRows(
      rows([
        'Transaction Successful',
        'TID: 111222333444',
        'Rs. 570 . 50',
        'Transferred to Other Wallet',
        'Fee',
        'Rs. 0.00',
        'To',
        'Test Recipient',
        '*******7632',
      ]),
    );
    expect(r.total, 570.5);
    expect(r.payment!.recipient, 'Test Recipient');
    expect(r.payment!.fee, 0);
  });
  test('different headline amounts require checking', () {
    final r = parser.parseRows([
      'Transaction Successful',
      'TID: 111222333444',
      'Rs. 570.00',
      'Rs. 7632.00',
      'To Test Recipient',
    ]);
    expect(r.issues, contains('receipt_conflicting_totals'));
  });
  test('fee and identifiers alone never create a payment', () {
    final r = parser.parseRows([
      'Transaction Successful',
      'TID: 111222333444',
      'Fee Rs. 0.00',
      'To Test Recipient',
      '*******7632',
    ]);
    expect(r.total, 0);
    expect(r.items, isEmpty);
    expect(r.needsReview, isTrue);
  });
  test('a grocery table with a successful-payment footer remains itemized', () {
    final r = parser.parseRows([
      'SHOP',
      'Item Qty Rate Amount',
      'Milk 2 150 300',
      'Bread 1 180 180',
      'Total 480',
      'Transaction Successful',
    ]);
    expect(r.items.map((item) => item.name), ['Milk', 'Bread']);
    expect(r.total, 480);
  });
}

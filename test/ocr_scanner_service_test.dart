import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/services/ocr_scanner_service.dart';

void main() {
  const parser = ReceiptOcrParser();

  group('ReceiptOcrParser', () {
    test('extracts supermarket items and prefers grand total over subtotal', () {
      final receipt = parser.parseRows([
        'AL FATAH',
        'Invoice No 128833',
        'Milk 2 x 150.00 300.00',
        'Bread 180.00',
        'SUB TOTAL 480.00',
        'Tax 0.00',
        'GRAND TOTAL PKR 480.00',
        'Thank you',
      ]);

      expect(receipt.vendor, 'AL FATAH');
      expect(receipt.total, 480);
      expect(receipt.items.map((item) => item.name), ['Milk', 'Bread']);
      expect(receipt.items.map((item) => item.price), [300, 180]);
      expect(receipt.confidence, greaterThanOrEqualTo(0.9));
    });

    test('reads a digital payment total without creating metadata items', () {
      final receipt = parser.parseRows([
        'JAZZCASH',
        'Transaction Successful',
        'Transaction Amount Rs. 1,500.00',
        'TID 123456789012',
        'Date: 04/10/2026 10:30',
      ]);

      expect(receipt.vendor, 'JAZZCASH');
      expect(receipt.total, 1500);
      expect(receipt.items, isEmpty);
      expect(receipt.confidence, greaterThan(0.6));
    });

    test('pairs a standalone item name with the following amount row', () {
      final receipt = parser.parseRows([
        'CAFE ONE',
        'Receipt',
        'Coffee Latte',
        'Rs. 450.00',
        'TOTAL 450.00',
      ]);

      expect(receipt.total, 450);
      expect(receipt.items, hasLength(1));
      expect(receipt.items.single.name, 'Coffee Latte');
      expect(receipt.items.single.price, 450);
    });

    test('does not treat tax change dates or invoice numbers as items', () {
      final receipt = parser.parseRows([
        'STORE',
        'Invoice 87654321',
        'Date 04/10/2026',
        'Burger 700',
        'Tax 70',
        'Cash Tendered 1000',
        'Change 230',
        'Total 770',
      ]);

      expect(receipt.total, 770);
      expect(receipt.items, hasLength(1));
      expect(receipt.items.single.name, 'Burger');
      expect(receipt.items.single.price, 700);
    });

    test('uses item sum when no reliable printed total exists', () {
      final receipt = parser.parseRows([
        'MINI MART',
        'Items',
        'Water 100',
        'Chips 150',
      ]);

      expect(receipt.total, 250);
      expect(receipt.items, hasLength(2));
      expect(receipt.confidence, greaterThan(0.5));
    });

    test('normalizes OCR letter O inside numeric amounts', () {
      final receipt = parser.parseRows([
        'SHOP',
        'Item A 1O0',
        'TOTAL 1O0',
      ]);

      expect(receipt.total, 100);
      expect(receipt.items.single.price, 100);
    });

    test('selection heuristic rejects common receipt metadata', () {
      expect(parser.isLikelyUsefulLine('Invoice No 12345'), isFalse);
      expect(parser.isLikelyUsefulLine('Date: 04/10/2026'), isFalse);
      expect(parser.isLikelyUsefulLine('TID 123456789012'), isFalse);
      expect(parser.isLikelyUsefulLine('GRAND TOTAL PKR 850.00'), isTrue);
      expect(parser.isLikelyUsefulLine('Chicken Burger 650.00'), isTrue);
    });
  });
}

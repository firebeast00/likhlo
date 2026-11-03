import 'package:flutter_test/flutter_test.dart';
import 'package:student_expense_manager/services/receipt_ocr_parser.dart';

void main() {
  const parser = ReceiptOcrParser();
  ScannedReceipt scan(List<String> body) =>
      parser.parseRows(['MINI MART', 'Items', ...body]);

  test('separate numeric columns never become a multi-million amount', () {
    final receipt = scan(['Milk 2 150 300', 'Bread 1 180 180', 'Total 480']);
    expect(receipt.items.map((item) => item.price), [300, 180]);
    expect(receipt.items.map((item) => item.name), ['Milk', 'Bread']);
    expect(receipt.needsReview, isFalse);
  });
  test(
    'unlabelled dates, headers, addresses and identifiers never become products',
    () {
      final receipt = scan([
        'Description Qty Rate Amount',
        'Main Road 42',
        '03/11/2026 11:45',
        '0312 1234567',
        'NTN 87654321',
        'STRN 123456789012345',
        'Rice 1500',
        'Cash 2000',
        'Change 500',
        'Total 1500',
      ]);
      expect(receipt.items.map((item) => item.name), ['Rice']);
      expect(receipt.total, 1500);
    },
  );
  test('date does not supply an amount for a pending heading', () {
    final receipt = scan([
      'SALES SUMMARY',
      '03/11/2026',
      'Milk 300',
      'Total 300',
    ]);
    expect(receipt.items.map((item) => item.name), ['Milk']);
    expect(receipt.items.single.price, 300);
  });
  test('preserves product sizes, embedded digits and removes leading SKU', () {
    final receipt = scan([
      '123456789 Rice 5 kg 1 1500 1500',
      '7Up 500 ml 1 120 120',
      'Total 1620',
    ]);
    expect(receipt.items.map((item) => item.name), ['Rice 5 kg', '7Up 500 ml']);
    expect(receipt.items.map((item) => item.price), [1500, 120]);
  });
  test('pairs wrapped names and a following currency amount', () {
    final receipt = scan([
      'Premium Chicken',
      'Burger Meal',
      'Rs. 650.00',
      'Total 650',
    ]);
    expect(receipt.items.single.name, 'Premium Chicken Burger Meal');
    expect(receipt.items.single.price, 650);
  });
  test('quantity mismatch highlights only the affected item', () {
    final receipt = scan(['Milk 2 150 200', 'Bread 180', 'Total 380']);
    expect(receipt.items.first.issue, 'receipt_quantity_mismatch');
    expect(receipt.items.last.needsReview, isFalse);
    expect(receipt.needsReview, isTrue);
  });
  test('tax and discounts reconcile without becoming products', () {
    final receipt = scan([
      'Burger 700',
      'Subtotal 700',
      'Tax 10% 70',
      'Discount 20',
      'Grand Total 750',
      'Cash 1000',
      'Change 250',
    ]);
    expect(receipt.items, hasLength(1));
    expect(receipt.adjustmentTotal, 50);
    expect(receipt.total, 750);
    expect(receipt.issues, isEmpty);
    expect(receipt.purchaseTitle, 'Burger');
  });
  test('percentage-only tax is not mistaken for a currency amount', () {
    final receipt = scan(['Burger 700', 'Tax 10%', 'Total 770']);
    expect(receipt.adjustments, isEmpty);
    expect(receipt.issues, contains('receipt_total_mismatch'));
  });
  test('reads split total label and value without turning it into an item', () {
    final receipt = scan(['Coffee 450', 'Grand Total', 'Rs. 450.00']);
    expect(receipt.total, 450);
    expect(receipt.hasPrintedTotal, isTrue);
    expect(receipt.items, hasLength(1));
  });
  test(
    'huge identifiers cannot become expenses or fall back to their fragments',
    () {
      final receipt = scan(['Widget 123456789012345', 'Total 123456789012345']);
      expect(receipt.total, 0);
      expect(receipt.items, isEmpty);
      expect(receipt.issues, contains('receipt_amount_uncertain'));
    },
  );
  test('conflicting equally ranked totals require checking', () {
    final receipt = scan(['Milk 300', 'Total 300', 'Total 3000']);
    expect(receipt.issues, contains('receipt_conflicting_totals'));
  });
  test('two unlabelled numeric columns remain uncertain', () {
    expect(scan(['Milk 150 300']).items.single.needsReview, isTrue);
    expect(scan(['Milk 1 500']).items.single.needsReview, isTrue);
  });
  test('total fallback does not fabricate products', () {
    final receipt = parser.parseRows([
      'JAZZCASH',
      'Transaction Successful',
      'Transaction Amount Rs. 1,500.00',
      'TID 123456789012',
      'Date 03/11/2026',
    ]);
    expect(receipt.total, 1500);
    expect(receipt.items, isEmpty);
  });
  test('metadata-only and empty receipts produce no expense', () {
    for (final rows in <List<String>>[
      [],
      ['SHOP', 'Invoice 123456', '03/11/2026', 'Cash 2000'],
    ]) {
      final receipt = parser.parseRows(rows);
      expect(receipt.total, 0);
      expect(receipt.items, isEmpty);
    }
  });
  test('same products on separate rows are not silently deduplicated', () {
    final receipt = scan(['Milk 300', 'Milk 300', 'Total 600']);
    expect(receipt.items, hasLength(2));
    expect(receipt.itemSum, 600);
  });
  test('zero priced lines do not become invalid ledger entries', () {
    expect(scan(['Free Bag 0', 'Bread 180', 'Total 180']).items, hasLength(1));
  });
  test('footer numbers do not reopen the product table', () {
    final receipt = scan(['Milk 300', 'Total 300', 'Points Earned 2026']);
    expect(receipt.items.map((item) => item.name), ['Milk']);
  });
  test('unambiguous product categories are inferred independently', () {
    final receipt = scan(['Milk 300', 'Notebook 150', 'Total 450']);
    expect(receipt.items.map((item) => item.category), ['Food', 'Education']);
    expect(receipt.category, 'General');
  });
  test('positioned columns distinguish quantity from amount', () {
    final receipt = parser.parseSpatialRows([
      const ReceiptOcrRow([ReceiptOcrCell('SHOP')]),
      const ReceiptOcrRow([
        ReceiptOcrCell('Item', left: 0, right: 80),
        ReceiptOcrCell('Qty', left: 110, right: 140),
        ReceiptOcrCell('Amount', left: 200, right: 250),
      ]),
      const ReceiptOcrRow(
        [
          ReceiptOcrCell('Milk', left: 0, right: 80),
          ReceiptOcrCell('2', left: 110, right: 140),
          ReceiptOcrCell('300', left: 200, right: 250),
        ],
        centerY: 40,
        height: 12,
      ),
      const ReceiptOcrRow([ReceiptOcrCell('Total 300')]),
    ]);
    expect(receipt.items.single.price, 300);
    expect(receipt.items.single.needsReview, isFalse);
  });
  test('distant name and amount fragments are not paired', () {
    final receipt = parser.parseSpatialRows([
      const ReceiptOcrRow([ReceiptOcrCell('SHOP')], centerY: 0, height: 10),
      const ReceiptOcrRow([ReceiptOcrCell('Items')], centerY: 20, height: 10),
      const ReceiptOcrRow([ReceiptOcrCell('Coffee')], centerY: 40, height: 10),
      const ReceiptOcrRow([ReceiptOcrCell('450')], centerY: 200, height: 10),
    ]);
    expect(receipt.items, isEmpty);
  });
  test('decimal prices and comma grouping are not dates', () {
    for (final example in {
      '1.50': 1.5,
      '100.50': 100.5,
      '1,500.50': 1500.5,
      '1.500,50': 1500.5,
      '1500,50': 1500.5,
    }.entries) {
      final r = scan(['Bread ${example.key}', 'Total ${example.key}']);
      expect(r.items.single.price, example.value);
      expect(r.total, example.value);
    }
  });
  test('named and short slash dates are excluded', () {
    final r = scan([
      '3 November 2026',
      'Nov 3, 2026',
      '03/11',
      'Milk 300',
      'Total 300',
    ]);
    expect(r.items.map((i) => i.name), ['Milk']);
  });
  test(
    'negative discount reconciles but negative purchase is not a positive expense',
    () {
      final r = scan([
        'Bread 180',
        'Subtotal 180',
        'Discount -20',
        'Total 160',
      ]);
      expect(r.adjustmentTotal, -20);
      expect(r.issues, isEmpty);
      expect(scan(['Refund -300']).items, isEmpty);
    },
  );
  test(
      'header-area numbers and document headings are excluded from item entries',
      () {
    final r = parser.parseRows([
      'SHOP',
      'Special Branch 2026',
      'CASH SALES',
      'SALES SUMMARY',
      'Description Qty Rate Amount',
      'Bread 1 180 180',
      'Total 180'
    ]);
    expect(r.items.map((i) => i.name), ['Bread']);
    expect(r.total, 180);
    expect(
        scan(['SALES SUMMARY', '2026', 'Milk 300', 'Total 300'])
            .items
            .map((i) => i.name),
        ['Milk']);
  });
  test('uses the amount column even when another numeric column follows', () {
    final r = parser.parseSpatialRows([
      const ReceiptOcrRow([ReceiptOcrCell('SHOP')]),
      const ReceiptOcrRow([
        ReceiptOcrCell('Item', left: 0, right: 80),
        ReceiptOcrCell('Qty', left: 100, right: 120),
        ReceiptOcrCell('Rate', left: 140, right: 180),
        ReceiptOcrCell('Amount', left: 200, right: 250),
        ReceiptOcrCell('Tax', left: 280, right: 300)
      ]),
      const ReceiptOcrRow([
        ReceiptOcrCell('Milk', left: 0, right: 80),
        ReceiptOcrCell('2', left: 100, right: 120),
        ReceiptOcrCell('150', left: 140, right: 180),
        ReceiptOcrCell('300', left: 200, right: 250),
        ReceiptOcrCell('1', left: 280, right: 300)
      ], height: 12),
      const ReceiptOcrRow([ReceiptOcrCell('Total 300')]),
    ]);
    expect(r.items.single.price, 300);
    expect(r.items.single.needsReview, isFalse);
  });
  test('100 generated receipt variants retain product-amount pairs', () {
    for (var i = 1; i <= 100; i++) {
      final rate = 100 + i;
      final qty = i % 4 + 1;
      final amount = rate * qty;
      final receipt = scan([
        'Date: 03/11/2026',
        'Invoice No 12345678$i',
        'Milk 1 L $qty $rate $amount',
        'Grand Total PKR $amount',
        'Cash ${amount + 1000}',
        'Change 1000',
      ]);
      expect(receipt.items.single.name, 'Milk 1 L', reason: 'variant $i');
      expect(receipt.items.single.price, amount, reason: 'variant $i');
      expect(receipt.needsReview, isFalse, reason: 'variant $i');
    }
  });
}

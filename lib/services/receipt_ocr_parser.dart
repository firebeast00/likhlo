part 'digital_receipt_parser.dart';

/// Receipt-specific interpretation. No ledger mutations or general NLP parsing.
class ReceiptOcrCell {
  final String text;
  final double? left;
  final double? right;
  const ReceiptOcrCell(this.text, {this.left, this.right});
}

class ReceiptOcrRow {
  final List<ReceiptOcrCell> cells;
  final double? centerY;
  final double? height;
  const ReceiptOcrRow(this.cells, {this.centerY, this.height});
  String get text => cells.map((cell) => cell.text).join(' ').trim();
}

class ReceiptItem {
  final String name;
  final double price;
  final String category;
  final String? issue;
  final double confidence;
  const ReceiptItem({
    required this.name,
    required this.price,
    this.category = 'General',
    this.issue,
    this.confidence = 0.92,
  });
  bool get needsReview => issue != null;
  Map<String, dynamic> toJson() => {
    'name': name,
    'price': price,
    'category': category,
    'issue': issue,
    'confidence': confidence,
  };
  @override
  String toString() => '$name: $price';
}

class ReceiptAdjustment {
  final String label;
  final double amount;
  const ReceiptAdjustment(this.label, this.amount);
}

class ScannedReceipt {
  final String vendor;
  final double total;
  final String category;
  final List<ReceiptItem> items;
  final String description;
  final String rawText;
  final double confidence;
  final List<ReceiptAdjustment> adjustments;
  final List<String> issues;
  final bool hasPrintedTotal;
  final DigitalReceiptDetails? payment;
  const ScannedReceipt({
    required this.vendor,
    required this.total,
    required this.category,
    required this.items,
    required this.description,
    required this.rawText,
    required this.confidence,
    this.adjustments = const [],
    this.issues = const [],
    this.hasPrintedTotal = false,
    this.payment,
  });
  double get itemSum => items.fold(0, (sum, item) => sum + item.price);
  double get adjustmentTotal =>
      adjustments.fold(0, (sum, item) => sum + item.amount);
  bool get needsReview =>
      issues.isNotEmpty || items.any((item) => item.needsReview);
  bool get isDigitalPayment => payment != null;
  String get purchaseTitle =>
      payment?.purpose ??
      (payment?.recipient == null ? null : 'To ${payment!.recipient}') ??
      (items.isEmpty
          ? vendor
          : items.map((item) => item.name).take(3).join(', '));
  Map<String, dynamic> toJson() => {
    'title': purchaseTitle,
    'amount': total,
    'category': category,
    'description': description,
    'items': items.map((item) => item.toJson()).toList(),
    'rawText': rawText,
    'confidence': confidence,
    'issues': issues,
    if (payment != null) 'payment': payment!.toJson(),
  };
}

class ReceiptOcrParser {
  const ReceiptOcrParser();
  // Whitespace never joins numbers: "2 150 300" is three columns.
  static final _number = RegExp(r'(?<![\w./:+])\d+(?:[.,]\d+)*(?![\w/:-])');
  static final _currency = RegExp(
    r'\b(?:rs|pkr|rupees?)\b\.?|/-|/=',
    caseSensitive: false,
  );
  static final _date = RegExp(
    r'\b(?:\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4}|\d{1,2}[-/]\d{1,2}|\d{4}[-/.]\d{1,2}[-/.]\d{1,2}|\d{1,2}:\d{2}(?::\d{2})?)\b',
  );
  static final _namedDate = RegExp(
    r'\b(?:\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{2,4}|(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{1,2},?\s+\d{2,4})\b',
    caseSensitive: false,
  );
  static final _metadata = RegExp(
    r'\b(?:date|time|phone|mobile|tel|contact|invoice|receipt|ref(?:erence)?|tid|trx|transaction\s*id|terminal|branch|counter|cashier|customer|card|visa|mastercard|auth(?:orization)?|cnic|ntn|strn|barcode|sku|fbr|bill\s*(?:no|number)|order\s*(?:no|number))\b',
    caseSensitive: false,
  );
  static final _address = RegExp(
    r'\b(?:road|street|avenue|sector|block|address|www|https?)\b|\b(?:rd|st)\.',
    caseSensitive: false,
  );
  static final _noise = RegExp(
    r'\b(?:successful|success|failed|completed|approved|powered\s+by|thank\s*you|thanks|welcome|merchant\s*copy|customer\s*copy)\b',
    caseSensitive: false,
  );
  static final _header = RegExp(
    r'^(?:(?:item|items|description|product|products|particulars|name|qty|quantity|rate|unit|price|amount|no|sno|sr|total|code|tax)\.?\s*)+$',
    caseSensitive: false,
  );
  static final _documentHeading = RegExp(
    r'^(?:sales\s*summary|purchase\s*summary|cash\s*memo|bill|tax\s*invoice|duplicate\s*copy)\b',
    caseSensitive: false,
  );
  static final _unit = RegExp(
    r'^\s*(?:kg|gm|g|mg|ml|litres?|liters?|ltr|l|pcs|pc|packs?)\b',
    caseSensitive: false,
  );
  static final _payment = RegExp(
    r'^(?:cash(?:\s*(?:paid|tendered|received))?|tendered|change|balance|opening\s*balance|closing\s*balance|payment|paid\s*(?:by|via))\b',
    caseSensitive: false,
  );
  static final _adjustment = RegExp(
    r'^(?:tax|vat|gst|sales\s*tax|service\s*charge|charges?|discount|round\s*off)\b',
    caseSensitive: false,
  );
  static final _subtotal = RegExp(r'^sub\s*total\b', caseSensitive: false);
  static const maxAmount = 100000000.0;

  ScannedReceipt parseRows(Iterable<String> rows) =>
      parseSpatialRows(rows.map((row) => ReceiptOcrRow([ReceiptOcrCell(row)])));

  bool isReceiptContextLine(String text) {
    final value = _normalize(text);
    return _totalScore(value) > 0 ||
        _header.hasMatch(value) ||
        _adjustment.hasMatch(value) ||
        _subtotal.hasMatch(value);
  }

  bool isLikelyUsefulLine(String text) {
    final normalized = _normalize(text);
    if (normalized.isEmpty || _blocked(normalized)) return false;
    if (_totalScore(normalized) > 0) return true;
    if (_header.hasMatch(normalized) ||
        _adjustment.hasMatch(normalized) ||
        _subtotal.hasMatch(normalized) ||
        _payment.hasMatch(normalized))
      return false;
    return _goodName(normalized) || _amounts(normalized).isNotEmpty;
  }

  ScannedReceipt parseSpatialRows(Iterable<ReceiptOcrRow> source) {
    final rows = source.where((row) => row.text.trim().isNotEmpty).toList();
    final digital = _parseDigitalReceipt(rows);
    if (digital != null) return digital;
    final items = <ReceiptItem>[];
    final totals = <_Total>[];
    final adjustments = <ReceiptAdjustment>[];
    final issues = <String>{};
    var vendor = 'Scanned receipt';
    var vendorIndex = -1;
    for (var i = 0; i < rows.length && i < 6; i++) {
      final text = _normalize(rows[i].text);
      if (_goodName(text) &&
          !_header.hasMatch(text) &&
          _amounts(text).isEmpty &&
          !_unit.hasMatch(text)) {
        vendor = text;
        vendorIndex = i;
        break;
      }
    }

    final tableStart = rows.indexWhere(
      (row) =>
          _header.hasMatch(_normalize(row.text)) &&
          RegExp(
            r'\b(?:qty|quantity|rate|price|amount)\b',
            caseSensitive: false,
          ).hasMatch(row.text),
    );
    String? pendingName;
    ReceiptOcrRow? pendingRow;
    var inSummary = false;
    int? pendingTotal;
    double? amountColumn;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final text = _normalize(row.text);
      final score = _totalScore(text);
      final amounts = _amounts(text);
      if (score > 0) {
        inSummary = true;
        pendingName = null;
        pendingRow = null;
        pendingTotal = amounts.isEmpty ? score : null;
        if (amounts.isNotEmpty) {
          if (amounts.last.value <= maxAmount) {
            totals.add(_Total(amounts.last.value, score));
          } else {
            issues.add('receipt_amount_uncertain');
          }
          if (amounts.length > 1) issues.add('receipt_amount_uncertain');
        }
        continue;
      }
      if (pendingTotal != null &&
          amounts.length == 1 &&
          !_letters(text.replaceAll(_currency, '')) &&
          !_blocked(text)) {
        if (amounts.single.value <= maxAmount) {
          totals.add(_Total(amounts.single.value, pendingTotal));
        } else {
          issues.add('receipt_amount_uncertain');
        }
        pendingTotal = null;
        continue;
      }
      pendingTotal = null;
      if (_adjustment.hasMatch(text)) {
        if (amounts.isNotEmpty && amounts.last.value <= maxAmount) {
          final discount = text.toLowerCase().startsWith('discount');
          final roundOff = text.toLowerCase().startsWith('round');
          final negative = discount || (roundOff && text.contains('-'));
          final percentOnly = text
              .substring(amounts.last.end)
              .trim()
              .startsWith('%');
          if (!percentOnly) {
            adjustments.add(
              ReceiptAdjustment(
                discount
                    ? 'Discount'
                    : roundOff
                    ? 'Rounding'
                    : 'Tax / charges',
                amounts.last.value * (negative ? -1 : 1),
              ),
            );
          }
        }
        pendingName = null;
        pendingRow = null;
        continue;
      }
      if (_subtotal.hasMatch(text) || _payment.hasMatch(text)) {
        inSummary = true;
        pendingName = null;
        pendingRow = null;
        continue;
      }
      if (_header.hasMatch(text)) {
        if (i == tableStart) inSummary = false;
        for (final cell in row.cells) {
          if (RegExp(
            r'^(?:amount|total)$',
            caseSensitive: false,
          ).hasMatch(cell.text)) {
            amountColumn = cell.right;
          }
        }
        pendingName = null;
        pendingRow = null;
        continue;
      }
      if (i == vendorIndex ||
          (tableStart >= 0 && i < tableStart) ||
          _blocked(text) ||
          inSummary) {
        pendingName = null;
        pendingRow = null;
        continue;
      }
      if (amounts.isEmpty) {
        if (_goodName(text) && (i >= 2 || vendorIndex < 0)) {
          final near = pendingRow == null || _adjacent(pendingRow, row);
          pendingName = pendingName != null && near
              ? '$pendingName $text'
              : text;
          pendingRow = row;
        } else {
          pendingName = null;
          pendingRow = null;
        }
        continue;
      }
      // A long identifier at the end is never replaced with an earlier number.
      if (amounts.last.value > maxAmount) {
        issues.add('receipt_amount_uncertain');
        pendingName = null;
        pendingRow = null;
        continue;
      }
      var chosen = amounts.length - 1;
      var alignedColumn = false;
      if (amountColumn != null) {
        var distance = double.infinity;
        for (var j = 0; j < amounts.length; j++) {
          final right = _rightForAmount(row, amounts[j]);
          if (right != null && (right - amountColumn).abs() < distance) {
            chosen = j;
            distance = (right - amountColumn).abs();
          }
        }
        alignedColumn = distance <= (row.height ?? 12) * 3;
        if (!alignedColumn) chosen = amounts.length - 1;
      }
      final last = amounts[chosen];
      if (last.value <= 0) continue;
      var first = chosen;
      while (first > 0 &&
          RegExp(r'^[\s xX@*×]*$').hasMatch(
            text.substring(amounts[first - 1].end, amounts[first].start),
          )) {
        first--;
      }
      var name = text
          .substring(0, amounts[first].start)
          .replaceAll(_currency, ' ')
          .replaceAll(RegExp(r'^[\s.:-]+|[\s.:-]+$'), '')
          .trim();
      // Strip a leading printed SKU while retaining sizes embedded in names.
      name = name.replaceFirst(RegExp(r'^\d{5,}\s+'), '').trim();
      name = name.replaceFirst(
        RegExp(r'^\d+\s*[x×]\s*', caseSensitive: false),
        '',
      );
      if (pendingName != null &&
          pendingRow != null &&
          _adjacent(pendingRow, row)) {
        name = name.isEmpty ? pendingName : '$pendingName $name';
      }
      pendingName = null;
      pendingRow = null;
      if (!_goodName(name)) continue;
      final suffix = text.substring(last.end).replaceAll(_currency, '').trim();
      if (suffix.isNotEmpty &&
          !RegExp(r'^[*A-D]$').hasMatch(suffix) &&
          !(alignedColumn && RegExp(r'^[\d., %A-D*]+$').hasMatch(suffix)))
        continue;
      String? issue;
      final numericColumns = amounts.sublist(first, chosen + 1);
      if (numericColumns.length >= 3) {
        final q = numericColumns[numericColumns.length - 3].value;
        final rate = numericColumns[numericColumns.length - 2].value;
        if (!_close(q * rate, last.value)) issue = 'receipt_quantity_mismatch';
      } else if (numericColumns.length == 2) {
        // Qty + line amount is valid only with a small integer quantity or a
        // known amount column. Two arbitrary prices need a targeted check.
        final quantity = numericColumns.first.value;
        if (!alignedColumn ||
            quantity != quantity.truncateToDouble() ||
            quantity > 99 ||
            RegExp(
              r'[x×@*]',
            ).hasMatch(text.substring(numericColumns.first.end, last.start))) {
          issue = 'receipt_amount_uncertain';
        }
      }
      if (last.value >= 1000000) issue = 'receipt_amount_uncertain';
      if (amountColumn != null) {
        final x = _rightForAmount(row, last);
        if (x != null && (x - amountColumn).abs() > (row.height ?? 12) * 3) {
          issue = 'receipt_amount_uncertain';
        }
      }
      // Product names with no row geometry are allowed, but geometry prevents
      // pairing an adjacent-looking number from a distant part of the image.
      items.add(
        ReceiptItem(
          name: name,
          price: last.value,
          category: categoryFor(name),
          issue: issue,
          confidence: issue == null ? 0.95 : 0.55,
        ),
      );
    }

    if (items.isEmpty && totals.isEmpty) {
      for (var i = 0; i < rows.length; i++) {
        final money = _currencyAmount(rows[i].text);
        if (money != null &&
            money > 0 &&
            money <= maxAmount &&
            (i == 0 || !_feeLabel.hasMatch(rows[i - 1].text))) {
          totals.add(_Total(money, 60));
        }
      }
    }
    totals.sort((a, b) => b.score.compareTo(a.score));
    final itemSum = items.fold<double>(0, (sum, item) => sum + item.price);
    final adjustmentSum = adjustments.fold<double>(
      0,
      (sum, a) => sum + a.amount,
    );
    final hasTotal = totals.isNotEmpty;
    final total = hasTotal ? totals.first.amount : itemSum + adjustmentSum;
    if (hasTotal &&
        totals.any(
          (t) =>
              t.score == totals.first.score &&
              !_close(t.amount, totals.first.amount),
        )) {
      issues.add('receipt_conflicting_totals');
    }
    if (hasTotal &&
        items.isNotEmpty &&
        !_close(itemSum + adjustmentSum, total)) {
      issues.add('receipt_total_mismatch');
    }
    if (total > maxAmount || total < 0 || !total.isFinite) {
      issues.add('receipt_amount_uncertain');
    }
    final categories = items.map((item) => item.category).toSet();
    var confidence = hasTotal ? 0.7 : 0.4;
    if (items.isNotEmpty) confidence += 0.18;
    if (vendorIndex >= 0) confidence += 0.05;
    if (hasTotal && items.isNotEmpty && _close(itemSum + adjustmentSum, total))
      confidence += 0.05;
    if (issues.isNotEmpty || items.any((item) => item.needsReview))
      confidence = 0.55;
    return ScannedReceipt(
      vendor: vendor,
      total: total.isFinite && total >= 0 && total <= maxAmount ? total : 0,
      category: categories.length == 1 ? categories.single : 'General',
      items: List.unmodifiable(items),
      description: items.map((i) => i.name).take(3).join(', '),
      rawText: rows.map((r) => r.text).join('\n'),
      confidence: confidence,
      adjustments: List.unmodifiable(adjustments),
      issues: List.unmodifiable(issues),
      hasPrintedTotal: hasTotal,
    );
  }

  static String categoryFor(String name) {
    const words = {
      'Food':
          r'\b(?:food|groceries|grocery|milk|bread|rice|water|chips|chicken|burger|coffee|tea|sugar|flour|eggs?|juice|biscuits?|doodh|chawal|atta|chai|roti)\b',
      'Health':
          r'\b(?:medicine|panadol|paracetamol|tablets?|capsules?|syrup|bandage)\b',
      'Education':
          r'\b(?:notebooks?|textbooks?|pencils?|pens?|stationery|books?)\b',
      'Transport': r'\b(?:petrol|diesel|fuel|fare|ticket)\b',
      'Shopping':
          r'\b(?:shampoo|soap|detergent|shirt|shoes|toothpaste|tissue)\b',
    };
    final matches = words.entries
        .where(
          (entry) => RegExp(entry.value, caseSensitive: false).hasMatch(name),
        )
        .toList();
    return matches.length == 1 ? matches.single.key : 'General';
  }

  bool _blocked(String text) =>
      _accountMask.hasMatch(text) ||
      _partyLabel.hasMatch(text) ||
      _feeLabel.hasMatch(text) ||
      _date.hasMatch(text) ||
      _namedDate.hasMatch(text) ||
      _metadata.hasMatch(text) ||
      _address.hasMatch(text) ||
      _noise.hasMatch(text) ||
      _documentHeading.hasMatch(text) ||
      RegExp(r'^\+?\d[\d\s-]{8,}$').hasMatch(text) && !_currency.hasMatch(text);
  bool _goodName(String text) =>
      text.length >= 2 &&
      text.length <= 100 &&
      _letters(text) &&
      !_blocked(text) &&
      !_header.hasMatch(text) &&
      !_payment.hasMatch(text) &&
      !_adjustment.hasMatch(text) &&
      !_subtotal.hasMatch(text) &&
      _totalScore(text) == 0;
  bool _letters(String text) => RegExp(r'[A-Za-z]').hasMatch(text);
  bool _close(double a, double b) =>
      (a - b).abs() <= (b.abs() * 0.001 > 1 ? b.abs() * 0.001 : 1);
  bool _adjacent(ReceiptOcrRow a, ReceiptOcrRow b) =>
      a.centerY == null ||
      b.centerY == null ||
      (b.centerY! - a.centerY!).abs() <=
          ((a.height ?? 12) + (b.height ?? 12)) * 1.5;

  int _totalScore(String text) {
    if (_subtotal.hasMatch(text)) return 0;
    if (RegExp(r'^grand\s*total\b', caseSensitive: false).hasMatch(text))
      return 100;
    if (RegExp(
      r'^(?:net\s*(?:payable|amount|total)|amount\s*(?:paid|due|payable))\b',
      caseSensitive: false,
    ).hasMatch(text))
      return 95;
    if (RegExp(
      r'^(?:total\s*(?:amount|payable|due)|bill\s*total|invoice\s*total|transaction\s*amount)\b',
      caseSensitive: false,
    ).hasMatch(text))
      return 90;
    if (RegExp(r'^total\b', caseSensitive: false).hasMatch(text) &&
        !_letters(
          text
              .replaceFirst(RegExp(r'^total\b', caseSensitive: false), '')
              .replaceAll(_currency, ''),
        ))
      return 80;
    return 0;
  }

  List<_Amount> _amounts(String text) {
    final result = <_Amount>[];
    for (final match in _number.allMatches(text)) {
      if (match.start > 0 &&
          text[match.start - 1] == '-' &&
          !_adjustment.hasMatch(text))
        continue;
      if (_unit.hasMatch(text.substring(match.end))) continue;
      if (text.substring(match.end).trimLeft().startsWith('%')) continue;
      final value = _parseNumber(match.group(0)!);
      if (value != null) result.add(_Amount(value, match.start, match.end));
    }
    return result;
  }

  double? _parseNumber(String text) {
    var normalized = text;
    if (text.contains(',') && text.contains('.')) {
      // The last separator is decimal; earlier separators must form groups.
      if (text.lastIndexOf(',') > text.lastIndexOf('.')) {
        if (!RegExp(r'^\d{1,3}(?:\.\d{3})+,\d{1,2}$').hasMatch(text))
          return null;
        normalized = text.replaceAll('.', '').replaceAll(',', '.');
      } else {
        if (!RegExp(r'^\d{1,3}(?:,\d{3})+\.\d{1,2}$').hasMatch(text))
          return null;
        normalized = text.replaceAll(',', '');
      }
    } else if (text.contains(',')) {
      if (RegExp(r'^\d{1,3}(?:,\d{3})+$').hasMatch(text)) {
        normalized = text.replaceAll(',', '');
      } else if (RegExp(r'^\d+,\d{1,2}$').hasMatch(text)) {
        normalized = text.replaceAll(',', '.');
      } else {
        return null;
      }
    } else if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(text)) {
      return null;
    }
    final value = double.tryParse(normalized);
    return value != null && value.isFinite ? value : null;
  }

  double? _rightForAmount(ReceiptOcrRow row, _Amount amount) {
    // Word positions correspond to the normalized joined row (O->0 preserves
    // length). Do not infer coordinates for legacy plain-text callers.
    var offset = 0;
    for (final cell in row.cells) {
      final end = offset + cell.text.length;
      if (amount.end > offset && amount.end <= end) return cell.right;
      offset = end + 1;
    }
    return null;
  }

  String _normalize(String text) =>
      text.trim().replaceAllMapped(RegExp(r'(?<=\d)[Oo](?=\d)'), (_) => '0');
}

class _Amount {
  final double value;
  final int start;
  final int end;
  const _Amount(this.value, this.start, this.end);
}

class _Total {
  final double amount;
  final int score;
  const _Total(this.amount, this.score);
}

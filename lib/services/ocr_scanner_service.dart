import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'app_lock_activity_guard.dart';

class ReceiptItem {
  final String name;
  final double price;

  const ReceiptItem({
    required this.name,
    required this.price,
  });

  Map<String, dynamic> toJson() => {'name': name, 'price': price};

  @override
  String toString() => '$name: $price';
}

class ScannedReceipt {
  final String vendor;
  final double total;
  final String category;
  final List<ReceiptItem> items;
  final String description;
  final String rawText;
  final double confidence;

  const ScannedReceipt({
    required this.vendor,
    required this.total,
    required this.category,
    required this.items,
    required this.description,
    required this.rawText,
    required this.confidence,
  });

  Map<String, dynamic> toJson() => {
        'title': vendor,
        'amount': total,
        'category': category,
        'description': description,
        'items': items.map((e) => e.toJson()).toList(),
        'rawText': rawText,
        'confidence': confidence,
      };
}

/// Deterministic receipt parser shared by both the normal OCR path and the
/// interactive line-selection screen. Keeping a single parser prevents the
/// same receipt from producing different totals depending on the entry path.
class ReceiptOcrParser {
  static final RegExp _amountToken = RegExp(
    r'(?<!\d)(\d{1,3}(?:[ ,]\d{3})+(?:[.,]\d{1,2})?|\d{1,7}(?:[.,]\d{1,2})?)(?!\d)',
  );

  static final RegExp _currency = RegExp(
    r'\b(rs\.?|pkr|rupees?|rupee)\b|/-|/=',
    caseSensitive: false,
  );

  static final RegExp _explicitTotal = RegExp(
    r'\b(grand\s*total|net\s*(?:amount|payable|total)|amount\s*(?:paid|due|payable)|total\s*(?:amount|payable|due)|bill\s*total|invoice\s*total|transaction\s*amount)\b',
    caseSensitive: false,
  );

  static final RegExp _plainTotal = RegExp(
    r'(^|\s)total(?:\s|:|=|$)',
    caseSensitive: false,
  );

  static final RegExp _subtotal = RegExp(
    r'\b(sub\s*total|subtotal)\b',
    caseSensitive: false,
  );

  static final RegExp _nonPurchaseAmount = RegExp(
    r'\b(change|cash\s*tendered|tendered|discount|tax|vat|gst|service\s*charge|balance|opening\s*balance|closing\s*balance)\b',
    caseSensitive: false,
  );

  static final RegExp _metadata = RegExp(
    r'\b(date|time|phone|mobile|tel|contact|invoice\s*(?:no|number)?|receipt\s*(?:no|number)?|ref(?:erence)?|tid|trx|transaction\s*id|terminal|branch|counter|cashier|customer|card\s*(?:no|number)?|visa|mastercard|auth(?:orization)?|cnic)\b',
    caseSensitive: false,
  );

  static final RegExp _noiseOnly = RegExp(
    r'\b(successful|success|failed|completed|approved|securely|powered\s+by|thank\s*you|thanks|welcome|merchant\s*copy|customer\s*copy)\b',
    caseSensitive: false,
  );

  static final RegExp _monthWord = RegExp(
    r'\b(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\b',
    caseSensitive: false,
  );

  static final RegExp _dateLike = RegExp(
    r'\b(?:\d{1,2}[-/.]\d{1,2}(?:[-/.]\d{2,4})?|\d{4}[-/.]\d{1,2}[-/.]\d{1,2}|\d{1,2}:\d{2}(?::\d{2})?)\b',
  );

  static final RegExp _quantityPrefix = RegExp(
    r'^\s*\d+(?:[.,]\d+)?\s*(?:x|@)\s*\d+(?:[.,]\d+)?\s*',
    caseSensitive: false,
  );

  const ReceiptOcrParser();

  /// Groups ML Kit fragments that occupy the same visual row. This is more
  /// reliable than block order for supermarket/POS receipts with columns.
  List<String> reconstructRows(Iterable<TextLine> sourceLines) {
    final lines = sourceLines.toList(growable: false);
    if (lines.isEmpty) return const [];

    final sorted = [...lines]
      ..sort((a, b) {
        final aCenter = (a.boundingBox.top + a.boundingBox.bottom) / 2;
        final bCenter = (b.boundingBox.top + b.boundingBox.bottom) / 2;
        final vertical = aCenter.compareTo(bCenter);
        if (vertical != 0) return vertical;
        return a.boundingBox.left.compareTo(b.boundingBox.left);
      });

    final rows = <_ReceiptSpatialRow>[];
    for (final line in sorted) {
      final center = (line.boundingBox.top + line.boundingBox.bottom) / 2;
      final height = line.boundingBox.height <= 0 ? 1.0 : line.boundingBox.height;

      _ReceiptSpatialRow? best;
      var bestDistance = double.infinity;
      for (final row in rows.reversed.take(3)) {
        final tolerance = (row.averageHeight > height
                    ? row.averageHeight
                    : height) *
                0.55 +
            3;
        final distance = (center - row.averageCenter).abs();
        if (distance <= tolerance && distance < bestDistance) {
          best = row;
          bestDistance = distance;
        }
      }

      if (best == null) {
        rows.add(_ReceiptSpatialRow(line));
      } else {
        best.add(line);
      }
    }

    rows.sort((a, b) => a.averageCenter.compareTo(b.averageCenter));
    return rows.map((row) {
      row.lines.sort(
        (a, b) => a.boundingBox.left.compareTo(b.boundingBox.left),
      );
      return row.lines
          .map((line) => line.text.trim())
          .where((text) => text.isNotEmpty)
          .join(' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }).where((row) => row.isNotEmpty).toList(growable: false);
  }

  bool isLikelyUsefulLine(String rawText) {
    final text = _normalizeOcrDigits(rawText).trim();
    if (text.isEmpty) return false;

    final lower = text.toLowerCase();
    final digits = text.replaceAll(RegExp(r'\D'), '');

    if (_isTotalLine(lower)) return true;
    if (_subtotal.hasMatch(lower) || _nonPurchaseAmount.hasMatch(lower)) {
      return false;
    }
    if (_metadata.hasMatch(lower) &&
        !_currency.hasMatch(lower) &&
        !_explicitTotal.hasMatch(lower)) {
      return false;
    }
    if (_noiseOnly.hasMatch(lower)) return false;
    if (_dateLike.hasMatch(lower) || _monthWord.hasMatch(lower)) {
      if (!_currency.hasMatch(lower) && !_hasPlausibleAmount(text)) {
        return false;
      }
    }
    if (digits.length >= 9 &&
        text.replaceAll(RegExp(r'[\s-]'), '').contains(digits)) {
      return false;
    }
    if (text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').isEmpty) {
      return false;
    }

    return true;
  }

  ScannedReceipt parseRows(Iterable<String> sourceRows) {
    final rows = sourceRows
        .map((row) => _normalizeOcrDigits(row).replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((row) => row.isNotEmpty)
        .toList(growable: false);

    if (rows.isEmpty) {
      return const ScannedReceipt(
        vendor: 'Scanned receipt',
        total: 0,
        category: 'General',
        items: [],
        description: '',
        rawText: '',
        confidence: 0.2,
      );
    }

    final vendor = _inferVendor(rows);
    final totalCandidates = <_ReceiptAmountCandidate>[];
    final items = <ReceiptItem>[];
    String? pendingName;

    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final lower = row.toLowerCase();
      final amounts = _extractAmounts(row);

      if (amounts.isNotEmpty) {
        final rightmost = amounts.last;
        final totalScore = _totalScore(lower);
        if (totalScore > 0) {
          totalCandidates.add(
            _ReceiptAmountCandidate(
              amount: rightmost.value,
              score: totalScore,
              rowIndex: index,
            ),
          );
          pendingName = null;
          continue;
        }

        if (_subtotal.hasMatch(lower) || _nonPurchaseAmount.hasMatch(lower)) {
          pendingName = null;
          continue;
        }

        if (_metadata.hasMatch(lower) &&
            !_currency.hasMatch(lower)) {
          pendingName = null;
          continue;
        }

        final candidateName = _cleanItemName(
          row.substring(0, rightmost.start),
        );

        String? itemName;
        if (_isGoodItemName(candidateName)) {
          itemName = candidateName;
          pendingName = null;
        } else if (pendingName != null && _isGoodItemName(pendingName)) {
          itemName = pendingName;
          pendingName = null;
        }

        if (itemName != null &&
            rightmost.value > 0 &&
            rightmost.value <= 100000000) {
          items.add(ReceiptItem(name: itemName, price: rightmost.value));
        }
        continue;
      }

      if (_isPotentialStandaloneItemName(row, index, rows.length)) {
        pendingName = _cleanItemName(row);
      }
    }

    totalCandidates.sort((a, b) {
      final score = b.score.compareTo(a.score);
      if (score != 0) return score;
      return b.rowIndex.compareTo(a.rowIndex);
    });

    final itemSum = items.fold<double>(0, (sum, item) => sum + item.price);
    final explicitTotal =
        totalCandidates.isEmpty ? null : totalCandidates.first.amount;

    double total;
    var usedExplicitTotal = false;
    if (explicitTotal != null && explicitTotal > 0) {
      total = explicitTotal;
      usedExplicitTotal = true;
    } else if (itemSum > 0) {
      total = itemSum;
    } else {
      total = _singlePlausibleAmount(rows) ?? 0.0;
    }

    final consistency = total > 0 && itemSum > 0
        ? (itemSum - total).abs() / total
        : null;
    var confidence = 0.35;
    if (usedExplicitTotal) confidence += 0.30;
    if (items.isNotEmpty) confidence += 0.18;
    if (vendor != 'Scanned receipt') confidence += 0.05;
    if (consistency != null && consistency <= 0.03) {
      confidence += 0.10;
    } else if (consistency != null && consistency > 0.20) {
      confidence -= 0.08;
    }
    if (!usedExplicitTotal && itemSum > 0) confidence += 0.05;
    confidence = confidence.clamp(0.2, 0.98).toDouble();

    return ScannedReceipt(
      vendor: vendor,
      total: total,
      category: 'General',
      items: List<ReceiptItem>.unmodifiable(items),
      description: items.map((item) => item.name).take(3).join(', '),
      rawText: rows.join('\n'),
      confidence: confidence,
    );
  }

  String _inferVendor(List<String> rows) {
    final limit = rows.length < 6 ? rows.length : 6;
    for (var index = 0; index < limit; index++) {
      final row = rows[index].trim();
      final lower = row.toLowerCase();
      if (!_containsLetters(row) ||
          _metadata.hasMatch(lower) ||
          _noiseOnly.hasMatch(lower) ||
          _isTotalLine(lower) ||
          _subtotal.hasMatch(lower) ||
          _dateLike.hasMatch(lower) ||
          _monthWord.hasMatch(lower)) {
        continue;
      }

      final withoutAmount = row.replaceAll(_amountToken, ' ');
      final cleaned = withoutAmount
          .replaceAll(_currency, ' ')
          .replaceAll(RegExp(r"[^A-Za-z0-9&.\-' ]"), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (cleaned.length >= 2 && cleaned.length <= 60) {
        return cleaned;
      }
    }
    return 'Scanned receipt';
  }

  int _totalScore(String lower) {
    if (_subtotal.hasMatch(lower)) return 0;
    if (RegExp(r'\bgrand\s*total\b', caseSensitive: false).hasMatch(lower)) {
      return 100;
    }
    if (RegExp(
      r'\b(net\s*(?:payable|amount|total)|amount\s*(?:paid|due|payable))\b',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return 95;
    }
    if (RegExp(
      r'\b(total\s*(?:amount|payable|due)|bill\s*total|invoice\s*total)\b',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return 90;
    }
    if (RegExp(
      r'\btransaction\s*amount\b',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return 88;
    }
    if (_plainTotal.hasMatch(lower)) return 80;
    return 0;
  }

  bool _isTotalLine(String lower) =>
      _totalScore(lower) > 0 || _explicitTotal.hasMatch(lower);

  List<_ReceiptParsedAmount> _extractAmounts(String row) {
    final matches = _amountToken.allMatches(row);
    final parsed = <_ReceiptParsedAmount>[];
    for (final match in matches) {
      final raw = match.group(1);
      if (raw == null) continue;
      final value = _parseAmount(raw);
      if (value == null || value <= 0 || value > 100000000) continue;
      parsed.add(
        _ReceiptParsedAmount(
          value: value,
          start: match.start,
          end: match.end,
        ),
      );
    }
    return parsed;
  }

  double? _parseAmount(String raw) {
    var value = raw.replaceAll(' ', '').trim();
    if (value.isEmpty) return null;

    if (value.contains(',') && value.contains('.')) {
      value = value.replaceAll(',', '');
    } else if (value.contains(',')) {
      final comma = value.lastIndexOf(',');
      final decimals = value.length - comma - 1;
      if (decimals == 1 || decimals == 2) {
        value = value.replaceRange(comma, comma + 1, '.');
      } else {
        value = value.replaceAll(',', '');
      }
    }

    final parsed = double.tryParse(value);
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  bool _hasPlausibleAmount(String row) => _extractAmounts(row).isNotEmpty;

  double? _singlePlausibleAmount(List<String> rows) {
    final candidates = <double>[];
    for (final row in rows) {
      final lower = row.toLowerCase();
      if (_metadata.hasMatch(lower) ||
          _dateLike.hasMatch(lower) ||
          _subtotal.hasMatch(lower) ||
          _nonPurchaseAmount.hasMatch(lower)) {
        continue;
      }
      final amounts = _extractAmounts(row);
      if (amounts.length == 1) candidates.add(amounts.single.value);
    }
    return candidates.length == 1 ? candidates.single : null;
  }

  String _cleanItemName(String value) {
    var cleaned = value
        .replaceAll(_currency, ' ')
        .replaceAll(_quantityPrefix, ' ')
        .replaceAll(RegExp(r'\b(?:qty|quantity|rate|price|amount)\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\b\d+(?:[.,]\d+)?\b'), ' ')
        .replaceAll(RegExp(r'\b(?:x|@)\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r"[^A-Za-z0-9&\-' ]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (cleaned.length > 80) cleaned = cleaned.substring(0, 80).trim();
    return cleaned;
  }

  bool _isGoodItemName(String value) {
    final trimmed = value.trim();
    if (trimmed.length < 2 || !_containsLetters(trimmed)) return false;
    final lower = trimmed.toLowerCase();
    if (_metadata.hasMatch(lower) ||
        _noiseOnly.hasMatch(lower) ||
        _isTotalLine(lower) ||
        _subtotal.hasMatch(lower) ||
        _nonPurchaseAmount.hasMatch(lower)) {
      return false;
    }
    return true;
  }

  bool _isPotentialStandaloneItemName(
    String row,
    int index,
    int totalRows,
  ) {
    final cleaned = _cleanItemName(row);
    if (!_isGoodItemName(cleaned)) return false;
    final lower = row.toLowerCase();
    if (_dateLike.hasMatch(lower) || _monthWord.hasMatch(lower)) return false;

    // Header/vendor/address lines near the top are poor pending-item
    // candidates. They can still be used as the vendor.
    if (index < 2 && totalRows > 3) return false;
    return true;
  }

  bool _containsLetters(String value) => RegExp(r'[A-Za-z]').hasMatch(value);

  String _normalizeOcrDigits(String value) {
    if (value.length < 3) return value;
    final chars = value.split('');
    for (var index = 1; index < chars.length - 1; index++) {
      final previousDigit = RegExp(r'\d').hasMatch(chars[index - 1]);
      final nextDigit = RegExp(r'\d').hasMatch(chars[index + 1]);
      if (previousDigit &&
          nextDigit &&
          (chars[index] == 'O' || chars[index] == 'o')) {
        chars[index] = '0';
      }
    }
    return chars.join();
  }
}

class OcrScannerService {
  static final OcrScannerService _instance = OcrScannerService._internal();

  factory OcrScannerService() => _instance;

  OcrScannerService._internal();

  final ImagePicker _picker = ImagePicker();
  final ReceiptOcrParser _parser = const ReceiptOcrParser();

  Future<ScannedReceipt?> recoverLostReceiptDetailed({
    bool enhanceForHandwriting = true,
  }) async {
    try {
      final lost = await _picker.retrieveLostData();
      if (lost.isEmpty || lost.files == null || lost.files!.isEmpty) {
        return null;
      }
      return _readReceiptImage(lost.files!.first);
    } catch (_) {
      return null;
    }
  }

  Future<ScannedReceipt?> scanReceiptDetailed({
    ImageSource source = ImageSource.camera,
    bool enhanceForHandwriting = true,
  }) async {
    final image = await AppLockActivityGuard.protectExternalActivity(
      () => _picker.pickImage(
        source: source,
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 95,
      ),
    );
    if (image == null) return null;
    return _readReceiptImage(image);
  }

  Future<ScannedReceipt> _readReceiptImage(XFile image) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(image.path),
      );
      final lines = result.blocks.expand((block) => block.lines).toList();
      final rows = _parser.reconstructRows(lines);
      return _parser.parseRows(rows);
    } finally {
      await recognizer.close();
    }
  }

  Future<Map<String, dynamic>?> scanReceipt({
    ImageSource source = ImageSource.camera,
    bool enhanceForHandwriting = true,
  }) async {
    final receipt = await scanReceiptDetailed(
      source: source,
      enhanceForHandwriting: enhanceForHandwriting,
    );
    return receipt?.total == 0 ? null : receipt?.toJson();
  }
}

class _ReceiptSpatialRow {
  final List<TextLine> lines = [];
  double _centerSum = 0;
  double _heightSum = 0;

  _ReceiptSpatialRow(TextLine line) {
    add(line);
  }

  double get averageCenter => _centerSum / lines.length;

  double get averageHeight => _heightSum / lines.length;

  void add(TextLine line) {
    lines.add(line);
    _centerSum += (line.boundingBox.top + line.boundingBox.bottom) / 2;
    _heightSum += line.boundingBox.height <= 0 ? 1.0 : line.boundingBox.height;
  }
}

class _ReceiptParsedAmount {
  final double value;
  final int start;
  final int end;

  const _ReceiptParsedAmount({
    required this.value,
    required this.start,
    required this.end,
  });
}

class _ReceiptAmountCandidate {
  final double amount;
  final int score;
  final int rowIndex;

  const _ReceiptAmountCandidate({
    required this.amount,
    required this.score,
    required this.rowIndex,
  });
}

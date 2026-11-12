part of 'receipt_ocr_parser.dart';

class DigitalReceiptDetails {
  final double principal;
  final double? fee;
  final String? recipient;
  final String? purpose;
  const DigitalReceiptDetails({
    required this.principal,
    this.fee,
    this.recipient,
    this.purpose,
  });
  Map<String, dynamic> toJson() => {
    'principal': principal,
    'fee': fee,
    'recipient': recipient,
    'purpose': purpose,
  };
}

final _accountMask = RegExp(r'(?:[*•●]\s*){2,}|\b[xX]{2,}[\s-]*\d{2,}');
final _partyLabel = RegExp(
  r'^(?:to|from|recipient|sender|beneficiary)(?:\s|:|$)',
  caseSensitive: false,
);
final _feeLabel = RegExp(
  r'^(?:fees?|service\s*charges?|transaction\s*charges?|charges?)\b',
  caseSensitive: false,
);
final _digitalHeading = RegExp(
  r'\b(?:transaction|payment|transfer)\s+(?:successful|completed)\b|\btransferred\s+to\s+other\s+wallet\b',
  caseSensitive: false,
);
final _amountLabel = RegExp(
  r'^(?:transaction\s*amount|transfer\s*amount|amount\s*sent|sent\s*amount|amount)\b',
  caseSensitive: false,
);

extension DigitalReceiptParsing on ReceiptOcrParser {
  /// Selection changes financial fields; unselected party/purpose text remains
  /// context only. Never reinsert the original amount after it was deselected.
  ScannedReceipt parseSelection({
    required Iterable<ReceiptOcrRow> allRows,
    required Iterable<ReceiptOcrRow> selectedRows,
  }) {
    final context = parseSpatialRows(allRows);
    final selected = selectedRows.toList();
    return context.payment == null
        ? parseSpatialRows(selected)
        : _parseDigitalReceipt(selected, context: context)!;
  }

  bool isDigitalSelectionLine(String text, ScannedReceipt receipt) {
    if (_accountMask.hasMatch(text) || _blockedPaymentId(text)) return false;
    final normalized = _moneyText(text);
    if (_digitalHeading.hasMatch(normalized) ||
        _feeLabel.hasMatch(normalized) ||
        _partyLabel.hasMatch(normalized) ||
        _amountLabel.hasMatch(normalized) ||
        _totalScore(normalized) > 0 ||
        _currencyAmount(normalized) != null)
      return true;
    // ML Kit may split large whole digits and superscript decimal text boxes.
    if (RegExp(r'^[.,]\s*\d{2}$').hasMatch(normalized)) return true;
    if (ReceiptOcrParser._currency.hasMatch(normalized) &&
        _amounts(normalized).isEmpty)
      return true;
    final numbers = _amounts(normalized);
    if (!_letters(normalized) &&
        numbers.length == 1 &&
        [receipt.payment?.principal, receipt.payment?.fee]
            .whereType<double>()
            .any((value) => (value - numbers.single.value).abs() < 0.001))
      return true;
    return [
      receipt.payment?.recipient,
      receipt.payment?.purpose,
    ].whereType<String>().any(
      (value) =>
          normalized.isNotEmpty &&
          value.toLowerCase().contains(normalized.toLowerCase()),
    );
  }

  ScannedReceipt? _parseDigitalReceipt(
    List<ReceiptOcrRow> rows, {
    ScannedReceipt? context,
  }) {
    final texts = rows.map((row) => _moneyText(row.text)).toList();
    final hasTable = texts.any(
      (text) =>
          ReceiptOcrParser._header.hasMatch(text) &&
          RegExp(
            r'\b(?:qty|quantity|rate)\b',
            caseSensitive: false,
          ).hasMatch(text),
    );
    final hasBrand = texts.any(
      (text) => RegExp(
        r'\b(?:jazz\s*cash|easypaisa)\b',
        caseSensitive: false,
      ).hasMatch(text),
    );
    if (context == null &&
        (hasTable ||
            !(texts.any(_digitalHeading.hasMatch) ||
                hasBrand && texts.any(_partyLabel.hasMatch))))
      return null;
    final candidates = <_DigitalAmount>[];
    final fees = <double>[];
    final issues = <String>{};
    var inParty = false;
    for (var i = 0; i < texts.length; i++) {
      final text = texts[i];
      if (_partyLabel.hasMatch(text)) inParty = true;
      if (_accountMask.hasMatch(text) ||
          _blockedPaymentId(text) ||
          _partyLabel.hasMatch(text))
        continue;
      final amounts = _amounts(text);
      if (amounts.isEmpty) continue;
      final feeRow =
          _feeLabel.hasMatch(text) ||
          i > 0 &&
              _feeLabel.hasMatch(texts[i - 1]) &&
              _amounts(texts[i - 1]).isEmpty &&
              _adjacent(rows[i - 1], rows[i]);
      if (feeRow) {
        if (amounts.last.value <= ReceiptOcrParser.maxAmount)
          fees.add(amounts.last.value);
        continue;
      }
      var score = _totalScore(text);
      var net = score > 0 && !_amountLabel.hasMatch(text);
      if (score == 0 && _amountLabel.hasMatch(text)) score = 90;
      if (score == 0 &&
          i > 0 &&
          _amounts(texts[i - 1]).isEmpty &&
          (_amountLabel.hasMatch(texts[i - 1]) ||
              _totalScore(texts[i - 1]) > 0) &&
          _adjacent(rows[i - 1], rows[i])) {
        score = 90;
        net =
            _totalScore(texts[i - 1]) > 0 &&
            !_amountLabel.hasMatch(texts[i - 1]);
      }
      if (score == 0 && !inParty && _currencyAmount(text) != null) score = 60;
      if (score == 0) continue;
      final positive = amounts.where((amount) => amount.value > 0).toList();
      if (positive.isEmpty) continue;
      final value = positive.first.value;
      if (value > ReceiptOcrParser.maxAmount) {
        issues.add('receipt_amount_uncertain');
        continue;
      }
      if (amounts.length > 1) issues.add('receipt_amount_uncertain');
      candidates.add(_DigitalAmount(value, score, net));
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final best = candidates.isEmpty ? null : candidates.first;
    if (best == null) issues.add('receipt_amount_uncertain');
    if (best != null &&
        candidates.any(
          (amount) =>
              amount.score == best.score && !_close(amount.value, best.value),
        ))
      issues.add('receipt_conflicting_totals');
    if (fees.toSet().length > 1) issues.add('receipt_amount_uncertain');
    final fee = fees.isEmpty
        ? (context?.payment?.fee == 0 ? 0.0 : null)
        : fees.first;
    final principalRows = candidates.where((amount) => !amount.net).toList();
    final principal = principalRows.isEmpty
        ? best?.value ?? 0.0
        : principalRows.first.value;
    final total = best?.net == true
        ? best!.value
        : best == null
        ? 0.0
        : principal + (fee ?? 0);
    if (total > ReceiptOcrParser.maxAmount)
      issues.add('receipt_amount_uncertain');
    final recipient = _recipient(texts) ?? context?.payment?.recipient;
    final purpose = _purpose(texts) ?? context?.payment?.purpose;
    final standaloneBrand = texts.where(
      (text) => RegExp(
        r'^(?:jazz\s*cash|easypaisa)$',
        caseSensitive: false,
      ).hasMatch(text),
    );
    final vendor = standaloneBrand.isNotEmpty
        ? standaloneBrand.first
        : hasBrand
        ? (texts.any(
                (text) =>
                    RegExp(r'jazz\s*cash', caseSensitive: false).hasMatch(text),
              )
              ? 'JazzCash'
              : 'Easypaisa')
        : context?.vendor ?? 'Digital payment';
    return ScannedReceipt(
      vendor: vendor,
      total: total <= ReceiptOcrParser.maxAmount ? total : 0,
      category: purpose == null
          ? context?.category ?? 'General'
          : ReceiptOcrParser.categoryFor(purpose),
      items: const [],
      description: [recipient, purpose].whereType<String>().join(' · '),
      rawText: rows.map((row) => row.text).join('\n'),
      confidence: issues.isEmpty ? 0.95 : 0.55,
      issues: List.unmodifiable(issues),
      hasPrintedTotal: best != null,
      payment: DigitalReceiptDetails(
        principal: principal,
        fee: fee,
        recipient: recipient,
        purpose: purpose,
      ),
    );
  }

  bool _blockedPaymentId(String text) =>
      ReceiptOcrParser._metadata.hasMatch(text) &&
          !_amountLabel.hasMatch(text) &&
          _totalScore(text) == 0 ||
      ReceiptOcrParser._date.hasMatch(text) ||
      ReceiptOcrParser._namedDate.hasMatch(text) ||
      RegExp(r'^\+?\d[\d\s-]{8,}$').hasMatch(text);

  String _moneyText(String text) => _normalize(text)
      .replaceAllMapped(
        RegExp(r'(?<=\d)\s*\.\s*(?=\d{1,2}(?:\D|$))'),
        (_) => '.',
      )
      .replaceAllMapped(RegExp(r'(?<=\d),\s+(?=\d{3}\b)'), (_) => ',');

  double? _currencyAmount(String raw) {
    final text = _moneyText(raw);
    if (!ReceiptOcrParser._currency.hasMatch(text) ||
        _accountMask.hasMatch(text))
      return null;
    final amounts = _amounts(text);
    if (amounts.length != 1) return null;
    final remainder = text
        .replaceAll(ReceiptOcrParser._currency, '')
        .replaceAll(ReceiptOcrParser._number, '');
    return RegExp(r'[A-Za-z0-9]').hasMatch(remainder)
        ? null
        : amounts.single.value;
  }

  String? _recipient(List<String> texts) {
    final label = RegExp(
      r'^(?:to|recipient|beneficiary)(?:\s*:\s*|\s+|$)',
      caseSensitive: false,
    );
    for (var i = 0; i < texts.length; i++) {
      final match = label.firstMatch(texts[i]);
      if (match == null) continue;
      final inline = texts[i]
          .substring(match.end)
          .replaceFirst(RegExp(r'\s*(?:[*•●xX]\s*){2,}.*$'), '')
          .trim();
      if (_safeName(inline)) return inline;
      if (i + 1 < texts.length && _safeName(texts[i + 1])) return texts[i + 1];
    }
    return null;
  }

  bool _safeName(String text) =>
      _letters(text) &&
      text.length <= 100 &&
      !RegExp(r'\d').hasMatch(text) &&
      !_accountMask.hasMatch(text) &&
      !_partyLabel.hasMatch(text) &&
      !_feeLabel.hasMatch(text) &&
      !_digitalHeading.hasMatch(text) &&
      !ReceiptOcrParser._metadata.hasMatch(text) &&
      !ReceiptOcrParser._currency.hasMatch(text);
  String? _purpose(List<String> texts) {
    final label = RegExp(
      r'^purpose(?:\s+of\s+(?:payment|transaction))?\s*:?\s*',
      caseSensitive: false,
    );
    for (var i = 0; i < texts.length; i++) {
      if (label.hasMatch(texts[i])) {
        final value = texts[i].replaceFirst(label, '');
        if (_safeName(value)) return value;
        if (i + 1 < texts.length && _safeName(texts[i + 1]))
          return texts[i + 1];
      }
      if (RegExp(
            r'^(?:food\s+and\s+groceries|groceries|food)\b',
            caseSensitive: false,
          ).hasMatch(texts[i]) &&
          _safeName(texts[i]))
        return texts[i];
    }
    return null;
  }
}

class _DigitalAmount {
  final double value;
  final int score;
  final bool net;
  const _DigitalAmount(this.value, this.score, this.net);
}

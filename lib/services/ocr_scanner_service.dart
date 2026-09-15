// OcrScannerService
//
// Add these to pubspec.yaml (google_mlkit_text_recognition and image_picker
// were already required; `image` and `path_provider` are new):
//
//   dependencies:
//     google_mlkit_text_recognition: ^0.13.0
//     image_picker: ^1.0.0
//     image: ^4.1.7
//     path_provider: ^2.1.0
//
// IMPORTANT CAVEAT: google_mlkit_text_recognition's on-device "Latin" model
// is a printed-text recognizer. It is NOT a dedicated handwriting model
// (ML Kit's real handwriting model, Digital Ink Recognition, only works on
// live pen/finger strokes, not photos of paper). The changes below squeeze
// meaningfully better results out of it for handwritten receipts, but they
// cannot fully close that gap. If accuracy is still not good enough for
// your use case, the next step up is usually Google Cloud Vision API's
// DOCUMENT_TEXT_DETECTION endpoint, which has noticeably better handwriting
// support than any on-device model — at the cost of needing network access
// and a backend call. This file always returns the raw recognized text
// (`rawText`) alongside the parsed guess specifically so your UI can let
// the user glance at / correct the parse, which is the standard pattern
// for handwriting OCR products.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// A single line item detected on the receipt.
class ReceiptItem {
  final String name;
  final double price;

  const ReceiptItem({required this.name, required this.price});

  Map<String, dynamic> toJson() => {'name': name, 'price': price};

  @override
  String toString() => '$name: $price';
}

/// Structured result of scanning a receipt (handwritten or printed).
class ScannedReceipt {
  final String vendor;
  final double total;
  final String category;
  final List<ReceiptItem> items;
  final String description;

  /// Full raw OCR text, unedited. Always keep this available in the UI so
  /// the user can verify/correct a handwriting misread — no on-device OCR
  /// is reliable enough on handwriting to skip this.
  final String rawText;

  /// Rough 0.0–1.0 heuristic for how much to trust the parse (not a true
  /// ML confidence score — ML Kit doesn't expose per-word confidence
  /// consistently across platforms). Use it to decide whether to prompt
  /// the user to double check the fields before saving.
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

  /// Keeps the original map shape ('title', 'amount', 'category',
  /// 'description') so existing call sites don't break, and adds the new
  /// itemized/raw/confidence fields on top.
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

class OcrScannerService {
  // Singleton pattern
  static final OcrScannerService _instance = OcrScannerService._internal();
  factory OcrScannerService() => _instance;
  OcrScannerService._internal();

  final ImagePicker _picker = ImagePicker();

  static const _totalKeywords = [
    'total', 'amount', 'sum', 'net', 'due', 'balance', 'grand',
    'bill', 'hisab', 'hisaab', 'kul', 'jama', 'payable', 'paid',
  ];

  static const _ignoreWords = [
    'cash', 'change', 'tax', 'gst', 'date', 'time', 'qty', 'no',
  ];

  /// Launches the camera (or gallery), processes the image, and returns
  /// structured expense data as a Map — same top-level keys as before,
  /// plus 'items', 'rawText' and 'confidence'.
  ///
  /// Set [enhanceForHandwriting] to false to skip the contrast/preprocess
  /// step and feed ML Kit the original photo directly (useful for A/B
  /// testing which gives better results on your sample receipts).
  Future<Map<String, dynamic>?> scanReceipt({
    ImageSource source = ImageSource.camera,
    bool enhanceForHandwriting = true,
  }) async {
    final receipt = await scanReceiptDetailed(
      source: source,
      enhanceForHandwriting: enhanceForHandwriting,
    );
    return receipt?.toJson();
  }

  /// Same as [scanReceipt] but returns the typed [ScannedReceipt] object
  /// (itemized list, raw text, confidence) instead of a raw Map.
  Future<ScannedReceipt?> scanReceiptDetailed({
    ImageSource source = ImageSource.camera,
    bool enhanceForHandwriting = true,
  }) async {
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 100,
      );
      if (image == null) return null;

      String pathToProcess = image.path;
      if (enhanceForHandwriting) {
        final enhancedPath = await _preprocessForHandwriting(image.path);
        if (enhancedPath != null) pathToProcess = enhancedPath;
      }

      RecognizedText recognizedText = await textRecognizer.processImage(
        InputImage.fromFilePath(pathToProcess),
      );

      // Safety net: if the enhanced version somehow produced almost no
      // text (over-aggressive contrast can occasionally wash out faint
      // pencil strokes), fall back to the original photo.
      if (enhanceForHandwriting &&
          pathToProcess != image.path &&
          recognizedText.text.trim().length < 6) {
        recognizedText = await textRecognizer.processImage(
          InputImage.fromFilePath(image.path),
        );
      }

      return _parseReceiptData(recognizedText);
    } catch (e) {
      debugPrint('OCR Error: $e');
      return null;
    } finally {
      textRecognizer.close();
    }
  }

  /// Grayscale + contrast stretch + normalization.
  ///
  /// Handwriting (pencil or faint pen on lined paper, faded thermal ink)
  /// usually has much lower stroke-to-background contrast than printed
  /// receipt text, and low contrast is the single biggest cause of
  /// missed/garbled words in on-device OCR. Normalizing contrast before
  /// handing the frame to ML Kit is the cheapest lever available without
  /// switching recognizers, and it costs nothing if the photo is already
  /// clean.
  Future<String?> _preprocessForHandwriting(String originalPath) async {
    try {
      final bytes = await File(originalPath).readAsBytes();
      img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      // Downscale very large camera photos — OCR accuracy doesn't benefit
      // past ~1600px on the long edge, and it's a lot faster.
      if (decoded.width > 1600) {
        decoded = img.copyResize(decoded, width: 1600);
      }

      img.Image processed = img.grayscale(decoded);
      processed = img.adjustColor(processed, contrast: 1.4, brightness: 1.05);
      processed = img.normalize(processed, min: 0, max: 255);

      final dir = await getTemporaryDirectory();
      final outPath =
          '${dir.path}/ocr_enhanced_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(outPath).writeAsBytes(img.encodeJpg(processed, quality: 92));
      return outPath;
    } catch (e) {
      // Preprocessing is a best-effort enhancement — never let it block
      // the scan if the image package throws on a weird input.
      debugPrint('Preprocessing skipped: $e');
      return null;
    }
  }

  ScannedReceipt _parseReceiptData(RecognizedText recognizedText) {
    final rawText = recognizedText.text;

    // Flatten to lines with position info. ML Kit doesn't always return
    // handwritten lines in top-to-bottom reading order the way it does
    // for print, so we re-sort by bounding box.
    final allLines = <TextLine>[];
    for (final block in recognizedText.blocks) {
      allLines.addAll(block.lines);
    }
    allLines.sort((a, b) {
      final topDiff = a.boundingBox.top - b.boundingBox.top;
      if (topDiff.abs() > 12) return topDiff > 0 ? 1 : -1;
      final leftDiff = a.boundingBox.left - b.boundingBox.left;
      return leftDiff > 0 ? 1 : (leftDiff < 0 ? -1 : 0);
    });

    // --- STEP 1: VENDOR NAME ---
    String vendorName = '';
    for (final line in allLines) {
      final text = line.text.trim();
      final upper = text.toUpperCase();
      if (text.length > 3 &&
          RegExp(r'[A-Za-z]').hasMatch(text) &&
          !_fuzzyContainsAny(upper, ['RECEIPT', 'INVOICE', 'BILL', 'SLIP'])) {
        vendorName = _titleCase(text);
        break;
      }
    }
    if (vendorName.isEmpty) vendorName = 'Handwritten Bill';

    // --- STEP 2: ITEMS + PRICES ---
    // Matches digit runs AND letters that handwriting/low-res OCR commonly
    // confuses with digits (O/0, I,l/1, S/5, B/8, Z/2). A match is only
    // ever accepted as a number if it also contains a genuine digit
    // (checked below), so plain words like "So" or "Oil" are never
    // mistaken for prices.
    final numberCandidateRegex =
    RegExp(r'[0-9OoIiLlSsBbZz]+(?:[.,][0-9OoIiLlSsBbZz]+)?');
    final currencyMarkers =
    RegExp(r'(rs\.?|pkr|inr|rupees|rupya|/-|/=)', caseSensitive: false);

    final items = <ReceiptItem>[];
    final allPrices = <double>[];
    double totalAmount = 0.0;
    int linesWithPrice = 0;
    int totalLineHits = 0;

    for (final line in allLines) {
      final raw = line.text;
      final lower = raw.toLowerCase();
      final cleanedLine = raw.replaceAll(currencyMarkers, ' ');

      final lineNumbers = <double>[];
      final acceptedMatches = <String>[];

      for (final match in numberCandidateRegex.allMatches(cleanedLine)) {
        final candidate = match.group(0)!;
        // Require a real digit so pure-letter words never get treated as
        // numbers, even though the character class above includes letters.
        if (!RegExp(r'\d').hasMatch(candidate)) continue;

        final corrected = _correctDigitConfusion(candidate);
        final normalized = _normalizeNumberToken(corrected);
        final parsed = double.tryParse(normalized);

        if (parsed != null &&
            parsed > 0 &&
            parsed < 1000000 &&
            !_looksLikeYear(parsed)) {
          lineNumbers.add(parsed);
          acceptedMatches.add(candidate);
        }
      }

      if (lineNumbers.isEmpty) continue;
      linesWithPrice++;

      final linePrice = lineNumbers.reduce((a, b) => a > b ? a : b);
      allPrices.add(linePrice);

      final isTotalLine =
      _fuzzyContainsAny(lower, _totalKeywords, maxDistance: 1);
      final isIgnoreLine =
          _fuzzyContainsAny(lower, _ignoreWords, maxDistance: 1) &&
              !isTotalLine;

      if (isTotalLine) {
        totalLineHits++;
        if (linePrice > totalAmount) totalAmount = linePrice;
        continue;
      }
      if (isIgnoreLine) continue;

      // Build the item name by removing only the substrings we actually
      // accepted as numbers — never a blanket regex strip — so real words
      // that happen to contain confusable letters (e.g. "Oil", "Soap")
      // survive intact.
      String itemName = cleanedLine;
      for (final matched in acceptedMatches) {
        itemName = itemName.replaceFirst(matched, ' ');
      }
      itemName = itemName.replaceAll(RegExp(r'[^\w\s]'), ' ');
      itemName = itemName.replaceAll(RegExp(r'\s+'), ' ').trim();

      if (itemName.length > 1 && RegExp(r'[A-Za-z]').hasMatch(itemName)) {
        items.add(ReceiptItem(name: _titleCase(itemName), price: linePrice));
      } else {
        // No legible name recovered — keep the price so nothing silently
        // disappears from the total, just label it generically.
        items.add(ReceiptItem(name: 'Item', price: linePrice));
      }
    }

    // --- STEP 3: TOTAL FALLBACKS ---
    // Handwritten slips rarely say "Total" — the highest number on the
    // page is usually the grand total.
    if (allPrices.isNotEmpty) {
      final maxFound = allPrices.reduce((a, b) => a > b ? a : b);
      if (maxFound > totalAmount) totalAmount = maxFound;
    }

    // If no line was tagged as a total, but the items roughly sum to the
    // current best guess, trust the sum instead — this catches the case
    // where the "biggest number" is actually just the priciest item, not
    // a written total.
    if (totalLineHits == 0 && items.length > 1 && totalAmount > 0) {
      final sum = items.fold<double>(0, (s, i) => s + i.price);
      if ((sum - totalAmount).abs() / totalAmount < 0.15) {
        totalAmount = sum;
      }
    }

    final descriptionText = items.isEmpty
        ? 'Quick Scan'
        : (items.take(3).map((e) => e.name).join(', ') +
        (items.length > 3 ? '...' : ''));

    // --- STEP 4: CONFIDENCE HEURISTIC ---
    // Structural, not a true ML confidence score — capped below 0.95
    // because handwriting parses should never be presented as certain.
    double confidence = 0.35;
    if (linesWithPrice > 0) confidence += 0.2;
    if (totalLineHits > 0) confidence += 0.25;
    if (items.isNotEmpty) confidence += 0.15;
    confidence = confidence.clamp(0.1, 0.95);

    return ScannedReceipt(
      vendor: vendorName,
      total: totalAmount,
      category: 'General',
      items: items,
      description: descriptionText,
      rawText: rawText,
      confidence: confidence,
    );
  }

  // --- Helpers ---

  /// True if [haystack] contains any of [needles], optionally allowing up
  /// to [maxDistance] character edits per word — catches OCR misspellings
  /// of keywords like "total" reading as "t0tal" or "toial".
  bool _fuzzyContainsAny(
      String haystack,
      List<String> needles, {
        int maxDistance = 0,
      }) {
    for (final needle in needles) {
      if (haystack.contains(needle)) return true;
      if (maxDistance > 0) {
        for (final token in haystack.split(RegExp(r'\s+'))) {
          if (token.length < 3) continue;
          if (_levenshtein(token, needle) <= maxDistance) return true;
        }
      }
    }
    return false;
  }

  int _levenshtein(String a, String b) {
    final la = a.length, lb = b.length;
    final dp = List.generate(la + 1, (_) => List<int>.filled(lb + 1, 0));
    for (var i = 0; i <= la; i++) dp[i][0] = i;
    for (var j = 0; j <= lb; j++) dp[0][j] = j;
    for (var i = 1; i <= la; i++) {
      for (var j = 1; j <= lb; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        dp[i][j] = [
          dp[i - 1][j] + 1,
          dp[i][j - 1] + 1,
          dp[i - 1][j - 1] + cost,
        ].reduce(math.min);
      }
    }
    return dp[la][lb];
  }

  /// Corrects common digit/letter confusions inside a token that has
  /// already been confirmed to contain at least one genuine digit.
  String _correctDigitConfusion(String token) {
    return token
        .replaceAll(RegExp('[oO]'), '0')
        .replaceAll(RegExp('[lLiI]'), '1')
        .replaceAll(RegExp('[sS]'), '5')
        .replaceAll(RegExp('[bB]'), '8')
        .replaceAll(RegExp('[zZ]'), '2');
  }

  /// Decides whether a comma is a thousands separator (1,200) or a decimal
  /// point (45,50) and normalizes to a parseable dotted-decimal string.
  String _normalizeNumberToken(String token) {
    final hasComma = token.contains(',');
    final hasDot = token.contains('.');

    if (hasComma && hasDot) {
      // e.g. "1,200.50" -> comma is thousands, dot is decimal.
      return token.replaceAll(',', '');
    }
    if (hasComma && !hasDot) {
      final parts = token.split(',');
      final looksLikeThousands =
          parts.length > 1 && parts.sublist(1).every((p) => p.length == 3);
      return looksLikeThousands ? parts.join('') : token.replaceAll(',', '.');
    }
    return token;
  }

  bool _looksLikeYear(double value) {
    return value >= 1990 && value <= 2035 && value == value.roundToDouble();
  }

  String _titleCase(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').where((w) => w.isNotEmpty).map((word) {
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }
}
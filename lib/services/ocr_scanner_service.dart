import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class ReceiptItem {
  final String name;
  final double price;
  const ReceiptItem({required this.name, required this.price});
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

class OcrScannerService {
  // Singleton pattern
  static final OcrScannerService _instance = OcrScannerService._internal();
  factory OcrScannerService() => _instance;
  OcrScannerService._internal();

  final ImagePicker _picker = ImagePicker();

  Future<ScannedReceipt?> recoverLostReceiptDetailed({
    bool enhanceForHandwriting = true,
  }) async {
    try {
      final lost = await _picker.retrieveLostData();
      if (lost.isEmpty || lost.files == null || lost.files!.isEmpty)
        return null;
      return _readReceiptImage(lost.files!.first);
    } catch (_) {
      return null;
    }
  }

  Future<ScannedReceipt?> scanReceiptDetailed({
    ImageSource source = ImageSource.camera,
    bool enhanceForHandwriting = true,
  }) async {
    final image = await _picker.pickImage(
      source: source,
      maxWidth: 1800,
      maxHeight: 1800,
      imageQuality: 85,
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
      final lines = result.blocks
          .expand((block) => block.lines)
          .map((line) => line.text)
          .toList();
      final amountPattern = RegExp(
        r'(?<!\d)(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)(?!\d)',
      );
      double? printedTotal;
      final amounts = <double>[];
      for (final line in lines) {
        final matches = amountPattern.allMatches(line).toList();
        if (matches.isEmpty) continue;
        final amount = double.tryParse(
          matches.last.group(1)!.replaceAll(',', ''),
        );
        if (amount == null ||
            !amount.isFinite ||
            amount <= 0 ||
            amount > 100000000)
          continue;
        if (RegExp(
          r'\b(total|amount\s+paid|net\s+payable|transaction\s+amount)\b',
          caseSensitive: false,
        ).hasMatch(line)) {
          printedTotal = amount;
        } else if (!RegExp(
          r'\b(date|time|phone|mobile|ref|tid|invoice)\b',
          caseSensitive: false,
        ).hasMatch(line)) {
          amounts.add(amount);
        }
      }
      final amount =
          printedTotal ?? (amounts.length == 1 ? amounts.single : 0.0);
      return ScannedReceipt(
        vendor: 'Scanned receipt',
        total: amount,
        category: 'General',
        items: const [],
        description: '',
        rawText: lines.join('\n'),
        confidence: printedTotal != null ? 0.85 : 0.45,
      );
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

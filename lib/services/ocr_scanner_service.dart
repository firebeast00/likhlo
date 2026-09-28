import 'package:image_picker/image_picker.dart';

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

  // Satisfies the compiler for old background recovery calls
  Future<ScannedReceipt?> recoverLostReceiptDetailed({bool enhanceForHandwriting = true}) async {
    try {
      // Safely clear the cache if the app was killed while the camera was open
      await _picker.retrieveLostData();
    } catch (_) {}
    return null;
  }

  // Fallback stubs in case any screens still use the old automatic scanner
  Future<ScannedReceipt?> scanReceiptDetailed({dynamic source, bool enhanceForHandwriting = true}) async {
    return null;
  }

  Future<Map<String, dynamic>?> scanReceipt({dynamic source, bool enhanceForHandwriting = true}) async {
    return null;
  }
}
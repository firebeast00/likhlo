import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

class OcrScannerService {
  // Singleton Pattern
  static final OcrScannerService _instance = OcrScannerService._internal();
  factory OcrScannerService() => _instance;
  OcrScannerService._internal();

  final ImagePicker _picker = ImagePicker();

  /// Launches the camera, processes the image, and returns structured expense data.
  Future<Map<String, dynamic>?> scanReceipt() async {
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.camera);
      if (image == null) return null;

      final inputImage = InputImage.fromFilePath(image.path);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);

      return _parseReceiptData(recognizedText);

    } catch (e) {
      print("OCR Error: $e");
      return null;
    } finally {
      textRecognizer.close();
    }
  }

  Map<String, dynamic> _parseReceiptData(RecognizedText recognizedText) {
    String vendorName = "";
    double totalAmount = 0.0;

    List<double> allPrices = [];
    List<String> detectedItems = [];

    // --- STEP 1: EXTRACT VENDOR NAME ---
    // Handwritten receipts often have dates or phone numbers at the top.
    // We look for the first line that contains actual words to assume as the vendor.
    if (recognizedText.blocks.isNotEmpty) {
      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          String text = line.text.trim().toUpperCase();
          // Check if it has letters and isn't just a generic header or a string of numbers
          if (text.isNotEmpty &&
              text.length > 3 &&
              !text.contains('RECEIPT') &&
              !text.contains('INVOICE') &&
              !text.contains('BILL') &&
              RegExp(r'[A-Z]').hasMatch(text)) {
            vendorName = text;
            break;
          }
        }
        if (vendorName.isNotEmpty) break;
      }
    }
    if (vendorName.isEmpty) vendorName = "Handwritten Bill";

    // --- STEP 2: PARSE LINES FOR ITEMS AND PRICES ---
    // ✅ Loosened Regex: Captures numbers even if connected to text (Rs500) or symbols (500/-)
    final priceRegex = RegExp(r'\d+(?:[.,]\d{1,2})?');

    // Added local handwritten terms
    final totalKeywords = ['total', 'amount', 'sum', 'net', 'due', 'balance', 'grand', 'bill', 'hisab', 'kul', 'jama'];
    final ignoreWords = ['cash', 'change', 'tax', 'gst', 'date', 'time'];

    for (TextBlock block in recognizedText.blocks) {
      for (TextLine line in block.lines) {
        String rawText = line.text;
        String lowerText = rawText.toLowerCase();

        // Find all number groupings in this line
        final matches = priceRegex.allMatches(lowerText);
        List<double> lineNumbers = [];

        for (final match in matches) {
          String numStr = match.group(0)!.replaceAll(',', '.');
          double? parsed = double.tryParse(numStr);

          // ✅ Filters:
          // 1. Must be > 0
          // 2. Ignore years (2024, 2025)
          // 3. Ignore phone numbers (Pakistani/Indian numbers are usually > 1,000,000)
          if (parsed != null && parsed > 0 && parsed < 1000000 &&
              parsed != 2024 && parsed != 2025 && parsed != 2026 && parsed != 2027) {
            lineNumbers.add(parsed);
          }
        }

        if (lineNumbers.isNotEmpty) {
          // The highest valid number on the line is assumed to be the price for that item
          double linePrice = lineNumbers.reduce((a, b) => a > b ? a : b);
          allPrices.add(linePrice);

          bool isTotalLine = totalKeywords.any((kw) => lowerText.contains(kw));
          bool isIgnoreLine = ignoreWords.any((kw) => lowerText.contains(kw)) && !isTotalLine;

          if (isTotalLine) {
            if (linePrice > totalAmount) totalAmount = linePrice;
          } else if (!isIgnoreLine) {

            // ✅ EXTRACT HANDWRITTEN ITEM DESCRIPTION
            // 1. Remove the numbers
            String itemName = rawText.replaceAll(priceRegex, '');
            // 2. Remove common local currency symbols (Rs, rs, /-, /=)
            itemName = itemName.replaceAll(RegExp(r'(rs\.|rs|/-|/=)', caseSensitive: false), '');
            // 3. Remove random punctuation left behind by messy handwriting
            itemName = itemName.replaceAll(RegExp(r'[^\w\s]'), '').trim();
            // 4. Clean up multiple spaces
            itemName = itemName.replaceAll(RegExp(r'\s+'), ' ');

            // Only add if it actually looks like an item name (e.g. "Burger") and not just random letters
            if (itemName.isNotEmpty && itemName.length > 2 && !RegExp(r'^\d+$').hasMatch(itemName)) {
              detectedItems.add(_titleCase(itemName));
            }
          }
        }
      }
    }

    // --- STEP 3: FALLBACKS AND CLEANUP ---
    // Handwritten slips rarely have the word "Total".
    // The highest number on a handwritten slip is almost 100% guaranteed to be the grand total.
    if (allPrices.isNotEmpty) {
      double maxFoundPrice = allPrices.reduce((a, b) => a > b ? a : b);
      if (maxFoundPrice > totalAmount) {
        totalAmount = maxFoundPrice;
      }
    }

    // Create a neat description from the found items
    String descriptionText = "";
    if (detectedItems.isNotEmpty) {
      // Take the first 3 items to avoid massively long descriptions
      descriptionText = detectedItems.take(3).join(', ');
      if (detectedItems.length > 3) {
        descriptionText += '...';
      }
    } else {
      descriptionText = "Quick Scan";
    }

    return {
      'title': vendorName,
      'amount': totalAmount,
      'category': 'General',
      'description': descriptionText,
    };
  }

  // Helper method to format items nicely (e.g., "chicken burger" -> "Chicken Burger")
  String _titleCase(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }
}
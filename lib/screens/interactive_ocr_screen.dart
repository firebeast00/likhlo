import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../services/ocr_scanner_service.dart';

class InteractiveOcrScreen extends StatefulWidget {
  final File imageFile;
  const InteractiveOcrScreen({super.key, required this.imageFile});

  @override
  State<InteractiveOcrScreen> createState() => _InteractiveOcrScreenState();
}

class _InteractiveOcrScreenState extends State<InteractiveOcrScreen> {
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );
  List<TextLine> _lines = [];
  final Set<TextLine> _selectedLines = {};
  bool _isScanning = true;
  String? _scanError;
  Size? _imageSize;

  @override
  void initState() {
    super.initState();
    _scanImage();
  }

  // 🚀 FIXED: Advanced Layout & Contextual Selection Algorithm
  bool _shouldAutoSelect(TextLine line) {
    final text = line.text;
    final lower = text.toLowerCase().trim();
    final numericOnly = text.replaceAll(RegExp(r'[^0-9]'), '');

    // 1. Keep explicit currency amounts (Fixes the .00 omission bug)
    if (RegExp(
      r'\b(rs\.?|pkr|rupees|rupee)\b',
      caseSensitive: false,
    ).hasMatch(lower)) {
      // Intelligently identify and drop only true 0.00 fees, not "150.00"
      final nums = RegExp(r'\d+(?:[.,]\d+)?').allMatches(lower);
      if (nums.isNotEmpty) {
        final val =
            double.tryParse(nums.last.group(0)!.replaceAll(',', '.')) ?? 0.0;
        if (val == 0.0 &&
            (lower.contains('fee') ||
                lower.contains('tax') ||
                lower.contains('change')))
          return false;
      }
      return true;
    }

    // 2. Exclude long unformatted digit strings (TIDs, CNICs, Phone Numbers)
    if (numericOnly.length >= 10 &&
        numericOnly == text.replaceAll(RegExp(r'\s|-'), '')) {
      return false;
    }

    // 3. Exclude Standard POS Timestamps and Dates
    if (RegExp(r'\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\b')
        .hasMatch(lower))
      return false;
    if (RegExp(r'\b\d{1,2}[:/]\d{2}\b').hasMatch(lower)) return false;
    if (lower.startsWith('on ') ||
        lower.startsWith('at ') ||
        lower.startsWith('date:'))
      return false;

    // 4. Safely Exclude Digital POS Noise (Removed "transaction" to save "Transaction Amount")
    final noisePattern = RegExp(
      r'\b(successful|success|failed|status|completed|securely|powered|via|sender|branch|terminal|merchant|tid|trx|ref|thanks|thank you|welcome|invoice|receipt|customer|visa|mastercard|balance)\b',
    );
    if (noisePattern.hasMatch(lower)) return false;

    // 5. Exclude standalone directional structure labels
    if (lower == 'to' || lower == 'from' || lower == 'fee' || lower == 'tax')
      return false;

    // 6. Ensure the row isn't pure punctuation
    if (text.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').isEmpty) return false;

    // Everything remaining is likely an item, vendor, or untagged amount
    return true;
  }

  Future<void> _scanImage() async {
    try {
      final decodedImage = await decodeImageFromList(
        await widget.imageFile.readAsBytes(),
      );
      if (!mounted) return;
      _imageSize = Size(
        decodedImage.width.toDouble(),
        decodedImage.height.toDouble(),
      );

      final inputImage = InputImage.fromFile(widget.imageFile);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      if (!mounted) return;

      final lines = <TextLine>[];
      for (var block in recognizedText.blocks) {
        for (var line in block.lines) {
          lines.add(line);
        }
      }

      setState(() {
        _lines = lines;
        _selectedLines.clear();

        for (final line in lines) {
          if (_shouldAutoSelect(line)) {
            _selectedLines.add(line);
          }
        }

        _isScanning = false;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _isScanning = false;
          _scanError =
              'The receipt could not be read. Please try another image.';
        });
    }
  }

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  // 🚀 CORE STRATEGY: Spatial Y-Axis Clustering for Supermarkets and Hotels
  List<String> _groupLinesIntoRows(List<TextLine> lines) {
    if (lines.isEmpty) return [];

    lines.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    List<List<TextLine>> rows = [];

    for (var line in lines) {
      if (rows.isEmpty) {
        rows.add([line]);
        continue;
      }

      var lastRow = rows.last;
      var referenceLine = lastRow.first;

      double verticalThreshold = line.boundingBox.height * 0.5;

      if ((line.boundingBox.top - referenceLine.boundingBox.top).abs() <
          verticalThreshold) {
        lastRow.add(line);
      } else {
        rows.add([line]);
      }
    }

    List<String> rowStrings = [];
    for (var row in rows) {
      row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      rowStrings.add(row.map((l) => l.text).join(' '));
    }

    return rowStrings;
  }

  ScannedReceipt _buildReceipt() {
    final reconstructedRows = _groupLinesIntoRows(_selectedLines.toList());

    final items = <ReceiptItem>[];
    double grandTotal = 0.0;
    String vendor = 'Scanned Receipt';
    String? pendingName;

    // Extracts prices with complex mall formatting (e.g., 1,020.00)
    final amountRegExp = RegExp(r'\b\d+(?:[,.]\d+)*\b');
    final currencyRegExp = RegExp(
      r'\b(rs\.?|pkr|rupees|rupee|transaction amount)\b|/-|/=',
      caseSensitive: false,
    );

    double? printedTotal;
    for (final text in reconstructedRows) {
      final matches = amountRegExp.allMatches(text);

      if (matches.isNotEmpty) {
        String priceStr = matches.last.group(0)!;

        // Normalize commas for double casting
        if (priceStr.contains(',') && priceStr.contains('.')) {
          priceStr = priceStr.replaceAll(',', '');
        } else if (priceStr.contains(',') &&
            priceStr.length - priceStr.lastIndexOf(',') == 3) {
          priceStr = priceStr.replaceAll(',', '.');
        } else {
          priceStr = priceStr.replaceAll(',', '');
        }

        final price = double.tryParse(priceStr) ?? 0.0;

        String name = text.replaceAll(matches.last.group(0)!, '');
        name = name.replaceAll(currencyRegExp, '');
        name = name.replaceAll(RegExp(r'[^a-zA-Z\s]'), '');
        name = name.replaceAll(RegExp(r'\s+'), ' ').trim();

        if (name.isEmpty && pendingName != null) {
          name = pendingName;
          pendingName = null;
        } else if (name.isEmpty) {
          name = 'Item';
        }
        if (RegExp(
          r'\b(grand\s+total|total|amount\s+paid|net\s+payable|transaction\s+amount)\b',
          caseSensitive: false,
        ).hasMatch(text)) {
          if (price > 0) printedTotal = price;
          continue;
        }
        if (price <= 0) continue;
        items.add(ReceiptItem(name: name, price: price));
        if (price > grandTotal) grandTotal = price;
      } else {
        String cleanPending = text.replaceAll(currencyRegExp, '').trim();
        if (cleanPending.isNotEmpty) {
          pendingName = cleanPending;
          if (vendor == 'Scanned Receipt') vendor = cleanPending;
        }
      }
    }

    final sum = items.fold<double>(0, (s, i) => s + i.price);
    grandTotal = printedTotal ?? sum;

    return ScannedReceipt(
      vendor: vendor,
      total: grandTotal,
      category: 'General',
      items: items,
      description: items.map((e) => e.name).take(3).join(', '),
      rawText: reconstructedRows.join('\n'),
      confidence: 0.95,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_scanError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Receipt scan')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_scanError!, textAlign: TextAlign.center),
          ),
        ),
      );
    }
    if (_isScanning || _imageSize == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.teal)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Edit Selection'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.teal.withOpacity(0.5)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.tealAccent,
                  size: 20,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Smart selection applied! Tap any box to manually add missed items or remove unwanted text.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scaleX = constraints.maxWidth / _imageSize!.width;
                final scaleY = constraints.maxHeight / _imageSize!.height;
                final scale = scaleX < scaleY ? scaleX : scaleY;

                return Center(
                  child: SizedBox(
                    width: _imageSize!.width * scale,
                    height: _imageSize!.height * scale,
                    child: Stack(
                      children: [
                        Image.file(widget.imageFile, fit: BoxFit.contain),
                        ..._lines.map((line) {
                          final isSelected = _selectedLines.contains(line);
                          final rect = line.boundingBox;

                          return Positioned(
                            left: rect.left * scale,
                            top: rect.top * scale,
                            width: rect.width * scale,
                            height: rect.height * scale,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  isSelected
                                      ? _selectedLines.remove(line)
                                      : _selectedLines.add(line);
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.blue.withOpacity(0.4)
                                      : Colors.white.withOpacity(0.15),
                                  border: Border.all(
                                    color: isSelected
                                        ? Colors.blue
                                        : Colors.white60,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _selectedLines.isNotEmpty
          ? FloatingActionButton.extended(
              backgroundColor: Colors.teal,
              onPressed: () {
                final receipt = _buildReceipt();
                Navigator.pop(context, receipt);
              },
              icon: const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
              ),
              label: Text(
                'Continue (${_selectedLines.length})',
                style: const TextStyle(color: Colors.white),
              ),
            )
          : null,
    );
  }
}

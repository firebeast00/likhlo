import '../l10n/app_strings.dart';
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
  final ReceiptOcrParser _receiptParser = const ReceiptOcrParser();
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

  bool _shouldAutoSelect(TextLine line) =>
      _receiptParser.isLikelyUsefulLine(line.text);

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

  ScannedReceipt _buildReceipt() {
    final reconstructedRows =
        _receiptParser.reconstructRows(_selectedLines.toList());
    return _receiptParser.parseRows(reconstructedRows);
  }

  @override
  Widget build(BuildContext context) {
    AppStrings.of(context);
    if (_scanError != null) {
      return Scaffold(
        appBar: AppBar(title: Text(AppStrings.current.text('receipt_scan_706316'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(AppStrings.current.display(_scanError!), textAlign: TextAlign.center),
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
        title: Text(AppStrings.current.text('edit_selection_f1a66e')),
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
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.tealAccent,
                  size: 20,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppStrings.current.text('smart_selection_applied_tap_any_box_to_manually__362bef'),
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
                AppStrings.current.text('continue_d65c29', {'p0': _selectedLines.length}),
                style: const TextStyle(color: Colors.white),
              ),
            )
          : null,
    );
  }
}

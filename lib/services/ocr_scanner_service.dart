import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'app_lock_activity_guard.dart';

export 'receipt_ocr_parser.dart';

import 'receipt_ocr_parser.dart';

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

  Future<ScannedReceipt> readReceiptPath(String path) =>
      _readReceiptImage(XFile(path));

  Future<ScannedReceipt> _readReceiptImage(XFile image) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(image.path),
      );
      final lines = result.blocks.expand((block) => block.lines).toList();
      return _parser.parseSpatialRows(receiptSpatialRows(lines));
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

/// Retain word positions until receipt columns and prices have been resolved.
List<ReceiptOcrRow> receiptSpatialRows(Iterable<TextLine> sourceLines) {
  final sorted = sourceLines.toList()
    ..sort(
      (a, b) => a.boundingBox.center.dy.compareTo(b.boundingBox.center.dy),
    );
  final rows = <_ReceiptSpatialRow>[];
  for (final line in sorted) {
    final center = line.boundingBox.center.dy;
    _ReceiptSpatialRow? best;
    var distance = double.infinity;
    for (final row in rows.reversed.take(3)) {
      final height = line.boundingBox.height > row.averageHeight
          ? line.boundingBox.height
          : row.averageHeight;
      final delta = (center - row.averageCenter).abs();
      if (delta <= height * 0.5 + 2 && delta < distance) {
        best = row;
        distance = delta;
      }
    }
    if (best == null) {
      rows.add(_ReceiptSpatialRow(line));
    } else {
      best.add(line);
    }
  }
  return rows.map((row) {
    final cells = <ReceiptOcrCell>[];
    for (final line in row.lines) {
      if (line.elements.isEmpty) {
        cells.add(
          ReceiptOcrCell(
            line.text,
            left: line.boundingBox.left,
            right: line.boundingBox.right,
          ),
        );
      } else {
        for (final element in line.elements) {
          cells.add(
            ReceiptOcrCell(
              element.text,
              left: element.boundingBox.left,
              right: element.boundingBox.right,
            ),
          );
        }
      }
    }
    cells.sort((a, b) => a.left!.compareTo(b.left!));
    return ReceiptOcrRow(
      cells,
      centerY: row.averageCenter,
      height: row.averageHeight,
    );
  }).toList();
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

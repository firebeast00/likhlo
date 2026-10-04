part of '../../screens/home_screen.dart';

extension _DashboardOcrMethods on _HomeScreenState {
  Future<void> _scanReceiptIntoInput() async {
    if (_isScanningReceipt) return;
    _dismissKeyboard();
    _setScanningReceipt(true);

    try {
      // 🚀 FIXED: Show Bottom Sheet for Camera / Gallery
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Add Receipt', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded),
                title: const Text('Take Photo'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Text(
                  'For best results, keep the full receipt flat, fill the frame, avoid shadows, and make sure prices are sharp.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      final picker = ImagePicker();
      final image = await AppLockActivityGuard.protectExternalActivity(
        () => picker.pickImage(
          source: source,
          imageQuality: 95,
          maxWidth: 2400,
          maxHeight: 2400,
        ),
      );
      if (!mounted || image == null) return;

      // 🚀 FIXED: Navigate to Interactive Screen
      final scannedReceipt = await Navigator.push<ScannedReceipt>(
        context,
        MaterialPageRoute(
          builder: (_) => InteractiveOcrScreen(imageFile: File(image.path)),
        ),
      );

      if (!mounted || scannedReceipt == null) return;

      // 🚀 FIXED: Open the Review Screen for bulk saving if data was found!
      if (scannedReceipt.items.isNotEmpty || scannedReceipt.total > 0) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReceiptReviewScreen(receipt: scannedReceipt),
          ),
        );
      }

    } catch (e) {
      debugPrint("Scanner Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera or scanner error occurred.')),
      );
    } finally {
      if (mounted) _setScanningReceipt(false);
    }
  }

  Future<void> _recoverLostReceiptScan() async {
    if (_isScanningReceipt || !mounted) return;
    _setScanningReceipt(true);
    try {
      final scanner = OcrScannerService();
      final receipt = await scanner.recoverLostReceiptDetailed();
      if (!mounted || receipt == null) return;
      await _reviewScannedReceipt(receipt);
    } finally {
      if (mounted) _setScanningReceipt(false);
    }
  }

  Future<void> _reviewScannedReceipt(ScannedReceipt receipt) async {
    if (receipt.total <= 0 && receipt.items.isEmpty) {
      _showTransactionError(
        'No reliable receipt items or total were detected. Retake the photo with the full receipt visible and good lighting.',
        title: 'Receipt details not found',
      );
      return;
    }

    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReceiptReviewScreen(receipt: receipt),
      ),
    );
    if (confirmed == true && mounted) {
      _showExpenseMessage(
        'The reviewed receipt was added to your records.',
        title: 'Receipt saved',
      );
    }
  }


}

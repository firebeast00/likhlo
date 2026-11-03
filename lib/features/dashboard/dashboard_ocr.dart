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
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  AppStrings.current.text('add_receipt_943857'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded),
                title: Text(AppStrings.current.text('take_photo_e9765b')),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: Text(
                  AppStrings.current.text('choose_from_gallery_5b17ab'),
                ),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Text(
                  AppStrings.current.text(
                    'for_best_results_keep_the_full_receipt_flat_fill_b7a128',
                  ),
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

      final receipt = await OcrScannerService().readReceiptPath(image.path);
      if (!mounted) return;
      await _reviewScannedReceipt(receipt, imageFile: File(image.path));
    } catch (e) {
      debugPrint("Scanner Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.current.text('camera_or_scanner_error_occurred_4a27da'),
          ),
        ),
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

  Future<void> _reviewScannedReceipt(
    ScannedReceipt receipt, {
    File? imageFile,
  }) async {
    if (receipt.total <= 0 && receipt.items.isEmpty && imageFile == null) {
      _showTransactionError(
        AppMessage('no_reliable_receipt_items_or_total_were_detected_f8eee3'),
        title: AppMessage('receipt_details_not_found_d29e07'),
      );
      return;
    }

    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReceiptReviewScreen(
          receipt: receipt,
          onAdjustSelection: imageFile == null
              ? null
              : () => Navigator.of(context).push<ScannedReceipt>(
                  MaterialPageRoute(
                    builder: (_) => InteractiveOcrScreen(imageFile: imageFile),
                  ),
                ),
        ),
      ),
    );
    if (confirmed == true && mounted) {
      _showExpenseMessage(
        AppMessage('the_reviewed_receipt_was_added_to_your_records_047d90'),
        title: AppMessage('receipt_saved_f4656f'),
      );
    }
  }
}

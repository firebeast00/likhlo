import 'dart:async';

import 'package:flutter/material.dart';

import '../../widgets/transaction_message_card.dart';

/// Coordinates transient in-app feedback independently from feature screens.
class FeedbackCoordinator {
  Timer? _timer;
  OverlayEntry? _activeEntry;

  void show(
    BuildContext context, {
    required String title,
    required String message,
    required TransactionMessageTone tone,
    String? actionLabel,
    Future<void> Function()? onAction,
  }) {
    _timer?.cancel();
    _activeEntry?.remove();

    late final OverlayEntry entry;
    void dismiss() {
      if (_activeEntry != entry) return;
      entry.remove();
      _activeEntry = null;
      _timer?.cancel();
      _timer = null;
    }

    entry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        top: MediaQuery.paddingOf(overlayContext).top + 12,
        left: 16,
        right: 16,
        child: Align(
          alignment: Alignment.topCenter,
          child: TransactionMessageCard(
            title: title,
            message: message,
            tone: tone,
            actionLabel: actionLabel,
            onAction: onAction,
            onDismiss: dismiss,
          ),
        ),
      ),
    );

    _activeEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    _timer = Timer(const Duration(seconds: 5), dismiss);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _activeEntry?.remove();
    _activeEntry = null;
  }
}

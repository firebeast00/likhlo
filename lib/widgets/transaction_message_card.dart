import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';

enum TransactionMessageTone {
  error,
  deletion,
  expense,
  income,
  transfer,
  success,
  info,
  warning,
}

class TransactionMessageCard extends StatelessWidget {
  final String title;
  final String message;
  final TransactionMessageTone tone;
  final String? actionLabel;
  final Future<void> Function()? onAction;
  final VoidCallback onDismiss;

  const TransactionMessageCard({
    super.key,
    required this.title,
    required this.message,
    required this.tone,
    required this.actionLabel,
    required this.onAction,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color accent;
    final Color background;
    final Color foreground;
    final IconData icon;

    switch (tone) {
      case TransactionMessageTone.error:
        accent = scheme.error;
        background = scheme.errorContainer;
        foreground = scheme.onErrorContainer;
        icon = Icons.error_outline_rounded;
      case TransactionMessageTone.deletion:
        accent = const Color(0xFFB91C1C);
        background = isDark ? const Color(0xFF3F1117) : const Color(0xFFFEF2F2);
        foreground = isDark ? const Color(0xFFFECACA) : const Color(0xFF7F1D1D);
        icon = Icons.delete_outline_rounded;
      case TransactionMessageTone.expense:
        accent = const Color(0xFFDC2626);
        background = isDark ? const Color(0xFF35161A) : const Color(0xFFFFF1F2);
        foreground = isDark ? const Color(0xFFFDA4AF) : const Color(0xFF881337);
        icon = Icons.north_east_rounded;
      case TransactionMessageTone.income:
        accent = const Color(0xFF16A34A);
        background = isDark ? const Color(0xFF123524) : const Color(0xFFF0FDF4);
        foreground = isDark ? const Color(0xFFDCFCE7) : const Color(0xFF14532D);
        icon = Icons.south_west_rounded;
      case TransactionMessageTone.transfer:
        accent = const Color(0xFF2563EB);
        background = isDark ? const Color(0xFF12264B) : const Color(0xFFEFF6FF);
        foreground = isDark ? const Color(0xFFDBEAFE) : const Color(0xFF1E3A8A);
        icon = Icons.swap_horiz_rounded;
      case TransactionMessageTone.success:
        accent = const Color(0xFF16A34A);
        background = isDark ? const Color(0xFF123524) : const Color(0xFFF0FDF4);
        foreground = isDark ? const Color(0xFFDCFCE7) : const Color(0xFF14532D);
        icon = Icons.check_circle_outline_rounded;
      case TransactionMessageTone.info:
        accent = scheme.primary;
        background = scheme.primaryContainer;
        foreground = scheme.onPrimaryContainer;
        icon = Icons.info_outline_rounded;
      case TransactionMessageTone.warning:
        accent = const Color(0xFFD97706);
        background = isDark ? const Color(0xFF3A260B) : const Color(0xFFFFFBEB);
        foreground = isDark ? const Color(0xFFFDE68A) : const Color(0xFF78350F);
        icon = Icons.warning_amber_rounded;
    }

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, -8 * (1 - value)),
          child: child,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Material(
          color: Colors.transparent,
          child: Semantics(
            container: true,
            liveRegion: true,
            label: '$title. $message',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accent.withValues(alpha: 0.28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: accent, size: 21),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: foreground,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          message,
                          style: TextStyle(
                            color: foreground.withValues(alpha: 0.82),
                            fontSize: 13,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (actionLabel != null && onAction != null) ...[
                          const SizedBox(height: 7),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: accent,
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 30),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () async {
                              onDismiss();
                              await onAction!();
                            },
                            child: Text(
                              actionLabel!,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: AppStrings.current.text('dismiss_message_98f3b0'),
                    onPressed: onDismiss,
                    icon: Icon(
                      Icons.close_rounded,
                      color: foreground.withValues(alpha: 0.65),
                      size: 19,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

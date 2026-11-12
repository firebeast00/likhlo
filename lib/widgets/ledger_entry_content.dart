import 'package:flutter/material.dart';

/// Presentation shared by income, expense and transfer cards. Ledger actions
/// remain in the caller; only text layout is handled here.
class LedgerEntryContent extends StatelessWidget {
  final String title;
  final String dateLabel;
  final String amountLabel;
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final Color amountColor;
  const LedgerEntryContent({
    super.key,
    required this.title,
    required this.dateLabel,
    required this.amountLabel,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.amountColor,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      return Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 11,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        dateLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Very long amounts can shrink to fit; never truncate financial digits.
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.45),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                amountLabel,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: amountColor,
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

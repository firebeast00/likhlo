import 'package:flutter/material.dart';

/// Keeps Udhaar's instant-entry controls visually consistent with Main.
class UdharSmartEntryCard extends StatelessWidget {
  const UdharSmartEntryCard({
    super.key,
    required this.controller,
    required this.walletName,
    required this.color,
    required this.listening,
    required this.scanning,
    required this.saving,
    required this.onChooseWallet,
    required this.onVoice,
    required this.onScan,
    required this.onSave,
  });

  final TextEditingController controller;
  final String walletName;
  final Color color;
  final bool listening;
  final bool scanning;
  final bool saving;
  final VoidCallback onChooseWallet;
  final VoidCallback onVoice;
  final VoidCallback onScan;
  final ValueChanged<String> onSave;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: listening
              ? Colors.red.withValues(alpha: .7)
              : color.withValues(alpha: isDark ? .24 : .12),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: (listening ? Colors.red : color).withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  listening ? Icons.graphic_eq_rounded : Icons.auto_awesome_rounded,
                  color: listening ? Colors.red : color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: InkWell(
                  onTap: listening ? null : onChooseWallet,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(listening ? 'Listening now' : 'Smart Entry',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(
                          listening
                              ? 'Say who, how much and whether you gave or took'
                              : 'Wallet: $walletName · Tap to change',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: listening ? Colors.grey : color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (listening)
                const Icon(Icons.circle, size: 10, color: Colors.red)
              else
                IconButton(
                  tooltip: 'Select Udhaar wallet',
                  onPressed: onChooseWallet,
                  icon: Icon(Icons.tune_rounded, color: color, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 54,
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? .10 : .045),
              borderRadius: BorderRadius.circular(16),
            ),
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.done,
              onSubmitted: onSave,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: listening ? 'Listening…' : 'e.g. Ali ko 500 udhaar diya',
                hintStyle: const TextStyle(fontSize: 12),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.only(left: 15, top: 17, bottom: 17),
                suffixIconConstraints: const BoxConstraints(minHeight: 40),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Scan receipt',
                      constraints: const BoxConstraints.tightFor(width: 38, height: 40),
                      onPressed: scanning ? null : onScan,
                      icon: scanning
                          ? SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: color),
                            )
                          : Icon(Icons.document_scanner_outlined,
                              size: 20, color: color),
                    ),
                    IconButton(
                      tooltip: listening ? 'Stop listening' : 'Voice input',
                      constraints: const BoxConstraints.tightFor(width: 38, height: 40),
                      onPressed: saving ? null : onVoice,
                      icon: Icon(
                        listening ? Icons.stop_circle_rounded : Icons.mic_none_rounded,
                        size: 21,
                        color: listening ? Colors.red : color,
                      ),
                    ),
                    Container(
                      width: 34,
                      height: 34,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      child: IconButton(
                        tooltip: 'Save Udhaar entry',
                        padding: EdgeInsets.zero,
                        onPressed: saving ? null : () => onSave(controller.text),
                        icon: const Icon(Icons.arrow_upward_rounded,
                            size: 19, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

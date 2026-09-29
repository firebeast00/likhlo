part of '../../screens/home_screen.dart';

extension _DashboardSmartInputWidgetMethods on _HomeScreenState {
  Widget _buildSmartInputBar(
      Color primaryColor,
      bool isDark,
      List<Wallet> wallets,
      ) {
    final cardColor = Theme.of(context).cardColor;
    final inputColor = isDark
        ? Colors.white.withValues(alpha: 0.055)
        : primaryColor.withValues(alpha: 0.045);
    final defaultAccountLabel = _smartEntryDefaultAccountLabel(wallets);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _isListening
              ? Colors.red.withValues(alpha: 0.7)
              : primaryColor.withValues(alpha: isDark ? 0.24 : 0.12),
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
                  color: (_isListening ? Colors.red : primaryColor)
                      .withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _isListening
                      ? Icons.graphic_eq_rounded
                      : Icons.auto_awesome_rounded,
                  color: _isListening ? Colors.red : primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: InkWell(
                  onTap: _isListening
                      ? null
                      : _showSmartEntryAccountPicker,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isListening ? 'Listening now' : 'Smart Entry',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isListening
                              ? 'Speak naturally — it saves automatically'
                              : defaultAccountLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _isListening
                                ? Colors.grey.shade500
                                : primaryColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_isListening)
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                )
              else
                IconButton(
                  tooltip: 'Select default Smart Entry wallet',
                  visualDensity: VisualDensity.compact,
                  onPressed: _showSmartEntryAccountPicker,
                  icon: Icon(
                    Icons.tune_rounded,
                    color: primaryColor,
                    size: 20,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 54,
            decoration: BoxDecoration(
              color: inputColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: TextField(
              controller: _smartInputCtrl,
              textInputAction: TextInputAction.done,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              onSubmitted: _processNLP,
              decoration: InputDecoration(
                hintText: _isListening
                    ? 'Listening…'
                    : ref.watch(settingsProvider).smartEntryLanguage == 'romanUrdu'
                        ? 'Misal: 500 biryani par kharch kiya'
                        : 'e.g. 500 biryani from JazzCash',
                hintStyle: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                contentPadding:
                const EdgeInsets.only(left: 15, top: 17, bottom: 17),
                suffixIconConstraints:
                const BoxConstraints(minHeight: 40),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Scan receipt',
                      visualDensity: VisualDensity.compact,
                      constraints:
                      const BoxConstraints.tightFor(width: 38, height: 40),
                      onPressed:
                      _isScanningReceipt ? null : _scanReceiptIntoInput,
                      icon: _isScanningReceipt
                          ? SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: primaryColor,
                        ),
                      )
                          : Icon(
                        Icons.document_scanner_outlined,
                        size: 20,
                        color: primaryColor,
                      ),
                    ),
                    IconButton(
                      tooltip:
                      _isListening ? 'Stop listening' : 'Voice input',
                      visualDensity: VisualDensity.compact,
                      constraints:
                      const BoxConstraints.tightFor(width: 38, height: 40),
                      onPressed: _listenForExpense,
                      icon: Icon(
                        _isListening
                            ? Icons.stop_circle_rounded
                            : Icons.mic_none_rounded,
                        size: 21,
                        color: _isListening ? Colors.red : primaryColor,
                      ),
                    ),
                    Container(
                      width: 34,
                      height: 34,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        tooltip: 'Save Smart Entry',
                        padding: EdgeInsets.zero,
                        onPressed: () =>
                            _processNLP(_smartInputCtrl.text),
                        icon: const Icon(
                          Icons.arrow_upward_rounded,
                          size: 19,
                          color: Colors.white,
                        ),
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

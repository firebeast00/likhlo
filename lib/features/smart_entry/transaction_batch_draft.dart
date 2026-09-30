enum TransactionBatchSource { typed, voice, ocr }

class TransactionDraft {
  final String title;
  final double amount;
  final String category;
  final String? walletId;
  final String type;
  final DateTime date;
  final bool hasExplicitWallet;
  final bool hasExplicitDate;
  final double confidence;
  final String sourceText;

  const TransactionDraft({
    required this.title,
    required this.amount,
    required this.category,
    required this.walletId,
    required this.type,
    required this.date,
    required this.hasExplicitWallet,
    required this.hasExplicitDate,
    required this.confidence,
    required this.sourceText,
  });

  TransactionDraft copyWith({
    String? title,
    double? amount,
    String? category,
    String? walletId,
    bool clearWalletId = false,
    String? type,
    DateTime? date,
    bool? hasExplicitWallet,
    bool? hasExplicitDate,
    double? confidence,
    String? sourceText,
  }) {
    return TransactionDraft(
      title: title ?? this.title,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      walletId: clearWalletId ? null : (walletId ?? this.walletId),
      type: type ?? this.type,
      date: date ?? this.date,
      hasExplicitWallet: hasExplicitWallet ?? this.hasExplicitWallet,
      hasExplicitDate: hasExplicitDate ?? this.hasExplicitDate,
      confidence: confidence ?? this.confidence,
      sourceText: sourceText ?? this.sourceText,
    );
  }
}

class TransactionBatchDraft {
  final List<TransactionDraft> entries;
  final TransactionBatchSource source;
  final String rawInput;
  final double? expectedTotal;

  const TransactionBatchDraft({
    required this.entries,
    required this.source,
    required this.rawInput,
    this.expectedTotal,
  });
}

enum SmartEntryBatchStatus { none, ready, poisoned }

class SmartEntryBatchAttempt {
  final SmartEntryBatchStatus status;
  final TransactionBatchDraft? draft;
  final String? reason;

  const SmartEntryBatchAttempt._({
    required this.status,
    this.draft,
    this.reason,
  });

  const SmartEntryBatchAttempt.none()
      : this._(status: SmartEntryBatchStatus.none);

  const SmartEntryBatchAttempt.ready(TransactionBatchDraft value)
      : this._(status: SmartEntryBatchStatus.ready, draft: value);

  const SmartEntryBatchAttempt.poisoned(String message)
      : this._(status: SmartEntryBatchStatus.poisoned, reason: message);
}

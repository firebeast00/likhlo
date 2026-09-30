import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/local_nlp_service.dart';
import '../../services/smart_command.dart';
import '../../services/smart_input_engine.dart';
import '../../services/transaction_title_policy.dart';
import 'multi_entry_parser.dart';
import 'transaction_batch_draft.dart';

class SmartEntryBatchController {
  final MultiEntryParser parser;
  final SmartInputEngine engine;

  SmartEntryBatchController({
    MultiEntryParser? parser,
    SmartInputEngine? engine,
  })  : parser = parser ?? const MultiEntryParser(),
        engine = engine ?? SmartInputEngine();

  SmartEntryBatchAttempt tryBuild({
    required String rawText,
    required List<String> categories,
    required SmartInputSource source,
    required Iterable<SmartEntryAccount> accounts,
    String? preferredAccountId,
  }) {
    final segments = parser.tryParseBatch(rawText);
    if (segments == null || segments.length < 2) {
      return const SmartEntryBatchAttempt.none();
    }

    final accountList = accounts.toList(growable: false);
    final drafts = <TransactionDraft>[];

    for (final segment in segments) {
      final plan = engine.parse(
        segment,
        categories,
        source: source,
        accounts: accountList,
      );
      final parsed = plan.parsed;

      if (plan.command is! AddSmartTransactionCommand ||
          !parsed.amount.isFinite ||
          parsed.amount <= 0) {
        return const SmartEntryBatchAttempt.poisoned(
          'One of the detected entries is not a safe expense or income addition.',
        );
      }

      final type = parsed.intent == SmartEntryIntent.addIncome
          ? 'income'
          : 'expense';

      final explicitWalletId = findMentionedSmartEntryAccountId(
        plan.normalizedText,
        accountList,
      );
      final resolvedWalletId = resolveSmartEntryAccount(
        input: plan.normalizedText,
        accounts: accountList,
        transactionType: type,
        amount: parsed.amount,
        preferredAccountId: preferredAccountId,
      );

      drafts.add(
        TransactionDraft(
          title: _cleanTitle(
            parsed.title,
            parsed.category,
            type,
            resolvedWalletId,
            accountList,
          ),
          amount: parsed.amount,
          category: type == 'income'
              ? 'Income / Allowance'
              : parsed.category,
          walletId: resolvedWalletId,
          type: type,
          date: parsed.date,
          hasExplicitWallet: explicitWalletId != null,
          hasExplicitDate: parsed.hasExplicitDate,
          confidence: parsed.confidence,
          sourceText: segment,
        ),
      );
    }

    final inherited = _applyContextInheritance(drafts);
    return SmartEntryBatchAttempt.ready(
      TransactionBatchDraft(
        entries: inherited,
        source: source == SmartInputSource.voice
            ? TransactionBatchSource.voice
            : TransactionBatchSource.typed,
        rawInput: rawText,
      ),
    );
  }

  List<TransactionDraft> _applyContextInheritance(
    List<TransactionDraft> drafts,
  ) {
    final explicitWalletIds = drafts
        .where((entry) => entry.hasExplicitWallet && entry.walletId != null)
        .map((entry) => entry.walletId!)
        .toSet();

    final explicitDates = drafts
        .where((entry) => entry.hasExplicitDate)
        .map((entry) => DateTime(entry.date.year, entry.date.month, entry.date.day))
        .toSet();

    final inheritedWallet =
        explicitWalletIds.length == 1 ? explicitWalletIds.single : null;
    final inheritedDate =
        explicitDates.length == 1 ? explicitDates.single : null;

    return drafts.map((entry) {
      var updated = entry;
      if (!entry.hasExplicitWallet && inheritedWallet != null) {
        updated = updated.copyWith(walletId: inheritedWallet);
      }
      if (!entry.hasExplicitDate && inheritedDate != null) {
        updated = updated.copyWith(date: inheritedDate);
      }
      return updated;
    }).toList(growable: false);
  }

  String _cleanTitle(
    String rawTitle,
    String category,
    String type,
    String? walletId,
    List<SmartEntryAccount> accounts,
  ) {
    var title = rawTitle.trim();

    SmartEntryAccount? wallet;
    if (walletId != null) {
      for (final account in accounts) {
        if (account.id == walletId) {
          wallet = account;
          break;
        }
      }
    }

    if (wallet != null) {
      for (final phrase in [
        wallet.name,
        wallet.type,
        'cash in hand',
        'jazz cash',
        'jazzcash',
      ]) {
        final normalized = phrase.trim();
        if (normalized.isEmpty) continue;
        title = title.replaceAll(
          RegExp(
            '\\b${RegExp.escape(normalized)}\\b',
            caseSensitive: false,
          ),
          ' ',
        );
      }
    }

    title = title
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(
          RegExp(r'^(From|Via|Using)\s+', caseSensitive: false),
          '',
        );

    if (title.isEmpty || title.toLowerCase() == 'quick expense') {
      if (type == 'income') return 'Income Allowance';
      final fallback = category.trim().isEmpty ||
              category.trim().toLowerCase() == 'general'
          ? 'Quick Expense'
          : category;
      return coreTransactionTitle(fallback);
    }

    return coreTransactionTitle(title);
  }
}

final smartEntryBatchControllerProvider =
    Provider<SmartEntryBatchController>((ref) {
  return SmartEntryBatchController();
});

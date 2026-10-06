import 'local_nlp_service.dart';
import 'voice_diagnostics_service.dart';
import 'pakistani_language_normalizer.dart';

class UdharInput {
  final String person;
  final double amount;
  final String type;
  final bool canSaveImmediately;

  const UdharInput({
    required this.person,
    required this.amount,
    required this.type,
    required this.canSaveImmediately,
  });
}

/// Resolves debt commands without treating ordinary expenses as loans.
class UdharInputService {
  const UdharInputService();

  UdharInput? parse(String text, {
    Iterable<String> walletNames = const [],
    Iterable<SmartEntryAccount> accounts = const [],
  }) {
    // Debt verbs are deliberately local to Udhar; general expense intent stays unchanged.
    final debtText = text
        .replaceAll('ادھار', 'udhaar')
        .replaceAll('قرض', 'qarz')
        .replaceAll('دیا', 'diya')
        .replaceAll('دیے', 'diye')
        .replaceAll('لیا', 'liya')
        .replaceAll('لیے', 'liye');
    final normalization = PakistaniLanguageNormalizer().normalize(debtText);
    final normalized = normalization.normalized;
    VoiceDiagnosticsService.instance.stage('normalization', {
      'original': text, 'debt_script_input': debtText, 'normalized': normalized,
      'applied_rules': normalization.appliedRules,
    });
    // Main Smart Entry's negation/alternative safeguards also apply to Udhaar.
    if (RegExp(r'\b(nahi|nahin|mat|dont|don\x27t|ya|or)\b')
        .hasMatch(normalized)) {
      return null;
    }
    final parsed = LocalNlpService().parseCommand(normalized, const [
      'Udhaar',
      'Debt',
    ]);
    if (parsed.amount <= 0 ||
        !parsed.amount.isFinite ||
        RegExp(r'\d\s*:\s*\d').hasMatch(text)) {
      return null;
    }

    final borrowed = RegExp(
      r'\b(borrowed|borrow|took|liya|liye|lia|li|receive|received|lena)\b',
    ).hasMatch(normalized);
    final lent = RegExp(r'\b(lent|lend|loaned|gave|give|diya|dia|diye|dena)\b')
        .hasMatch(normalized);
    if (borrowed && lent) return null;

    var person = normalized.replaceAll(
      RegExp(
        r'\b(\d{1,3}(?:,\d{3})+|\d+(?:\.\d+)?)\s*(sau|hundred|hazar|hazaar|k|thousand|lakh|lak|lac|crore|krore|cr)?\b',
      ),
      ' ',
    );
    for (final wallet in walletNames) {
      final name = PakistaniLanguageNormalizer().normalize(wallet).normalized;
      if (name.isNotEmpty) {
        person = person.replaceAll(RegExp('\\b${RegExp.escape(name)}\\b'), ' ');
      }
    }
    final aliases = accounts
        .expand(smartEntryAccountAliases)
        .where((alias) => alias.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final alias in aliases) {
      person = person.replaceAll(RegExp('\\b${RegExp.escape(alias)}\\b'), ' ');
    }
    person = person
        .replaceAll(
          RegExp(
            r'\b(borrowed|borrow|took|liya|liye|lia|li|receive|received|lena|lent|lend|loaned|gave|give|diya|dia|diye|dena|udhaar|udhar|qarz|karz|loan|rs|pkr|rupees|rupee|from|to|se|sy|ko|me|mein|ka|ki|ke|ne|main|maine|karo|kar|do|aik|ek|one|two|teen|tin|chaar|char|paanch|panch|das|bees|tees|chalees|pachas|saath|sattar|assi|nabbe|sau|so|hazar|hazaar|lakh|lak|lac|crore|krore|cr|derh|dedh|dhai|sawa|paune)\b',
          ),
          ' ',
        )
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final words = person.split(' ').where((word) => word.length > 1).toList();
    person = words.take(3).join(' ');
    if (person.isNotEmpty) {
      person = person[0].toUpperCase() + person.substring(1);
    }
    VoiceDiagnosticsService.instance.stage('parse', {
      'intent': borrowed ? 'udhar_borrowed' : 'udhar_lent',
      'person': person, 'amount': parsed.amount, 'confidence': parsed.confidence,
      'confidence_by_field': parsed.confidenceByField,
      'can_save_immediately': (borrowed != lent) && person.isNotEmpty &&
          (parsed.confidenceByField['amount'] ?? 0) >= 0.9,
    });
    return UdharInput(
      person: person,
      amount: parsed.amount,
      type: borrowed ? 'borrowed' : 'lent',
      canSaveImmediately:
          (borrowed != lent) &&
          person.isNotEmpty &&
          (parsed.confidenceByField['amount'] ?? 0) >= 0.9,
    );
  }
}

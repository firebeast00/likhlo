import 'package:flutter_riverpod/flutter_riverpod.dart';



/// Feature-level entry point for Smart Entry interpretation.
///
/// Execution remains in the existing transaction layer. This controller owns
/// normalization/parsing so UI widgets do not construct SmartInputEngine
/// directly.
class SmartEntryController {
  final SmartInputEngine _engine;

  SmartEntryController({SmartInputEngine? engine})
      : _engine = engine ?? SmartInputEngine();

  SmartInputPlan parse(
    String input,
    List<String> categories, {
    required SmartInputSource source,
    List<SmartEntryAccount> accounts = const [],
  }) {
    return _engine.parse(
      input,
      categories,
      source: source,
      accounts: accounts,
    );
  }
}

final smartEntryControllerProvider = Provider<SmartEntryController>(
  (ref) => SmartEntryController(),
);

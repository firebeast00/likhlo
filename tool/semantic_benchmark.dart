import 'dart:convert';
import 'dart:io';

import 'package:student_expense_manager/services/smart_input_engine.dart';

Future<void> main(List<String> arguments) async {
  final path = arguments.isEmpty
      ? 'benchmark/pakistani_commands.jsonl'
      : arguments.first;
  final file = File(path);
  if (!await file.exists()) {
    stderr.writeln('Benchmark file not found: $path');
    exitCode = 2;
    return;
  }

  final engine = SmartInputEngine();
  var total = 0;
  var intentCorrect = 0;
  var amountCorrect = 0;
  var wholeCommandCorrect = 0;
  final failures = <String>[];

  await for (final line in file
      .openRead()
      .transform(utf8.decoder)
      .transform(const LineSplitter())) {
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    final sample = jsonDecode(line) as Map<String, dynamic>;
    final input = sample['input'] as String;
    final categories = (sample['categories'] as List<dynamic>? ??
            const ['General', 'Food', 'Transport', 'Shopping', 'Bills'])
        .cast<String>();
    final plan = engine.parse(input, categories);
    final expectedIntent = sample['intent'] as String;
    final expectedAmount = (sample['amount'] as num?)?.toDouble();
    final intentOk = plan.parsed.intent.wireName == expectedIntent;
    final amountOk = expectedAmount == null ||
        (plan.parsed.amount - expectedAmount).abs() < 0.005;

    total++;
    if (intentOk) intentCorrect++;
    if (amountOk) amountCorrect++;
    if (intentOk && amountOk) wholeCommandCorrect++;
    if (!intentOk || !amountOk) {
      failures.add(
        '${sample['id']}: expected $expectedIntent/$expectedAmount, got '
        '${plan.parsed.intent.wireName}/${plan.parsed.amount} '
        '(normalized: ${plan.normalizedText})',
      );
    }
  }

  if (total == 0) {
    stderr.writeln('No benchmark samples found.');
    exitCode = 2;
    return;
  }
  String percent(int value) => (100 * value / total).toStringAsFixed(1);
  stdout.writeln('Samples: $total');
  stdout.writeln('Intent accuracy: ${percent(intentCorrect)}%');
  stdout.writeln('Amount exact accuracy: ${percent(amountCorrect)}%');
  stdout.writeln(
    'Semantic command accuracy: ${percent(wholeCommandCorrect)}%',
  );
  if (failures.isNotEmpty) {
    stdout.writeln('\nFailures:');
    for (final failure in failures) {
      stdout.writeln('- $failure');
    }
    exitCode = 1;
  }
}

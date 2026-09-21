import 'dart:convert';
import 'dart:io';

import 'package:student_expense_manager/services/confidence_evaluator.dart';
import 'package:student_expense_manager/services/smart_command.dart';
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
  var titleCorrect = 0;
  var safetyCorrect = 0;
  var safetySamples = 0;
  var wholeCommandCorrect = 0;
  var totalParseMicros = 0;
  var slowestParseMicros = 0;
  String? slowestParseId;
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
    final source = sample['source'] == 'voice'
        ? SmartInputSource.voice
        : SmartInputSource.typed;
    final parseTimer = Stopwatch()..start();
    final plan = engine.parse(input, categories, source: source);
    parseTimer.stop();
    totalParseMicros += parseTimer.elapsedMicroseconds;
    if (parseTimer.elapsedMicroseconds > slowestParseMicros) {
      slowestParseMicros = parseTimer.elapsedMicroseconds;
      slowestParseId = sample['id']?.toString();
    }
    if (parseTimer.elapsedMilliseconds >= 1000) {
      failures.add(
        '${sample['id']}: parser exceeded the 1-second target '
        '(${parseTimer.elapsedMilliseconds} ms)',
      );
    }
    final expectedIntent = sample['intent'] as String;
    final expectedAmount = (sample['amount'] as num?)?.toDouble();
    final expectedTitle = sample['title'] as String?;
    final intentOk = plan.parsed.intent.wireName == expectedIntent;
    final amountOk = expectedAmount == null ||
        (plan.parsed.amount - expectedAmount).abs() < 0.005;
    final titleOk = expectedTitle == null ||
        plan.parsed.title.toLowerCase() == expectedTitle.toLowerCase();

    var safetyOk = true;
    final expectedAutoExecute = sample['allow_auto_execute'] as bool?;
    if (expectedAutoExecute != null) {
      safetySamples++;
      final confidence = const ConfidenceEvaluator().evaluate(
        plan.command,
        context: ConfidenceContext(
          hasResolvedWallet: true,
          hasExactAmount:
              (plan.parsed.confidenceByField['amount'] ?? 0) >= 0.9,
        ),
      );
      final isLedgerMutation =
          plan.command is AddSmartTransactionCommand ||
          plan.command is TransferCommand ||
          plan.command is MutationCommand ||
          plan.command is RepeatCommand;
      final wouldAutoExecute = isLedgerMutation &&
          confidence.canAutoExecute &&
          !plan.requiresAsrReview;
      safetyOk = wouldAutoExecute == expectedAutoExecute;
      if (safetyOk) safetyCorrect++;
    }

    total++;
    if (intentOk) intentCorrect++;
    if (amountOk) amountCorrect++;
    if (titleOk) titleCorrect++;
    if (intentOk && amountOk && titleOk && safetyOk) {
      wholeCommandCorrect++;
    }
    if (!intentOk || !amountOk || !titleOk || !safetyOk) {
      failures.add(
        '${sample['id']}: expected $expectedIntent/$expectedAmount/'
        '$expectedTitle, got ${plan.parsed.intent.wireName}/'
        '${plan.parsed.amount}/${plan.parsed.title} '
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
  stdout.writeln('Title exact accuracy: ${percent(titleCorrect)}%');
  if (safetySamples > 0) {
    stdout.writeln(
      'Safety expectation accuracy: '
      '${(100 * safetyCorrect / safetySamples).toStringAsFixed(1)}%',
    );
  }
  stdout.writeln(
    'Semantic command accuracy: ${percent(wholeCommandCorrect)}%',
  );
  stdout.writeln(
    'Average parse latency: '
    '${(totalParseMicros / total / 1000).toStringAsFixed(2)} ms',
  );
  stdout.writeln(
    'Slowest parse latency: '
    '${(slowestParseMicros / 1000).toStringAsFixed(2)} ms '
    '(${slowestParseId ?? 'unknown'})',
  );
  if (failures.isNotEmpty) {
    stdout.writeln('\nFailures:');
    for (final failure in failures) {
      stdout.writeln('- $failure');
    }
    exitCode = 1;
  }
}

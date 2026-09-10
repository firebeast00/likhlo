import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../providers/expense_provider.dart';
import '../providers/velocity_providers.dart';

class FinanceAiService {
  final WidgetRef ref;
  ChatSession? _chatSession;

  // 🚀 FALLBACK CASCADE: If one fails, the app instantly tries the next one.
  final List<String> _modelCascade = [
    'gemini-3.6-flash',
    'gemini-3.5-flash',
    'gemini-2.5-flash'
  ];
  String _currentModelName = 'gemini-3.7-flash';

  // Supply with --dart-define=GEMINI_API_KEY=... at build time.
  // Never keep a production key in source control.
  static const String _apiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  FinanceAiService(this.ref) {
    _initOrSwitchModel(_modelCascade.first);
  }

  /// Initializes a new ChatSession, injecting previous history if we are swapping models.
  void _initOrSwitchModel(String modelName, {List<Content>? history}) {
    final tools = [
      Tool(functionDeclarations: [
        FunctionDeclaration(
          'get_category_spending',
          'Calculates the total amount spent in a specific category for the current month.',
          Schema(
            SchemaType.object,
            properties: {
              'category': Schema(SchemaType.string, description: 'The exact category name.'),
            },
            requiredProperties: ['category'],
          ),
        ),
        FunctionDeclaration(
          'get_budget_health',
          'Gets the current daily burn rate, safe daily limit, and overall budget health status.',
          Schema(SchemaType.object, properties: {}),
        ),
      ])
    ];

    final model = GenerativeModel(
      model: modelName,
      apiKey: _apiKey, // 2. FIX: We now use the safe _apiKey variable!
      tools: tools,
      systemInstruction: Content.system(
          "You are an elite, slightly witty financial advisor built into the student expense tracker 'Likhlo'. "
              "Keep your answers concise, actionable, and formatted nicely. Always use your tools to check real data before answering."
      ),
    );

    _chatSession = model.startChat(history: history ?? []);
    _currentModelName = modelName;
  }

  Future<String> askFinancialQuestion(String prompt) async {
    if (_apiKey.isEmpty) {
      return "Likhlo AI is not configured in this build.";
    }
    // 3. 📸 SNAPSHOT: Save the clean history BEFORE we attempt the prompt.
    // This prevents broken history state if a model crashes mid-request.
    final List<Content> safeHistory = _chatSession?.history.toList() ?? [];

    for (int i = 0; i < _modelCascade.length; i++) {
      String modelToTry = _modelCascade[i];

      // If we are falling back, switch the model but inject the safe history!
      if (_currentModelName != modelToTry || _chatSession == null) {
        _initOrSwitchModel(modelToTry, history: safeHistory);
      }

      try {
        var response = await _chatSession!.sendMessage(Content.text(prompt));

        // 🔄 THE FUNCTION CALLING LOOP
        while (response.functionCalls.isNotEmpty) {
          final List<FunctionResponse> functionResponses = [];

          for (final call in response.functionCalls) {
            if (call.name == 'get_category_spending') {
              final category = call.args['category'] as String;
              final totalSpent = _getCategoryTotal(category);
              functionResponses.add(FunctionResponse(call.name, {'total_amount': totalSpent, 'currency': 'PKR'}));
            } else if (call.name == 'get_budget_health') {
              final velocity = ref.read(velocityProvider);
              functionResponses.add(FunctionResponse(call.name, {
                'daily_burn_rate': velocity.dailyVelocity,
                'safe_limit': velocity.safeDailyCap,
                'risk_level': velocity.riskLevel.name,
              }));
            }
          }

          response = await _chatSession!.sendMessage(Content.functionResponses(functionResponses));
        }

        return response.text ?? "I couldn't process that.";

      } catch (e) {
        String errorMsg = e.toString().toLowerCase();

        // Check if the error is related to Google's servers being overloaded
        bool isBusy = errorMsg.contains('429') ||
            errorMsg.contains('503') ||
            errorMsg.contains('quota') ||
            errorMsg.contains('exhausted') ||
            errorMsg.contains('overloaded');

        if (isBusy && i < _modelCascade.length - 1) {
          debugPrint("⚠️ Model $_currentModelName is busy. Falling back to ${_modelCascade[i+1]}...");
          continue; // The loop restarts, triggering the model switch
        } else {
          // If all models failed, or it's a network error, revert to the safe history
          _initOrSwitchModel(_currentModelName, history: safeHistory);
          return "⚠️ AI Connection Error: Please try again in a few moments.";
        }
      }
    }

    return "⚠️ Likhlo AI is experiencing extreme traffic right now. Please try again later.";
  }

  // --- INTERNAL HELPER METHODS ---
  double _getCategoryTotal(String categoryName) {
    final now = DateTime.now();
    final expenses = ref.read(expenseProvider).allExpenses;

    return expenses
        .where((e) => e.date.month == now.month &&
        e.date.year == now.year &&
        e.type == 'expense' && // 🚀 CRITICAL: Ignore incomes/allowances when calculating spending
        e.category.toLowerCase().contains(categoryName.toLowerCase()))
        .fold(0.0, (sum, item) => sum + item.amount);
  }
}

class LocalNlpService {
  // Singleton Pattern
  static final LocalNlpService _instance = LocalNlpService._internal();
  factory LocalNlpService() => _instance;
  LocalNlpService._internal();

  // Expanded lexicon for South Asian context
  final Map<String, String> _lexicon = {
    // Food & Dining
    'biryani': 'Food', 'burger': 'Food', 'burgers': 'Food', 'kfc': 'Food', 'mcdonalds': 'Food',
    'lunch': 'Food', 'dinner': 'Food', 'breakfast': 'Food', 'chai': 'Food', 'tea': 'Food',
    'coffee': 'Food', 'pizza': 'Food', 'ice cream': 'Food', 'groceries': 'Food', 'water': 'Food',
    'snack': 'Food', 'snacks': 'Food', 'roti': 'Food', 'karahi': 'Food',

    // Transport
    'petrol': 'Transport', 'fuel': 'Transport', 'uber': 'Transport', 'careem': 'Transport',
    'rickshaw': 'Transport', 'bike': 'Transport', 'bus': 'Transport', 'fare': 'Transport',
    'ticket': 'Transport', 'train': 'Transport', 'auto': 'Transport',

    // Shopping & Lifestyle
    'shirt': 'Shopping', 'shoes': 'Shopping', 'clothes': 'Shopping', 'shopping': 'Shopping',
    'jacket': 'Shopping', 'pant': 'Shopping', 'gift': 'Shopping', 'watch': 'Shopping',

    // Bills & Utilities
    'bill': 'Bills', 'bijli': 'Bills', 'electric': 'Bills', 'electricity': 'Bills',
    'gas': 'Bills', 'recharge': 'Bills', 'easyload': 'Bills', 'data plan': 'Bills',
    'wifi': 'Bills', 'internet': 'Bills', 'k-electric': 'Bills', 'k electric': 'Bills',

    // Health
    'medicine': 'Health', 'doctor': 'Health', 'clinic': 'Health', 'hospital': 'Health',
    'pharmacy': 'Health', 'pills': 'Health',

    // Education
    'fees': 'Education', 'book': 'Education', 'books': 'Education', 'pen': 'Education',
    'stationery': 'Education', 'copy': 'Education', 'register': 'Education', 'tuition': 'Education'
  };

  final List<String> _stopWords = [
    'ki', 'ka', 'ke', 'liye', 'for', 'spent', 'on', 'rs', 'rupees', 'rupee',
    'aur', 'the', 'a', 'an', 'paid', 'gave', 'to', 'mein', 'pe', 'khaye', 'diye',
    'bought', 'purchased', 'bill', 'amount'
  ];

  Map<String, dynamic> parseExpense(String input, List<String> activeCategories) {
    String lowerInput = input.toLowerCase();
    double amount = 0.0;
    String category = 'General';

    // 1. Extract Amount (Handles decimals and integers accurately)
    final amountRegExp = RegExp(r'\b\d+(\.\d+)?\b');
    final match = amountRegExp.firstMatch(lowerInput);
    if (match != null) {
      amount = double.tryParse(match.group(0)!) ?? 0.0;
    }

    // Convert active categories to lowercase for safe matching
    final lowerActiveCategories = activeCategories.map((c) => c.toLowerCase()).toList();

    // 2. Extract Category (Fixed Substring Bug using Word Boundaries)
    bool categoryFound = false;
    for (var entry in _lexicon.entries) {
      // \b ensures we match the exact word (e.g., 'pen' won't match inside 'spent')
      final regex = RegExp(r'\b' + entry.key + r'\b');

      if (regex.hasMatch(lowerInput)) {
        if (lowerActiveCategories.contains(entry.value.toLowerCase())) {
          category = activeCategories.firstWhere((c) => c.toLowerCase() == entry.value.toLowerCase());
          categoryFound = true;
          break;
        }
      }
    }

    // 3. Fallback: Direct Category Matching
    // If the user says "500 for Travel" and "Travel" is a category, catch it directly
    if (!categoryFound) {
      for (var cat in activeCategories) {
        if (RegExp(r'\b' + cat.toLowerCase() + r'\b').hasMatch(lowerInput)) {
          category = cat;
          break;
        }
      }
    }

    // 4. Clean the Title for the UI
    String cleanTitle = lowerInput.replaceAll(amountRegExp, ''); // Strip the number

    // Strip exactly matched stop words
    for (String stopWord in _stopWords) {
      cleanTitle = cleanTitle.replaceAll(RegExp(r'\b' + stopWord + r'\b'), '');
    }

    // Strip punctuation, remove double spaces, and trim
    cleanTitle = cleanTitle.replaceAll(RegExp(r'[^\w\s]'), '').trim();
    cleanTitle = cleanTitle.replaceAll(RegExp(r'\s+'), ' ');

    // 5. Format to Title Case (e.g., "Chicken Biryani" instead of "CHICKEN BIRYANI")
    if (cleanTitle.isEmpty) {
      cleanTitle = "Quick Expense";
    } else {
      cleanTitle = cleanTitle.split(' ').map((word) {
        if (word.isEmpty) return '';
        return word[0].toUpperCase() + word.substring(1).toLowerCase();
      }).join(' ');
    }

    return {
      'amount': amount,
      'category': category,
      'title': cleanTitle,
    };
  }
}
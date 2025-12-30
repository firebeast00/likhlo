import 'package:intl/intl.dart';

class Expense {
  String id; String title; String category; double amount; DateTime date;
  Expense({required this.id, required this.title, required this.category, required this.amount, required this.date});

  Map<String, dynamic> toMap() => {'id': id, 'title': title, 'category': category, 'amount': amount, 'date': date.toIso8601String()};

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'] ?? DateTime.now().toString(),
      title: map['title'] ?? 'Unknown',
      category: map['category'] ?? 'Other',
      amount: (map['amount'] ?? 0).toDouble(),
      date: DateTime.tryParse(map['date'] ?? '') ?? DateTime.now(),
    );
  }
}

class Debt {
  String id; String person; double amount; bool isIOwe; DateTime date;
  Debt({required this.id, required this.person, required this.amount, required this.isIOwe, required this.date});

  Map<String, dynamic> toMap() => {'id': id, 'person': person, 'amount': amount, 'isIOwe': isIOwe, 'date': date.toIso8601String()};

  factory Debt.fromMap(Map<String, dynamic> map) {
    return Debt(
      id: map['id'] ?? DateTime.now().toString(),
      person: map['person'] ?? 'Unknown',
      amount: (map['amount'] ?? 0).toDouble(),
      isIOwe: map['isIOwe'] ?? false,
      date: DateTime.tryParse(map['date'] ?? '') ?? DateTime.now(),
    );
  }
}
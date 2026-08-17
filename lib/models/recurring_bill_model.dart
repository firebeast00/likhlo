import 'package:hive/hive.dart';
part 'recurring_bill_model.g.dart';

@HiveType(typeId: 6)
class RecurringBill extends HiveObject {
  @HiveField(0)
  final String id;
  @HiveField(1)
  String title;
  @HiveField(2)
  double amount;
  @HiveField(3)
  String frequency; // 'Monthly' or 'Weekly'
  @HiveField(4)
  DateTime nextDueDate;

  RecurringBill({
    required this.id,
    required this.title,
    required this.amount,
    required this.frequency,
    required this.nextDueDate,
  });
}
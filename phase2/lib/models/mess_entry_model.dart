import 'package:hive/hive.dart';
part 'mess_entry_model.g.dart';

@HiveType(typeId: 7)
class MessEntry extends HiveObject {
  @HiveField(0)
  final String id;
  @HiveField(1)
  String title;
  @HiveField(2)
  double totalAmount;
  @HiveField(3)
  String paidBy;
  @HiveField(4)
  int splitCount; // Number of roommates sharing this cost
  @HiveField(5)
  DateTime date;

  MessEntry({
    required this.id,
    required this.title,
    required this.totalAmount,
    required this.paidBy,
    required this.splitCount,
    required this.date,
  });
}

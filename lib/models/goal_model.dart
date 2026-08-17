import 'package:hive/hive.dart';

part 'goal_model.g.dart';

@HiveType(typeId: 5)
class SmartGoal extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  double targetAmount;

  @HiveField(3)
  double savedAmount;

  @HiveField(4)
  DateTime targetDate;

  @HiveField(5)
  String categoryToTrim;

  SmartGoal({
    required this.id,
    required this.title,
    required this.targetAmount,
    this.savedAmount = 0.0,
    required this.targetDate,
    this.categoryToTrim = "Food",
  });
}
import 'package:hive/hive.dart';

part 'todo_model.g.dart';

@HiveType(typeId: 2)
class ToDoItem extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  bool isCompleted;

  @HiveField(3)
  final DateTime? date; // 👈 CHANGED: Added '?' to make it optional

  ToDoItem({
    required this.id,
    required this.title,
    this.isCompleted = false,
    this.date, // 👈 CHANGED: No longer 'required'
  });
}
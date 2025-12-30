import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/todo_model.dart';
import '../services/notification_service.dart';

class ToDoScreen extends StatefulWidget {
  const ToDoScreen({super.key});

  @override
  State<ToDoScreen> createState() => _ToDoScreenState();
}

class _ToDoScreenState extends State<ToDoScreen> {
  final TextEditingController _controller = TextEditingController();
  DateTime? _selectedDateTime;

  // Access the already opened box
  final Box<ToDoItem> todoBox = Hive.box<ToDoItem>('todos');

  Future<void> _addTodo() async {
    if (_controller.text.isNotEmpty) {
      final newItem = ToDoItem(
        id: const Uuid().v4(),
        title: _controller.text,
        isCompleted: false,
        // ✅ Ensure we always save a date, defaulting to Now if none selected
        date: _selectedDateTime ?? DateTime.now(),
      );

      int key = await todoBox.add(newItem);

      if (_selectedDateTime != null && _selectedDateTime!.isAfter(DateTime.now())) {
        await NotificationService().scheduleNotification(
            key,
            "Task Reminder 📌",
            newItem.title,
            _selectedDateTime!
        );
      }

      _controller.clear();
      setState(() {
        _selectedDateTime = null;
      });
    }
  }

  void _pickDateTime() async {
    DateTime? date = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime.now(),
        lastDate: DateTime(2030)
    );
    if (date == null) return;

    if (!mounted) return;

    TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now()
    );
    if (time == null) return;

    setState(() {
      _selectedDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // 1. INPUT AREA
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                    decoration: InputDecoration(
                      hintText: "Add a new task...",
                      hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.grey),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.notifications_none_rounded,
                      color: _selectedDateTime != null ? Theme.of(context).primaryColor : Colors.grey),
                  onPressed: _pickDateTime,
                ),
                IconButton(
                  icon: Icon(Icons.add_circle_rounded, color: Theme.of(context).primaryColor, size: 32),
                  onPressed: _addTodo,
                ),
              ],
            ),
          ),

          // 2. TASK LIST
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: todoBox.listenable(),
              builder: (context, Box<ToDoItem> box, _) {
                final todos = box.values.toList().cast<ToDoItem>();

                // ✅ FIX 1: Handle nullable dates in Sort
                todos.sort((a, b) {
                  if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;

                  // Safe access using '?? DateTime.now()' to treat nulls as current time
                  final dateA = a.date ?? DateTime.now();
                  final dateB = b.date ?? DateTime.now();
                  return dateB.compareTo(dateA);
                });

                if (todos.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline_rounded, size: 60, color: Colors.grey.withOpacity(0.3)),
                        const SizedBox(height: 10),
                        const Text("All Caught Up!", style: TextStyle(color: Colors.grey))
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: todos.length,
                  itemBuilder: (ctx, i) {
                    final todo = todos[i];

                    // ✅ FIX 2: Safely Format Date text
                    String dateText = "";
                    if (todo.date != null) {
                      try {
                        dateText = DateFormat.yMMMd().add_jm().format(todo.date!);
                      } catch (e) {
                        dateText = "Invalid Date";
                      }
                    }

                    // ✅ FIX 3: Safe check for Year (use ?. and ?? operators)
                    bool showSubtitle = (todo.date?.year ?? 0) != 1970;

                    return Dismissible(
                      key: Key(todo.id),
                      background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(16)),
                          child: const Icon(Icons.delete, color: Colors.white)
                      ),
                      onDismissed: (_) => todo.delete(),
                      child: Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.withOpacity(0.1))),
                        color: Theme.of(context).cardColor,
                        child: CheckboxListTile(
                          activeColor: Theme.of(context).primaryColor,
                          checkColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          title: Text(
                            todo.title,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              decoration: todo.isCompleted ? TextDecoration.lineThrough : null,
                              decorationColor: isDark ? Colors.grey : Colors.black,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          // Only show subtitle if we have a valid date string
                          subtitle: showSubtitle && dateText.isNotEmpty
                              ? Text(dateText, style: const TextStyle(fontSize: 12, color: Colors.grey))
                              : null,
                          value: todo.isCompleted,
                          onChanged: (val) {
                            todo.isCompleted = val!;
                            todo.save();
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/todo_model.dart';
import '../services/notification_service.dart';
import '../providers/settings_provider.dart';

class ToDoScreen extends ConsumerStatefulWidget {
  const ToDoScreen({super.key});

  @override
  ConsumerState<ToDoScreen> createState() => _ToDoScreenState();
}

class _ToDoScreenState extends ConsumerState<ToDoScreen> {
  final TextEditingController _controller = TextEditingController();
  DateTime? _selectedDateTime;
  String _currentFilter = 'Pending'; // Filters: All, Pending, Completed

  final Box<ToDoItem> todoBox = Hive.box<ToDoItem>('todos');

  Future<void> _addTodo() async {
    if (_controller.text.trim().isNotEmpty) {
      final newItem = ToDoItem(
        id: const Uuid().v4(),
        title: _controller.text.trim(),
        isCompleted: false,
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
      setState(() => _selectedDateTime = null);
      FocusScope.of(context).unfocus();
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

  void _clearCompleted() {
    final keysToDelete = todoBox.keys.where((key) {
      final item = todoBox.get(key);
      return item != null && item.isCompleted;
    }).toList();

    for (var key in keysToDelete) {
      todoBox.delete(key);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Cleared all completed tasks!"), backgroundColor: Colors.green),
    );
  }

  String _formatDateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final taskDate = DateTime(date.year, date.month, date.day);
    final timeStr = DateFormat.jm().format(date);

    if (taskDate == today) return "Today, $timeStr";
    if (taskDate == today.add(const Duration(days: 1))) return "Tomorrow, $timeStr";
    if (taskDate == today.subtract(const Duration(days: 1))) return "Yesterday, $timeStr";
    return "${DateFormat.MMMEd().format(date)}, $timeStr";
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final primaryColor = Color(settings.profileColorValue);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- HEADER & FILTERS ---
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Task Manager", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                    const SizedBox(height: 4),
                    ValueListenableBuilder(
                        valueListenable: todoBox.listenable(),
                        builder: (context, Box<ToDoItem> box, _) {
                          final pendingCount = box.values.where((t) => !t.isCompleted).length;
                          return Text(
                              pendingCount > 0 ? "You have $pendingCount pending tasks" : "You're all caught up!",
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 13, fontWeight: FontWeight.w500)
                          );
                        }
                    ),
                  ],
                ),
                if (_currentFilter == 'Completed' || _currentFilter == 'All')
                  InkWell(
                    onTap: _clearCompleted,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Text("Clear Done", style: TextStyle(color: Colors.red.shade400, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  )
              ],
            ),
          ),

          // --- FILTER CHIPS ---
          Container(
            height: 40,
            margin: const EdgeInsets.symmetric(vertical: 12),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: ['Pending', 'Completed', 'All'].map((filter) {
                bool isSelected = _currentFilter == filter;
                return GestureDetector(
                  onTap: () => setState(() => _currentFilter = filter),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: isSelected ? primaryColor : Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(20),
                      border: isSelected ? null : Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200, width: 1.2),
                      boxShadow: isSelected ? [BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))] : [],
                    ),
                    child: Center(
                      child: Text(
                          filter,
                          style: TextStyle(
                              color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                              fontSize: 13
                          )
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // --- SMART INPUT FIELD ---
          Container(
            margin: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.withOpacity(0.15), width: 1.5),
              boxShadow: [
                BoxShadow(color: isDark ? Colors.black26 : Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 4))
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: "What needs to be done?",
                          hintStyle: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.normal, fontSize: 14),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onSubmitted: (_) => _addTodo(),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _selectedDateTime != null ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
                        color: _selectedDateTime != null ? primaryColor : Colors.grey.shade400,
                        size: 22,
                      ),
                      tooltip: "Set Reminder",
                      onPressed: _pickDateTime,
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _addTodo,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: primaryColor, shape: BoxShape.circle, boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.4), blurRadius: 6, offset: const Offset(0, 2))]),
                        child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
                if (_selectedDateTime != null) ...[
                  const Divider(height: 1, thickness: 0.5),
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.schedule_rounded, size: 14, color: primaryColor),
                        const SizedBox(width: 6),
                        Text(
                          "Reminder: ${_formatDateLabel(_selectedDateTime!)}",
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: primaryColor),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () => setState(() => _selectedDateTime = null),
                          child: const Icon(Icons.close_rounded, size: 16, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // --- TASK LIST ---
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: todoBox.listenable(),
              builder: (context, Box<ToDoItem> box, _) {
                var todos = box.values.toList().cast<ToDoItem>();

                // Apply Filters
                if (_currentFilter == 'Pending') {
                  todos = todos.where((t) => !t.isCompleted).toList();
                } else if (_currentFilter == 'Completed') {
                  todos = todos.where((t) => t.isCompleted).toList();
                }

                // Sort: Incomplete first, then by closest date
                todos.sort((a, b) {
                  if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
                  final dateA = a.date ?? DateTime.now();
                  final dateB = b.date ?? DateTime.now();
                  return dateA.compareTo(dateB); // Ascending order (oldest/most urgent first)
                });

                if (todos.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(color: primaryColor.withOpacity(0.1), shape: BoxShape.circle),
                          child: Icon(
                              _currentFilter == 'Completed' ? Icons.done_all_rounded : Icons.check_circle_rounded,
                              size: 60, color: primaryColor
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                            _currentFilter == 'Completed' ? "No completed tasks." : "All Caught Up!",
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                        ),
                        const SizedBox(height: 6),
                        Text(
                            _currentFilter == 'Pending' ? "Enjoy your free time or add a new task." : "",
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 13)
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: todos.length,
                  itemBuilder: (ctx, i) {
                    final todo = todos[i];

                    // Date logic
                    bool hasValidDate = (todo.date?.year ?? 0) != 1970;
                    bool isOverdue = hasValidDate && !todo.isCompleted && todo.date!.isBefore(DateTime.now());

                    return Dismissible(
                      key: Key(todo.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(16)),
                        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                      ),
                      onDismissed: (_) => todo.delete(),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.withOpacity(0.15), width: 1.2),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // CUSTOM CHECKBOX
                            GestureDetector(
                              onTap: () {
                                todo.isCompleted = !todo.isCompleted;
                                todo.save();
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.only(top: 2),
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: todo.isCompleted ? primaryColor : Colors.transparent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: todo.isCompleted ? primaryColor : Colors.grey.shade400,
                                      width: 2
                                  ),
                                ),
                                child: todo.isCompleted ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
                              ),
                            ),
                            const SizedBox(width: 14),
                            // TASK DETAILS
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    todo.title,
                                    style: TextStyle(
                                      color: todo.isCompleted ? Colors.grey.shade500 : (isDark ? Colors.white : Colors.black87),
                                      decoration: todo.isCompleted ? TextDecoration.lineThrough : null,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  if (hasValidDate) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(
                                            Icons.schedule_rounded,
                                            size: 12,
                                            color: todo.isCompleted ? Colors.grey.shade500 : (isOverdue ? Colors.red : primaryColor)
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _formatDateLabel(todo.date!),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: todo.isCompleted ? Colors.grey.shade500 : (isOverdue ? Colors.red : primaryColor),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ]
                                ],
                              ),
                            ),
                          ],
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
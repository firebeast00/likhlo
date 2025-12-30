import 'package:flutter/material.dart';
import 'dart:math';

class UtilitiesScreen extends StatefulWidget {
  const UtilitiesScreen({super.key});
  @override
  State<UtilitiesScreen> createState() => _UtilitiesScreenState();
}

class _UtilitiesScreenState extends State<UtilitiesScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text("Student Zone", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const Text("Relax and sharpen your mind", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),

          _gameCard(Icons.timer_outlined, "Speed Math", "Test your calculation speed", Colors.purple, _playSpeedMath),
          _gameCard(Icons.quiz_rounded, "Guess Number", "Find the hidden number", Colors.orange, _playGuessNumber),
          _gameCard(Icons.casino_outlined, "Roll Dice", "Need a random number?", Colors.blue, _playRollDice),
          _gameCard(Icons.grid_view_rounded, "Memory Grid", "Coming Soon...", Colors.teal, (){}),
        ],
      ),
    );
  }

  Widget _gameCard(IconData icon, String title, String subtitle, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.grey.withOpacity(0.1)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, size: 28, color: color)),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)), Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey))]),
          const Spacer(),
          Icon(Icons.play_circle_fill_rounded, color: color.withOpacity(0.5))
        ]),
      ),
    );
  }

  void _playSpeedMath() { int num1 = Random().nextInt(20) + 1; int num2 = Random().nextInt(20) + 1; int answer = num1 + num2; TextEditingController c = TextEditingController(); showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("Speed Math"), content: Column(mainAxisSize: MainAxisSize.min, children: [Text("$num1 + $num2 = ?", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)), TextField(controller: c, keyboardType: TextInputType.number, autofocus: true)]), actions: [ElevatedButton(onPressed: (){ if (c.text == answer.toString()) { Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Correct!"))); } else { Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Wrong! It was $answer"))); } }, child: const Text("Check"))])); }
  void _playGuessNumber() { int target = Random().nextInt(100) + 1; TextEditingController c = TextEditingController(); showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("Guess (1-100)"), content: TextField(controller: c, keyboardType: TextInputType.number, autofocus: true), actions: [ElevatedButton(onPressed: (){ int guess = int.tryParse(c.text) ?? 0; Navigator.pop(ctx); if (guess == target) { _alert("🎉 Perfect!", "You guessed $target!"); } else { _alert("Nope", "It was $target."); } }, child: const Text("Guess"))])); }
  void _playRollDice() { _alert("Dice Rolled", "You got a ${Random().nextInt(6) + 1}! 🎲"); }
  void _alert(String title, String msg) { showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(title), content: Text(msg), actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text("OK"))])); }
}
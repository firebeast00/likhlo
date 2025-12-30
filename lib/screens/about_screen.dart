import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: Colors.transparent, // Uses parent Scaffold logic
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo / Icon
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(color: primary.withOpacity(0.1), shape: BoxShape.circle),
                child: Image.asset(
                  'assets/app_logo.png',
                  width: 120,
                  height: 120,
                ),
              ),
              const SizedBox(height: 20),

              // App Name
              Text("Likhlo", style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black87)),
              const Text("Student Expense Manager", style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w500)),

              const SizedBox(height: 40),

              // Description
              _buildInfoCard(context, Icons.info_rounded, "About", "Likhlo is designed specifically for students to manage pocket money, track hostel expenses, and handle 'Udhaar' (debts) efficiently."),
              const SizedBox(height: 15),
              _buildInfoCard(context, Icons.code_rounded, "Developer", "Developed by Jawad Rajper"),
              const SizedBox(height: 15),
              _buildInfoCard(context, Icons.verified_user_rounded, "Version", "2.5.0 (Stable)"),

              const SizedBox(height: 40),
              Text("© 2024 Likhlo Inc.", style: TextStyle(color: Colors.grey.withOpacity(0.5), fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, IconData icon, String title, String subtitle) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Theme.of(context).primaryColor.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: Theme.of(context).primaryColor),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: Colors.grey, height: 1.4)),
              ],
            ),
          )
        ],
      ),
    );
  }
}
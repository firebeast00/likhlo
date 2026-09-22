import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).primaryColor;
    final currentYear = DateTime.now().year;

    return Scaffold(
      backgroundColor: Colors.transparent, // Uses parent Scaffold logic
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // --- 1. HERO LOGO SECTION ---
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(36),
                border: Border.all(
                    color: primary.withValues(alpha: 0.15), width: 2),
              ),
              child: Image.asset(
                'assets/app_logo.png',
                width: 80,
                height: 80,
              ),
            ),
            const SizedBox(height: 24),

            // --- 2. APP IDENTITY ---
            Text(
              "Likhlo",
              style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.0,
                  color: isDark ? Colors.white : Colors.black87),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: Text(
                "Version 2.5.0 (Stable)",
                style: TextStyle(
                    fontSize: 12,
                    color: primary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5),
              ),
            ),
            const SizedBox(height: 40),

            // --- 3. DEVELOPER SHOWCASE CARD ---
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primary, primary.withValues(alpha: 0.8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle),
                        child: const Icon(Icons.terminal_rounded,
                            color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Lead Developer",
                                style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5)),
                            SizedBox(height: 4),
                            Text("Jawad Rajper",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Full-Stack Developer • BSIT, SBBU",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Engineered as a comprehensive final year project to solve real-world student financial management challenges.",
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                        height: 1.5),
                  ),
                  const SizedBox(height: 20),

                  // Contact Information Block
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Column(
                      children: [
                        Row(
                          children: [
                            Icon(Icons.email_rounded,
                                color: Colors.white70, size: 16),
                            SizedBox(width: 12),
                            Expanded(
                                child: Text("jawadrajper5001@gmail.com",
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600))),
                          ],
                        ),
                        SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.wechat_rounded,
                                color: Colors.white70,
                                size:
                                    16), // Using wechat or chat icon as WhatsApp alternative
                            SizedBox(width: 12),
                            Expanded(
                                child: Text("+92 307 3156483",
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600))),
                          ],
                        ),
                      ],
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 24),

            // --- 4. APP MISSION & INFO GROUP ---
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                    color: isDark
                        ? Colors.white10
                        : Colors.grey.withValues(alpha: 0.1)),
              ),
              child: Column(
                children: [
                  _buildListTile(
                    context: context,
                    icon: Icons.rocket_launch_rounded,
                    iconColor: Colors.orange,
                    title: "Our Mission",
                    subtitle:
                        "Empowering students to track pocket money, manage hostel khata, and handle Udhaar with AI-driven insights.",
                  ),
                  Divider(
                      height: 1,
                      indent: 64,
                      color: isDark
                          ? Colors.white10
                          : Colors.grey.withValues(alpha: 0.1)),
                  _buildListTile(
                    context: context,
                    icon: Icons.shield_rounded,
                    iconColor: Colors.green,
                    title: "Privacy First",
                    subtitle:
                        "All your financial data is stored securely and locally on your device using Hive.",
                  ),
                  Divider(
                      height: 1,
                      indent: 64,
                      color: isDark
                          ? Colors.white10
                          : Colors.grey.withValues(alpha: 0.1)),
                  _buildListTile(
                    context: context,
                    icon: Icons.code_rounded,
                    iconColor: Colors.blue,
                    title: "Architecture",
                    subtitle:
                        "Built with Flutter, Riverpod, Local NLP, and Material 3 Design.",
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),

            // --- 5. FOOTER ---
            Icon(Icons.favorite_rounded, color: Colors.red.shade400, size: 24),
            const SizedBox(height: 12),
            Text("Made with passion in Sindh, Pakistan",
                style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text("© $currentYear Likhlo App",
                style: TextStyle(
                    color: Colors.grey.withValues(alpha: 0.5), fontSize: 11)),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildListTile({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isDark ? Colors.white : Colors.black87)),
                const SizedBox(height: 6),
                Text(subtitle,
                    style: TextStyle(
                        color: Colors.grey.shade500,
                        height: 1.4,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          )
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'dart:async';

class FypPrototypeScreen extends StatefulWidget {
  const FypPrototypeScreen({super.key});

  @override
  State<FypPrototypeScreen> createState() => _FypPrototypeScreenState();
}

class _FypPrototypeScreenState extends State<FypPrototypeScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;

  // SHARED STATE
  final TextEditingController _nlpController = TextEditingController();
  final List<Map<String, dynamic>> _transactions = [];
  double _totalSpent = 0;

  // TAB 1: NLP STATE
  bool _isNlpLoading = false;
  bool _isListening = false;
  late AnimationController _micPulseController;

  // TAB 2: OCR STATE
  bool _isScanning = false;
  late AnimationController _laserController;
  late Animation<double> _laserAnimation;

  // TAB 4: SMART GOALS STATE
  bool _isGoalProcessing = false;
  bool _hasActiveGoal = false;
  String _goalStatusText = "";

  @override
  void initState() {
    super.initState();
    _micPulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000), lowerBound: 0.8, upperBound: 1.2);
    _laserController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _laserAnimation = Tween<double>(begin: 0.0, end: 300.0).animate(CurvedAnimation(parent: _laserController, curve: Curves.easeInOutSine));
  }

  @override
  void dispose() {
    _micPulseController.dispose();
    _laserController.dispose();
    _nlpController.dispose();
    super.dispose();
  }

  // ==========================================
  // TAB 1: NLP ENGINE
  // ==========================================
  void _startVoiceSimulation() async {
    setState(() { _isListening = true; _nlpController.text = "Listening..."; });
    _micPulseController.repeat(reverse: true);
    await Future.delayed(const Duration(seconds: 2));
    setState(() { _isListening = false; _nlpController.text = "850 ki biryani aur cold drink"; });
    _micPulseController.stop(); _micPulseController.reset();
    await Future.delayed(const Duration(milliseconds: 500));
    _processSmartEntry();
  }

  void _processSmartEntry() async {
    final input = _nlpController.text.trim();
    if (input.isEmpty || input == "Listening...") return;
    setState(() => _isNlpLoading = true);
    if (mounted) FocusScope.of(context).unfocus();
    await Future.delayed(const Duration(milliseconds: 1200));

    final numberMatch = RegExp(r'\d+').firstMatch(input);
    final amount = numberMatch != null ? double.parse(numberMatch.group(0)!) : 0.0;
    String title = input.replaceAll(RegExp(r'\d+'), '').replaceAll('ki', '').replaceAll('aur', '&').trim();

    setState(() {
      _transactions.insert(0, {"title": title.toUpperCase(), "amount": amount, "method": "🤖 Gemini NLP", "icon": Icons.auto_awesome_rounded, "color": Colors.purpleAccent});
      _totalSpent += amount;
      _isNlpLoading = false;
      _nlpController.clear();
    });
  }

  Widget _buildNlpTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: const Color(0xFF4F46E5).withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 10))]),
                  child: Column(children: [
                    const Text("Total Auto-Logged", style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Text("Rs. ${_totalSpent.toStringAsFixed(0)}", style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: -1)),
                  ]),
                ),
                const SizedBox(height: 35),
                const Text("AI Smart Entry", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(color: isDark ? const Color(0xFF1E293B) : Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))]),
                  child: Row(children: [
                    const SizedBox(width: 20),
                    Expanded(child: TextField(controller: _nlpController, enabled: !_isListening && !_isNlpLoading, decoration: InputDecoration(hintText: _isListening ? 'Listening...' : 'Type or speak "500 ki biryani"', border: InputBorder.none), onSubmitted: (_) => _processSmartEntry())),
                    ScaleTransition(scale: _micPulseController, child: IconButton(icon: Icon(_isListening ? Icons.mic : Icons.mic_none_rounded), color: _isListening ? Colors.purpleAccent : Colors.grey, onPressed: _isNlpLoading ? null : _startVoiceSimulation)),
                    Padding(padding: const EdgeInsets.all(8.0), child: InkWell(onTap: (_isNlpLoading || _isListening) ? null : _processSmartEntry, child: CircleAvatar(radius: 22, backgroundColor: _nlpController.text.isNotEmpty || _isNlpLoading ? Colors.purpleAccent : Colors.grey.withOpacity(0.2), child: _isNlpLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Icon(Icons.send_rounded, color: _nlpController.text.isNotEmpty ? Colors.white : Colors.grey, size: 20))))
                  ]),
                ),
                const SizedBox(height: 30),
                const Text("Recent Auto-Entries", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
              ],
            ),
          ),
        ),
        _transactions.isEmpty
            ? SliverToBoxAdapter(child: Center(child: Padding(padding: const EdgeInsets.only(top: 40), child: Column(children: [Icon(Icons.bubble_chart_rounded, size: 60, color: Colors.grey.withOpacity(0.2)), const SizedBox(height: 10), const Text("Awaiting AI input...", style: TextStyle(color: Colors.grey))]))))
            : SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 20), sliver: SliverList(delegate: SliverChildBuilderDelegate((context, index) {
          final t = _transactions[index];
          return Container(margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: isDark ? const Color(0xFF1E293B) : Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.withOpacity(0.1))), child: ListTile(leading: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: t["color"].withOpacity(0.1), shape: BoxShape.circle), child: Icon(t["icon"], color: t["color"], size: 24)), title: Text(t["title"], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), subtitle: Text(t["method"], style: TextStyle(color: t["color"], fontSize: 12, fontWeight: FontWeight.w600)), trailing: Text("Rs. ${t["amount"].toStringAsFixed(0)}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))));
        }, childCount: _transactions.length))),
      ],
    );
  }

  // ==========================================
  // TAB 2: OCR SCANNER
  // ==========================================
  void _runScannerSimulator() async {
    setState(() => _isScanning = true);
    _laserController.repeat(reverse: true);
    await Future.delayed(const Duration(seconds: 4));
    _laserController.stop();
    setState(() {
      _transactions.insert(0, {"title": "IMTIAZ SUPER MART", "amount": 8450.0, "method": "📷 ML Kit OCR Extracted", "icon": Icons.document_scanner_rounded, "color": Colors.blueAccent});
      _totalSpent += 8450.0;
      _isScanning = false;
      _currentIndex = 0;
    });
  }

  Widget _buildScannerTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text("ML Kit OCR Scanner", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text("Position receipt within the frame", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 30),
          Container(
            width: 300, height: 400,
            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.blueAccent.withOpacity(0.5), width: 2), boxShadow: [BoxShadow(color: Colors.blueAccent.withOpacity(0.2), blurRadius: 20, spreadRadius: 5)]),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 220, height: 320, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Center(child: Text("IMTIAZ SUPER MART", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16))),
                    const Divider(color: Colors.black),
                    _receiptLine("Eggs (1 Dozen)", "350"), _receiptLine("Milk (1L)", "250"), _receiptLine("Bread", "150"), _receiptLine("Cooking Oil", "2700"), _receiptLine("Rice (5kg)", "5000"),
                    const Spacer(), const Divider(color: Colors.black, thickness: 2),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("TOTAL", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)), Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(border: Border.all(color: _isScanning ? Colors.green : Colors.transparent, width: 2)), child: const Text("Rs 8450", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)))])
                  ]),
                ),
                if (_isScanning) AnimatedBuilder(animation: _laserAnimation, builder: (context, child) => Positioned(top: _laserAnimation.value + 30, child: Container(width: 240, height: 3, decoration: const BoxDecoration(color: Colors.greenAccent, boxShadow: [BoxShadow(color: Colors.greenAccent, blurRadius: 10, spreadRadius: 2)])))),
              ],
            ),
          ),
          const SizedBox(height: 40),
          SizedBox(width: 200, height: 55, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))), icon: _isScanning ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.document_scanner, color: Colors.white), label: Text(_isScanning ? "Processing..." : "Scan Receipt", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)), onPressed: _isScanning ? null : _runScannerSimulator))
        ],
      ),
    );
  }

  Widget _receiptLine(String item, String price) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4.0), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(item, style: const TextStyle(color: Colors.black87, fontSize: 12)), Text(price, style: const TextStyle(color: Colors.black87, fontSize: 12))]));
  }

  // ==========================================
  // TAB 3: AI VELOCITY PREDICTION
  // ==========================================
  Widget _buildVelocityTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Velocity Engine", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const Text("Proactive burn-rate analysis", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 30),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.red.shade200)),
            child: Column(
              children: [
                const Row(children: [Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28), SizedBox(width: 10), Text("Critical Velocity Alert", style: TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold))]),
                const SizedBox(height: 15),
                const Text("Based on your 7-day moving average (Rs. 2,100/day), you will exhaust your budget 6 days before the month ends.", style: TextStyle(color: Colors.redAccent, fontSize: 15, height: 1.5)),
                const SizedBox(height: 20),
                LinearProgressIndicator(value: 0.85, backgroundColor: Colors.red.withOpacity(0.2), valueColor: const AlwaysStoppedAnimation(Colors.red), minHeight: 8, borderRadius: BorderRadius.circular(4)),
                const SizedBox(height: 8),
                const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Current: 15th", style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)), Text("Empty: 24th", style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold))])
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 4: SMART GOALS PROCESS SIMULATOR
  // ==========================================
  void _runGoalSimulation() async {
    setState(() { _isGoalProcessing = true; _goalStatusText = "Analyzing 3 months of spending history..."; });
    await Future.delayed(const Duration(seconds: 2));

    setState(() => _goalStatusText = "Identifying non-essential expenses...");
    await Future.delayed(const Duration(seconds: 2));

    setState(() => _goalStatusText = "Structuring daily micro-savings plan...");
    await Future.delayed(const Duration(seconds: 2));

    setState(() { _isGoalProcessing = false; _hasActiveGoal = true; });
  }

  Widget _buildSmartGoalsTab() {
    if (_isGoalProcessing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.teal),
            const SizedBox(height: 24),
            Text(_goalStatusText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.teal)),
          ],
        ),
      );
    }

    if (_hasActiveGoal) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("AI Savings Strategy", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
            const Text("Your generated dynamic plan", style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 30),

            // GOAL CARD
            // GOAL CARD
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Colors.teal, Color(0xFF0D9488)]),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.teal.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))]
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // 👇 FIX: Wrapped in Expanded to prevent overflow
                        const Expanded(
                          child: Text(
                            "Laptop Upgrade",
                            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis, // Adds '...' if text is too long
                          ),
                        ),
                        const SizedBox(width: 10), // Adds a tiny buffer between text and badge
                        Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                            child: const Text("Rs. 150,000", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                        )
                      ]
                  ),
                  const SizedBox(height: 20),
                  const Text("Target Date: Dec 2026", style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: 0.1, backgroundColor: Colors.white.withOpacity(0.2), valueColor: const AlwaysStoppedAnimation(Colors.white), minHeight: 8, borderRadius: BorderRadius.circular(4)),
                  const SizedBox(height: 8),
                  const Text("Saved: Rs. 15,000 (10%)", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))
                ],
              ),
            ),

            // AI INSIGHT CARD
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.teal.shade200)),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [Icon(Icons.auto_awesome_rounded, color: Colors.teal, size: 28), SizedBox(width: 10), Text("How to achieve this?", style: TextStyle(color: Colors.teal, fontSize: 18, fontWeight: FontWeight.bold))]),
                  SizedBox(height: 15),
                  Text("To save the required Rs. 650/day, the AI recommends:", style: TextStyle(color: Colors.teal, fontSize: 15, fontWeight: FontWeight.bold)),
                  SizedBox(height: 10),
                  Text("• Reduce weekend dining by 15%\n• Switch to a cheaper data plan\n• Pause your Spotify Premium until December", style: TextStyle(color: Colors.teal, fontSize: 14, height: 1.6)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // EMPTY STATE FOR GOALS
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.flag_circle_rounded, size: 80, color: Colors.teal.withOpacity(0.2)),
          const SizedBox(height: 20),
          const Text("No Active Goals", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text("Tell us what you are saving for, and our AI will build a daily micro-savings plan.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, height: 1.5)),
          ),
          const SizedBox(height: 40),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
            icon: const Icon(Icons.rocket_launch_rounded, color: Colors.white),
            label: const Text("Create Goal: 'Laptop' (Rs. 150k)", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            onPressed: _runGoalSimulation,
          )
        ],
      ),
    );
  }

  // ==========================================
  // MAIN BUILD
  // ==========================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text("Likhlo Pro Architecture", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)), centerTitle: true, backgroundColor: Colors.transparent, elevation: 0),
      body: SafeArea(
        child: IndexedStack(
          index: _currentIndex,
          children: [_buildNlpTab(), _buildScannerTab(), _buildVelocityTab(), _buildSmartGoalsTab()],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5))]),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) => setState(() => _currentIndex = index),
          backgroundColor: Theme.of(context).cardColor,
          elevation: 0,
          indicatorColor: Colors.blueAccent.withOpacity(0.2),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.chat_bubble_outline_rounded), selectedIcon: Icon(Icons.chat_bubble_rounded, color: Colors.blueAccent), label: 'NLP Engine'),
            NavigationDestination(icon: Icon(Icons.document_scanner_outlined), selectedIcon: Icon(Icons.document_scanner_rounded, color: Colors.blueAccent), label: 'OCR Scanner'),
            NavigationDestination(icon: Icon(Icons.speed_rounded), selectedIcon: Icon(Icons.speed_rounded, color: Colors.blueAccent), label: 'Velocity'),
            NavigationDestination(icon: Icon(Icons.flag_outlined), selectedIcon: Icon(Icons.flag_rounded, color: Colors.teal), label: 'Smart Goals'),
          ],
        ),
      ),
    );
  }
}
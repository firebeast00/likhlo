import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../services/finance_ai_service.dart';

// 🚀 NEW: Global state to let HomeScreen know when to hide the FAB!
final isAiChatOpenProvider = StateProvider<bool>((ref) => false);

class ChatMessage {
  final String text;
  final bool isUser;
  ChatMessage({required this.text, required this.isUser});
}

class AiChatOverlay extends ConsumerStatefulWidget {
  const AiChatOverlay({super.key});

  @override
  ConsumerState<AiChatOverlay> createState() => _AiChatOverlayState();
}

class _AiChatOverlayState extends ConsumerState<AiChatOverlay> {
  // Dragging State
  Offset _position = const Offset(20, 100);
  bool _isExpanded = false;

  // Chat & AI State
  late FinanceAiService _aiService;
  final TextEditingController _msgCtrl = TextEditingController();
  final List<ChatMessage> _messages = [
    ChatMessage(text: "Hi Jawad! I'm your Likhlo AI. Ask me about your spending.", isUser: false)
  ];
  bool _isTyping = false;

  // 🎤 STT State
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _aiService = FinanceAiService(ref);
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  // --- 🚀 NEW EXPAND / COLLAPSE LOGIC ---
  void _expandChat() {
    setState(() => _isExpanded = true);
    ref.read(isAiChatOpenProvider.notifier).state = true;
  }

  void _collapseChat() {
    setState(() => _isExpanded = false);
    ref.read(isAiChatOpenProvider.notifier).state = false;
  }

  // --- 🎤 VOICE INPUT LOGIC ---
  void _listenForInput() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (val) {
          if (val == 'done' || val == 'notListening') {
            setState(() => _isListening = false);
            if (_msgCtrl.text.isNotEmpty && _msgCtrl.text != "Listening...") {
              _sendMessage();
            }
          }
        },
        onError: (val) => setState(() => _isListening = false),
      );

      if (available) {
        setState(() => _isListening = true);
        _msgCtrl.text = "Listening...";
        _speech.listen(
          onResult: (val) => setState(() {
            _msgCtrl.text = val.recognizedWords;
          }),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Speech recognition unavailable.")));
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  // --- 💬 CHAT LOGIC ---
  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || text == "Listening...") return;

    if (_isListening) {
      _speech.stop();
      setState(() => _isListening = false);
    }

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _msgCtrl.clear();
      _isTyping = true;
    });

    final aiResponse = await _aiService.askFinancialQuestion(text);

    setState(() {
      _messages.add(ChatMessage(text: aiResponse, isUser: false));
      _isTyping = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Hide overlay if keyboard is open & chat is closed to prevent collision
    final bool isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    if (isKeyboardOpen && !_isExpanded) return const SizedBox.shrink();

    final screenSize = MediaQuery.of(context).size;
    final primaryColor = Theme.of(context).primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned(
      left: _isExpanded ? 16 : _position.dx,
      top: _isExpanded ? 100 : _position.dy,
      right: _isExpanded ? 16 : null,
      bottom: _isExpanded ? 16 : null,
      child: _isExpanded
          ? _buildExpandedChat(primaryColor, isDark)
          : _buildCollapsedFAB(screenSize, primaryColor),
    );
  }

  Widget _buildCollapsedFAB(Size screenSize, Color primaryColor) {
    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          double newX = _position.dx + details.delta.dx;
          double newY = _position.dy + details.delta.dy;
          newX = newX.clamp(0.0, screenSize.width - 60);
          newY = newY.clamp(kToolbarHeight, screenSize.height - 120);
          _position = Offset(newX, newY);
        });
      },
      onTap: _expandChat, // 🚀 Uses new method
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: primaryColor,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _buildExpandedChat(Color primaryColor, bool isDark) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: primaryColor.withOpacity(0.3), width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 24, offset: const Offset(0, 12))],
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded, color: primaryColor),
                      const SizedBox(width: 10),
                      const Text("Likhlo AI", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: _collapseChat, // 🚀 Uses new method
                  )
                ],
              ),
            ),

            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                reverse: true,
                itemCount: _messages.length + (_isTyping ? 1 : 0),
                itemBuilder: (context, index) {
                  if (_isTyping && index == 0) return _buildTypingIndicator(primaryColor);
                  final msg = _messages[_messages.length - 1 - (index - (_isTyping ? 1 : 0))];
                  return _buildChatBubble(msg, primaryColor, isDark);
                },
              ),
            ),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.1)))),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(_isListening ? Icons.mic : Icons.mic_none_rounded, color: _isListening ? Colors.red : primaryColor),
                    onPressed: _listenForInput,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      decoration: InputDecoration(
                        hintText: _isListening ? "Listening..." : "Ask about your budget...",
                        hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                        filled: true,
                        fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(color: primaryColor, shape: BoxShape.circle),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                      onPressed: _sendMessage,
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildChatBubble(ChatMessage msg, Color primaryColor, bool isDark) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: msg.isUser ? primaryColor : (isDark ? Colors.grey.shade800 : Colors.grey.shade100),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(msg.isUser ? 16 : 4),
            bottomRight: Radius.circular(msg.isUser ? 4 : 16),
          ),
          border: msg.isUser ? null : Border.all(color: Colors.grey.withOpacity(0.1)),
        ),
        child: Text(msg.text, style: TextStyle(color: msg.isUser ? Colors.white : (isDark ? Colors.white : Colors.black87), fontSize: 14)),
      ),
    );
  }

  Widget _buildTypingIndicator(Color primaryColor) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, color: primaryColor, size: 16),
            const SizedBox(width: 8),
            Text("Analyzing finances...", style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }
}
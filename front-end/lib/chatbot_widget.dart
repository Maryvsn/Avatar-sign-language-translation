import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'theme.dart';

// ══════════════════════════════════════════════════════════════════════
//  Chat Message Model
// ══════════════════════════════════════════════════════════════════════
class _ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  _ChatMessage({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

// ══════════════════════════════════════════════════════════════════════
//  AI Chatbot FAB + Floating Chat Window
// ══════════════════════════════════════════════════════════════════════
class AIChatbotOverlay extends StatefulWidget {
  const AIChatbotOverlay({super.key});

  @override
  State<AIChatbotOverlay> createState() => _AIChatbotOverlayState();
}

class _AIChatbotOverlayState extends State<AIChatbotOverlay>
    with TickerProviderStateMixin {
  bool _isOpen = false;
  final _messages = <_ChatMessage>[];
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _isTyping = false;

  // FAB pulse animation
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // Chat window slide-up animation
  late AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  // Glow ring animation
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;

  final List<String> _quickSuggestions = [
    "كيف أستخدم الكاميرا؟",
    "ما هي لغة الإشارة؟",
    "كيف أبدأ الاختبار؟",
    "ترجمة جملة إلى إشارة",
    "كيف أرفع فيديو؟",
  ];

  @override
  void initState() {
    super.initState();

    // FAB pulsing
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _pulseCtrl.repeat(reverse: true);

    // Glow ring
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _glowAnim = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );
    _glowCtrl.repeat(reverse: true);

    // Chat window slide
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut),
    );

    // Welcome message
    _messages.add(_ChatMessage(
      text: "مرحباً! 👋 أنا مساعد HandAI الذكي.\nكيف يمكنني مساعدتك اليوم؟",
      isUser: false,
    ));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _glowCtrl.dispose();
    _slideCtrl.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _toggleChat() {
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _slideCtrl.forward();
      } else {
        _slideCtrl.reverse();
      }
    });
  }

  void _sendMessage(String text) {
    if (text.trim().isEmpty) return;

    setState(() {
      _messages.add(_ChatMessage(text: text.trim(), isUser: true));
      _inputCtrl.clear();
      _isTyping = true;
    });

    _scrollToBottom();

    // Simulate AI response
    Future.delayed(const Duration(milliseconds: 800 + 400), () {
      if (!mounted) return;
      setState(() {
        _isTyping = false;
        _messages.add(_ChatMessage(
          text: _getAIResponse(text.trim()),
          isUser: false,
        ));
      });
      _scrollToBottom();
    });
  }

  String _getAIResponse(String query) {
    final q = query.toLowerCase();
    if (q.contains('كاميرا') || q.contains('camera')) {
      return "📷 لاستخدام الكاميرا:\n1. اضغط على \"ترجمة إلى نص\" من الشاشة الرئيسية\n2. قم بعمل إشارة أمام الكاميرا\n3. سيتم التعرف عليها تلقائياً وعرض الترجمة";
    } else if (q.contains('إشارة') || q.contains('sign')) {
      return "🤟 لغة الإشارة هي نظام تواصل بصري يستخدم حركات اليد والجسم. تطبيقنا يدعم أكثر من 100 إشارة عربية!";
    } else if (q.contains('اختبار') || q.contains('quiz')) {
      return "🎮 لبدء الاختبار:\n1. اضغط على \"اختبر مهاراتك\" من الشاشة الرئيسية\n2. شاهد الأفاتار وهو يؤدي الإشارة\n3. اختر الإجابة الصحيحة من 4 خيارات\n4. لديك 15 ثانية لكل سؤال!";
    } else if (q.contains('ترجمة') || q.contains('جملة')) {
      return "✍️ لترجمة جملة إلى لغة الإشارة:\n1. اضغط على \"ترجمة إلى لغة الإشارة\"\n2. اكتب الجملة في المربع\n3. اضغط ترجمة وشاهد الأفاتار يؤديها!";
    } else if (q.contains('فيديو') || q.contains('رفع') || q.contains('ملف')) {
      return "📹 لرفع فيديو أو GIF:\n1. اذهب لشاشة الكاميرا\n2. اضغط على \"استيراد ملف\"\n3. اختر فيديو أو GIF من جهازك\n4. سيتم تحليله وترجمة الإشارات فيه";
    } else {
      return "شكراً لسؤالك! 😊\nيمكنني مساعدتك في:\n• استخدام الكاميرا للترجمة\n• ترجمة النصوص إلى لغة الإشارة\n• خوض اختبار لغة الإشارة\n\nاختر من الاقتراحات أدناه أو اكتب سؤالك!";
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── Chat Window ────────────────────────────────
        if (_isOpen)
          Positioned(
            bottom: 170,
            right: 16,
            child: SlideTransition(
              position: _slideAnim,
              child: FadeTransition(
                opacity: _fadeAnim,
                child: _buildChatWindow(),
              ),
            ),
          ),

        // ── FAB ────────────────────────────────────────
        Positioned(
          bottom: 100,
          right: 20,
          child: _buildFAB(),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  Floating Action Button with pulse + glow
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildFAB() {
    return GestureDetector(
      onTap: _toggleChat,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseAnim, _glowAnim]),
        builder: (context, child) {
          return Transform.scale(
            scale: _isOpen ? 1.0 : _pulseAnim.value,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFFA855F7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFA855F7)
                        .withOpacity(_isOpen ? 0.3 : _glowAnim.value),
                    blurRadius: _isOpen ? 12 : 24,
                    spreadRadius: _isOpen ? 1 : 4,
                  ),
                  BoxShadow(
                    color: const Color(0xFF7C3AED).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) =>
                    RotationTransition(turns: anim, child: child),
                child: Icon(
                  _isOpen ? Icons.close_rounded : Icons.smart_toy_rounded,
                  key: ValueKey(_isOpen),
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  Chat Window — Glassmorphic floating panel
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildChatWindow() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: 360,
          height: 520,
          decoration: BoxDecoration(
            color: const Color(0xFF0B0F19).withOpacity(0.92),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFFA855F7).withOpacity(0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFA855F7).withOpacity(0.15),
                blurRadius: 40,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildChatHeader(),
              Expanded(child: _buildMessageList()),
              _buildQuickSuggestions(),
              _buildInputBar(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Chat Header ──────────────────────────────────────────────────
  Widget _buildChatHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withOpacity(0.08),
          ),
        ),
      ),
      child: Row(
        children: [
          // Close button
          GestureDetector(
            onTap: _toggleChat,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded,
                  color: Colors.white70, size: 18),
            ),
          ),
          const Spacer(),
          // Title + Status
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                "مساعد الذكاء الاصطناعي",
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "متصل الآن",
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.emerald,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.emerald.withOpacity(0.6),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(width: 12),
          // Avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7C3AED), Color(0xFFA855F7)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFA855F7).withOpacity(0.4),
                  blurRadius: 10,
                ),
              ],
            ),
            child: const Icon(Icons.smart_toy_rounded,
                color: Colors.white, size: 22),
          ),
        ],
      ),
    );
  }

  // ── Message List ─────────────────────────────────────────────────
  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      itemCount: _messages.length + (_isTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length && _isTyping) {
          return _buildTypingIndicator();
        }
        final msg = _messages[index];
        return _buildBubble(msg);
      },
    );
  }

  Widget _buildBubble(_ChatMessage msg) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: const BoxConstraints(maxWidth: 280),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          textDirection: msg.isUser ? TextDirection.rtl : TextDirection.ltr,
          children: [
            // AI avatar (only for AI messages)
            if (!msg.isUser) ...[
              Container(
                width: 26,
                height: 26,
                margin: const EdgeInsets.only(right: 8, bottom: 2),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFFA855F7)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFA855F7).withOpacity(0.3),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: const Icon(Icons.smart_toy_rounded,
                    color: Colors.white, size: 14),
              ),
            ],
            // Bubble
            Flexible(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: msg.isUser
                      ? const Color(0xFF4338CA).withOpacity(0.85)
                      : Colors.white.withOpacity(0.07),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft:
                        Radius.circular(msg.isUser ? 18 : 4),
                    bottomRight:
                        Radius.circular(msg.isUser ? 4 : 18),
                  ),
                  border: msg.isUser
                      ? null
                      : Border.all(
                          color: const Color(0xFFA855F7).withOpacity(0.15),
                        ),
                  boxShadow: [
                    if (msg.isUser)
                      BoxShadow(
                        color: const Color(0xFF4338CA).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                  ],
                ),
                child: Text(
                  msg.text,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    color: msg.isUser
                        ? Colors.white
                        : Colors.white.withOpacity(0.9),
                    fontSize: 13.5,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, left: 34),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFFA855F7).withOpacity(0.15),
          ),
        ),
        child: const _TypingDots(),
      ),
    );
  }

  // ── Quick Suggestions ────────────────────────────────────────────
  Widget _buildQuickSuggestions() {
    return SizedBox(
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _quickSuggestions.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: GestureDetector(
              onTap: () => _sendMessage(_quickSuggestions[index]),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFA855F7).withOpacity(0.25),
                  ),
                ),
                child: Text(
                  _quickSuggestions[index],
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 11.5,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Input Bar ────────────────────────────────────────────────────
  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
      ),
      child: Row(
        children: [
          // Send button
          GestureDetector(
            onTap: () => _sendMessage(_inputCtrl.text),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFFA855F7)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFA855F7).withOpacity(0.4),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: const Icon(Icons.send_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 8),
          // Text Field
          Expanded(
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
              child: TextField(
                controller: _inputCtrl,
                textDirection: TextDirection.rtl,
                style: const TextStyle(color: Colors.white, fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: "اكتب رسالتك...",
                  hintTextDirection: TextDirection.rtl,
                  hintStyle:
                      TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: _sendMessage,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Mic button
          GestureDetector(
            onTap: () {
              // TODO: Voice input integration
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
              child: Icon(Icons.mic_rounded,
                  color: Colors.white.withOpacity(0.5), size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  Typing Dots Indicator — 3 bouncing dots
// ══════════════════════════════════════════════════════════════════════
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (i) {
      return AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      );
    });
    _animations = _controllers.map((c) {
      return Tween<double>(begin: 0, end: -6).animate(
        CurvedAnimation(parent: c, curve: Curves.easeInOut),
      );
    }).toList();

    // Stagger start
    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 180), () {
        if (mounted) _controllers[i].repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _animations[i],
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, _animations[i].value),
              child: Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFA855F7).withOpacity(0.7),
                  shape: BoxShape.circle,
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

import 'dart:math';
import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'theme.dart';
import 'camera_screen.dart';
import 'text_to_sign_screen.dart';
import 'settings_screen.dart';
import 'quiz_screen.dart';
import 'profile_screen.dart';

// ══════════════════════════════════════════════════════════════════════
//  Voice Assistant Overlay — Persistent bottom indicator + commands
// ══════════════════════════════════════════════════════════════════════
class VoiceAssistantOverlay extends StatefulWidget {
  const VoiceAssistantOverlay({super.key});

  @override
  State<VoiceAssistantOverlay> createState() => _VoiceAssistantOverlayState();
}

class _VoiceAssistantOverlayState extends State<VoiceAssistantOverlay>
    with TickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isAvailable = false;
  bool _isListening = false;
  bool _isSpeechActive = false; // voice detected
  String _lastRecognized = '';
  String _feedbackText = '';
  bool _showFeedback = false;
  bool _feedbackSuccess = false;
  Timer? _inactivityTimer;

  // Animations
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;
  late AnimationController _orbCtrl;
  late Animation<double> _orbAnim;
  late AnimationController _waveCtrl;
  late AnimationController _feedbackCtrl;
  late Animation<double> _feedbackAnim;

  // Wave bars for active speech visualization
  final List<double> _waveBars = List.generate(7, (_) => 0.3);

  // Color constants
  static const _neonCyan = Color(0xFF06B6D4);
  static const _indigo = Color(0xFF6366F1);
  static const _purple = Color(0xFFA855F7);
  static const _emerald = Color(0xFF10B981);
  static const _bg = Color(0xFF0B0F19);

  // ── Command Map ─────────────────────────────────────────────────
  static const _commandCategories = [
    _CommandCategory(
      title: 'التنقل',
      icon: Icons.explore_rounded,
      color: _indigo,
      commands: [
        _VoiceCommand('افتح الكاميرا', 'الانتقال لشاشة الكاميرا', 'camera'),
        _VoiceCommand('ابدأ الكويز', 'بدء اختبار لغة الإشارة', 'quiz'),
        _VoiceCommand('الرئيسية', 'العودة للصفحة الرئيسية', 'home'),
        _VoiceCommand('الترجمة', 'ترجمة نص إلى لغة الإشارة', 'translate'),
        _VoiceCommand('الإعدادات', 'فتح صفحة الإعدادات', 'settings'),
      ],
    ),
    _CommandCategory(
      title: 'التمرير',
      icon: Icons.swap_vert_rounded,
      color: _neonCyan,
      commands: [
        _VoiceCommand('انزل', 'تمرير الصفحة للأسفل', 'scroll_down'),
        _VoiceCommand('اطلع', 'تمرير الصفحة للأعلى', 'scroll_up'),
      ],
    ),
    _CommandCategory(
      title: 'الإجراءات',
      icon: Icons.flash_on_rounded,
      color: _purple,
      commands: [
        _VoiceCommand('سجل فيديو', 'بدء تسجيل فيديو', 'record'),
        _VoiceCommand('وقف التسجيل', 'إيقاف التسجيل', 'stop_record'),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();

    // Idle pulse for the pill indicator
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _pulseCtrl.repeat(reverse: true);

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _glowAnim = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );
    _glowCtrl.repeat(reverse: true);

    // Orb expansion animation
    _orbCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _orbAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _orbCtrl, curve: Curves.easeOutCubic),
    );

    // Wave animation for active speech bars
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    )..addListener(_updateWaveBars);

    // Feedback banner animation
    _feedbackCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _feedbackAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _feedbackCtrl, curve: Curves.easeOutCubic),
    );

    _initSpeech();
  }

  void _updateWaveBars() {
    if (!_isSpeechActive) return;
    final rng = Random();
    setState(() {
      for (int i = 0; i < _waveBars.length; i++) {
        _waveBars[i] = 0.2 + rng.nextDouble() * 0.8;
      }
    });
  }

  String _selectedLocale = 'ar-SA'; // will be auto-detected

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    if (_isListening) {
      _inactivityTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _isListening) {
          _toggleListening();
          _showFeedbackBanner('انتهى وقت الاستماع', false);
        }
      });
    }
  }

  Future<void> _initSpeech() async {
    try {
      _isAvailable = await _speech.initialize(
        onStatus: _onSpeechStatus,
        onError: (e) {
          print('[Voice] Error: ${e.errorMsg}');
          _resetInactivityTimer();
        },
      );
      print('[Voice] Speech available: $_isAvailable');

      if (_isAvailable) {
        // Discover available locales and pick best Arabic one
        final locales = await _speech.locales();
        print('[Voice] Available locales (${locales.length}):');
        for (final loc in locales) {
          print('[Voice]   ${loc.localeId} — ${loc.name}');
        }

        // Try to find an Arabic locale
        final arabicLocale = locales.firstWhere(
          (l) => l.localeId.startsWith('ar'),
          orElse: () => locales.firstWhere(
            (l) => l.localeId.contains('ar'),
            orElse: () => locales.isNotEmpty ? locales.first : locales.first,
          ),
        );

        _selectedLocale = arabicLocale.localeId;
        print('[Voice] ✅ Selected locale: $_selectedLocale (${arabicLocale.name})');

        // If no Arabic available, warn
        if (!_selectedLocale.startsWith('ar')) {
          print('[Voice] ⚠️ No Arabic locale found! Using: $_selectedLocale');
          print('[Voice] ℹ️ To add Arabic: Windows Settings → Time & Language → Language → Add "العربية"');
        }
      }
    } catch (e) {
      print('[Voice] Init error: $e');
      _isAvailable = false;
    }
    if (mounted) setState(() {});
  }

  void _onSpeechStatus(String status) {
    print('[Voice] Status: $status');
    _resetInactivityTimer();
    if (status == 'notListening' && _isListening && mounted) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && _isListening) _startListening();
      });
    }
    if (status == 'listening') {
      setState(() => _isSpeechActive = true);
      _orbCtrl.forward();
      _waveCtrl.repeat();
    } else {
      setState(() => _isSpeechActive = false);
      _orbCtrl.reverse();
      _waveCtrl.stop();
    }
  }

  void _startListening() {
    if (!_isAvailable || !mounted) return;

    print('[Voice] Starting listen with locale: $_selectedLocale');
    _resetInactivityTimer();
    _speech.listen(
      onResult: (result) {
        _resetInactivityTimer();
        setState(() {
          _lastRecognized = result.recognizedWords;
          _isSpeechActive = result.hasConfidenceRating && result.confidence > 0;
        });
        if (result.finalResult) {
          _processCommand(result.recognizedWords);
        }
      },
      localeId: _selectedLocale,
      listenMode: stt.ListenMode.dictation,
      cancelOnError: false,
      partialResults: true,
    );
  }

  void _toggleListening() {
    setState(() => _isListening = !_isListening);
    if (_isListening) {
      _startListening();
    } else {
      _inactivityTimer?.cancel();
      _speech.stop();
      _orbCtrl.reverse();
      _waveCtrl.stop();
      setState(() => _isSpeechActive = false);
    }
  }

  // ── Command Processing ──────────────────────────────────────────
  void _processCommand(String text) {
    final t = text.trim().toLowerCase();
    if (t.isEmpty) return;
    print('[Voice] Processing: "$t"');

    // Help / Commands
    if (t.contains('مساعدة') || t.contains('أوامر') || t.contains('help') || t.contains('commands') || t.contains('musa')) {
      _showCommandSheet();
      _showFeedbackBanner('مساعدة — عرض الأوامر', true);
      return;
    }

    // Navigation
    if (t.contains('الكاميرا') || t.contains('كاميرا') || t.contains('camera')) {
      _navigate(const CameraScreen());
      _showFeedbackBanner('افتح الكاميرا ✓', true);
      return;
    }
    if (t.contains('كويز') || t.contains('اختبار') || t.contains('quiz') || t.contains('test')) {
      _navigate(const QuizScreen());
      _showFeedbackBanner('ابدأ الكويز ✓', true);
      return;
    }
    if (t.contains('ترجمة') || t.contains('الترجمة') || t.contains('translate') || t.contains('translation')) {
      _navigate(const TextToSignScreen());
      _showFeedbackBanner('الترجمة ✓', true);
      return;
    }
    if (t.contains('إعدادات') || t.contains('الإعدادات') || t.contains('settings') || t.contains('setting')) {
      _navigate(SettingsScreen(onThemeChanged: (_) {}));
      _showFeedbackBanner('الإعدادات ✓', true);
      return;
    }
    if (t.contains('الرئيسية') || t.contains('رئيسية') || t.contains('home') || t.contains('main')) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      _showFeedbackBanner('الرئيسية ✓', true);
      return;
    }

    // Scrolling
    if (t.contains('انزل') || t.contains('down') || t.contains('scroll down')) {
      _showFeedbackBanner('تمرير للأسفل ↓', true);
      return;
    }
    if (t.contains('اطلع') || t.contains('up') || t.contains('scroll up')) {
      _showFeedbackBanner('تمرير للأعلى ↑', true);
      return;
    }

    // Recording
    if (t.contains('سجل') || t.contains('فيديو') || t.contains('record') || t.contains('video')) {
      _showFeedbackBanner('سجل فيديو 🔴', true);
      return;
    }
    if (t.contains('وقف') || t.contains('stop')) {
      _showFeedbackBanner('وقف التسجيل ⏹', true);
      return;
    }

    // No match — show what was heard
    _showFeedbackBanner('"$t" — لم يُتعرف على الأمر', false);
  }

  void _navigate(Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  void _showFeedbackBanner(String text, bool success) {
    setState(() {
      _feedbackText = text;
      _showFeedback = true;
      _feedbackSuccess = success;
    });
    _feedbackCtrl.forward(from: 0);

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _feedbackCtrl.reverse().then((_) {
          if (mounted) setState(() => _showFeedback = false);
        });
      }
    });
  }

  // ── Command Reference Bottom Sheet ──────────────────────────────
  void _showCommandSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _buildCommandSheet(),
    );
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _speech.cancel();
    _pulseCtrl.dispose();
    _glowCtrl.dispose();
    _orbCtrl.dispose();
    _waveCtrl.dispose();
    _feedbackCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── Feedback Banner (top) ──────────────────────────
        if (_showFeedback)
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: FadeTransition(
              opacity: _feedbackAnim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.5),
                  end: Offset.zero,
                ).animate(_feedbackCtrl),
                child: _buildFeedbackBanner(),
              ),
            ),
          ),

        // ── Voice Indicator (bottom-right floating) ────────────────
        Positioned(
          bottom: 170, // Above the chatbot FAB
          right: 24,
          child: GestureDetector(
            onTap: _isListening ? _showCommandSheet : _toggleListening,
            onLongPress: _toggleListening,
            child: _buildVoiceIndicator(),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  Voice Pulse Indicator
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildVoiceIndicator() {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnim, _glowAnim, _orbAnim]),
      builder: (context, _) {
        final orbProgress = _orbAnim.value;
        final isExpanded = _isListening && _isSpeechActive;

        // Size interpolation: circular FAB → slightly larger glowing orb
        final size = lerpDouble(48, 56, orbProgress)!;
        final borderRadius = size / 2;

        return Transform.scale(
          scale: _pulseAnim.value, // Always pulse
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // The circular indicator itself
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(borderRadius),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFFA855F7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7C3AED)
                          .withOpacity(_glowAnim.value),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(borderRadius),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Center(
                    child: Icon(
                      _isListening ? Icons.hearing_rounded : Icons.mic_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

  // ═══════════════════════════════════════════════════════════════════
  //  Feedback Banner — top toast
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildFeedbackBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: _bg.withOpacity(0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: (_feedbackSuccess ? _emerald : Colors.amber)
              .withOpacity(0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (_feedbackSuccess ? _emerald : Colors.amber)
                .withOpacity(0.15),
            blurRadius: 20,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: TextDirection.rtl,
        children: [
          Icon(
            _feedbackSuccess
                ? Icons.check_circle_rounded
                : Icons.info_outline_rounded,
            color: _feedbackSuccess ? _emerald : Colors.amber,
            size: 22,
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              _feedbackText,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  Command Reference Bottom Sheet
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildCommandSheet() {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollCtrl) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(28),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              decoration: BoxDecoration(
                color: _bg.withOpacity(0.94),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                border: Border.all(
                  color: _purple.withOpacity(0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _purple.withOpacity(0.12),
                    blurRadius: 40,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                children: [
                  // ── Drag handle ──
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // ── Header ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Row(
                      textDirection: TextDirection.rtl,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [_neonCyan, _indigo],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: _neonCyan.withOpacity(0.3),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.record_voice_over_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'الأوامر الصوتية',
                                textDirection: TextDirection.rtl,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'قل أمراً صوتياً أو اضغط للتنفيذ',
                                textDirection: TextDirection.rtl,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  Divider(
                    color: Colors.white.withOpacity(0.08),
                    indent: 20,
                    endIndent: 20,
                  ),

                  // ── Command Categories ──
                  Expanded(
                    child: ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                      itemCount: _commandCategories.length,
                      itemBuilder: (_, i) =>
                          _buildCategorySection(_commandCategories[i]),
                    ),
                  ),

                  // ── Close Button ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.1),
                          ),
                        ),
                        child: const Text(
                          'إغلاق',
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategorySection(_CommandCategory cat) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Category header
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                cat.title,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: cat.color,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cat.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: cat.color.withOpacity(0.3),
                  ),
                ),
                child: Icon(cat.icon, color: cat.color, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Command cards
          ...cat.commands.map((cmd) => _buildCommandCard(cmd, cat.color)),
        ],
      ),
    );
  }

  Widget _buildCommandCard(_VoiceCommand cmd, Color accentColor) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context); // close sheet
        _processCommand(cmd.phrase);
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: accentColor.withOpacity(0.15),
          ),
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            // Command phrase badge
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accentColor.withOpacity(0.2),
                    accentColor.withOpacity(0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: accentColor.withOpacity(0.3),
                ),
              ),
              child: Text(
                '"${cmd.phrase}"',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Description
            Expanded(
              child: Text(
                cmd.description,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_back_ios_rounded,
              color: Colors.white.withOpacity(0.2),
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  Data Models
// ══════════════════════════════════════════════════════════════════════
class _CommandCategory {
  final String title;
  final IconData icon;
  final Color color;
  final List<_VoiceCommand> commands;

  const _CommandCategory({
    required this.title,
    required this.icon,
    required this.color,
    required this.commands,
  });
}

class _VoiceCommand {
  final String phrase;
  final String description;
  final String actionId;

  const _VoiceCommand(this.phrase, this.description, this.actionId);
}

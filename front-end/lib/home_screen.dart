import 'dart:ui';
import 'package:flutter/material.dart';
import 'theme.dart';
import 'bubble_screen.dart';
import 'camera_screen.dart';
import 'text_to_sign_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'user_session.dart';
import 'quiz_screen.dart';
import 'chatbot_widget.dart';
import 'voice_assistant_widget.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  int _navIndex = 0;
  String _userName = 'User';

  late AnimationController _heroCtrl;
  late Animation<double> _heroScale;
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _loadUserData();

    _heroCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 3));
    _heroScale = Tween<double>(begin: 1.0, end: 1.08).animate(
        CurvedAnimation(parent: _heroCtrl, curve: Curves.easeInOut));
    _heroCtrl.repeat(reverse: true);

    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2));
    _glowAnim = Tween<double>(begin: 0.3, end: 0.7).animate(
        CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));
    _glowCtrl.repeat(reverse: true);
  }

  Future<void> _loadUserData() async {
    final name = await UserSession.getUserName();
    setState(() => _userName = name);
  }

  @override
  void dispose() {
    _heroCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  void _onNavTapped(int index) {
    if (index == 1) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const CameraScreen()));
    } else if (index == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SettingsScreen(
            onThemeChanged: (_) {},
          ),
        ),
      );
    } else if (index == 3) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const ProfileScreen(isDarkMode: true)));
    } else {
      setState(() => _navIndex = index);
    }
  }

  void _goToTextToSign() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TextToSignScreen()),
    );
  }

  void _goToCamera() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CameraScreen()),
    );
  }

  void _goToQuiz() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QuizScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: Stack(
        children: [
          // ── Ambient Glow Background ────────────────────────
          Positioned(
            top: -80,
            left: -60,
            child: AnimatedBuilder(
              animation: _glowAnim,
              builder: (_, __) => Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withOpacity(_glowAnim.value * 0.15),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 100,
            right: -40,
            child: AnimatedBuilder(
              animation: _glowAnim,
              builder: (_, __) => Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.accent.withOpacity(_glowAnim.value * 0.1),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Main Content ───────────────────────────────────
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Top Bar ─────────────────────────────────
                  Row(
                    children: [
                      // App logo
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.sign_language_rounded,
                            color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ShaderMask(
                            shaderCallback: (b) => AppColors.primaryGradient.createShader(b),
                            child: const Text(
                              "AI Hand ",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                                fontSize: 22,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const Text(
                            "🤟",
                            style: TextStyle(
                              fontSize: 22,
                              color: Colors.amberAccent,
                              fontFamilyFallback: ['Segoe UI Emoji', 'Apple Color Emoji'],
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      // Notification bell (glassmorphic)
                      Container(
                        width: 42,
                        height: 42,
                        decoration: AppColors.glassCard(borderRadius: 14),
                        child: Icon(Icons.notifications_none_rounded,
                            color: Colors.white.withOpacity(0.7), size: 22),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // ── Greeting ────────────────────────────────
                  Text(
                    "مرحباً، $_userName 👋",
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "ماذا تريد أن تفعل اليوم؟",
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 15,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── Hero Card (Glassmorphic) ─────────────────
                  ScaleTransition(
                    scale: _heroScale,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.primary.withOpacity(0.15),
                            AppColors.accent.withOpacity(0.08),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.3),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.15),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Glowing icon ring
                          AnimatedBuilder(
                            animation: _glowAnim,
                            builder: (_, __) => Container(
                              width: 90,
                              height: 90,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    AppColors.primary.withOpacity(0.2),
                                    AppColors.accent.withOpacity(0.05),
                                  ],
                                ),
                                border: Border.all(
                                  color: AppColors.primary.withOpacity(
                                      0.3 + _glowAnim.value * 0.3),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(
                                        _glowAnim.value * 0.3),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.sign_language_rounded,
                                size: 40,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            "AI Hand",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "مدعوم بالذكاء الاصطناعي",
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.neonCyan.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── Feature Buttons ─────────────────────────
                  _buildFeatureButton(
                    icon: Icons.translate_rounded,
                    title: "ترجمة إلى لغة الإشارة",
                    subtitle: "اكتب جملة أو كلمة وشاهد الترجمة",
                    gradient: AppColors.primaryGradient,
                    glowColor: AppColors.primary,
                    onTap: _goToTextToSign,
                  ),
                  const SizedBox(height: 16),
                  _buildFeatureButton(
                    icon: Icons.videocam_rounded,
                    title: "ترجمة إلى نص",
                    subtitle: "استخدم الكاميرا لترجمة الإشارات",
                    gradient: AppColors.cyanGradient,
                    glowColor: AppColors.neonCyan,
                    onTap: _goToCamera,
                  ),
                  const SizedBox(height: 16),
                  _buildFeatureButton(
                    icon: Icons.sports_esports_rounded,
                    title: "اختبر مهاراتك",
                    subtitle: "تحدَّ نفسك في التعرف على لغة الإشارة",
                    gradient: const LinearGradient(colors: [Color(0xFFA855F7), Color(0xFF6366F1)]),
                    glowColor: const Color(0xFFA855F7),
                    onTap: _goToQuiz,
                  ),

                  const SizedBox(height: 32),

                  // ── Stats Row ───────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          icon: Icons.auto_awesome_rounded,
                          label: "إشارة متاحة",
                          value: "100+",
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          icon: Icons.speed_rounded,
                          label: "دقة النموذج",
                          value: "97%",
                          color: AppColors.emerald,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          icon: Icons.text_fields_rounded,
                          label: "ترجمة جمل",
                          value: "جديد",
                          color: AppColors.neonCyan,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // ── AI Chatbot FAB Overlay ──────────────────────────────
          const AIChatbotOverlay(),
          // ── Voice Assistant Overlay ─────────────────────────────
          const VoiceAssistantOverlay(),
        ],
      ),

      // ── Floating Curved Bottom Navigation Bar ───────────────
      bottomNavigationBar: _buildFloatingNavBar(),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  Feature Button — Glassmorphic gradient action card
  // ═══════════════════════════════════════════════════════════════
  Widget _buildFeatureButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required LinearGradient gradient,
    required Color glowColor,
    required VoidCallback onTap,
  }) {
    return SparkleButton(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: glowColor.withOpacity(0.25),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: glowColor.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            // Icon with gradient background
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: glowColor.withOpacity(0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    title,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(Icons.arrow_back_ios_rounded,
                color: Colors.white.withOpacity(0.3), size: 18),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  Stat Card — Small glassmorphic info card
  // ═══════════════════════════════════════════════════════════════
  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: AppColors.glassCard(borderRadius: 18),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  Floating Curved Bottom Navigation Bar
  // ═══════════════════════════════════════════════════════════════
  Widget _buildFloatingNavBar() {
    final items = [
      _NavItem(Icons.home_rounded, "الرئيسية"),
      _NavItem(Icons.videocam_rounded, "الكاميرا"),
      _NavItem(Icons.settings_rounded, "الإعدادات"),
      _NavItem(Icons.person_rounded, "الملف"),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.15),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (i) {
              final isActive = i == _navIndex;
              return GestureDetector(
                onTap: () => _onNavTapped(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.symmetric(
                    horizontal: isActive ? 20 : 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.primary.withOpacity(0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        child: Icon(
                          items[i].icon,
                          color: isActive
                              ? AppColors.primary
                              : Colors.white.withOpacity(0.4),
                          size: isActive ? 26 : 22,
                        ),
                      ),
                      if (isActive) ...[
                        const SizedBox(height: 4),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.6),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}

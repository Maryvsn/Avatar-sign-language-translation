import 'dart:ui';
import 'package:flutter/material.dart';
import 'theme.dart';
import 'bubble_screen.dart';
import 'database_helper.dart';
import 'user_session.dart';
import 'home_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _showPass = false;
  bool _showConfirm = false;
  bool _isLoading = false;
  String _passStrength = '';
  Color _strengthColor = Colors.transparent;
  double _strengthValue = 0;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _checkStrength(String v) {
    if (v.isEmpty) {
      setState(() {
        _passStrength = '';
        _strengthValue = 0;
      });
      return;
    }
    bool up = v.contains(RegExp(r'[A-Z]'));
    bool lo = v.contains(RegExp(r'[a-z]'));
    bool dig = v.contains(RegExp(r'[0-9]'));
    bool sp = v.contains(RegExp(r'[!@#\$%^&*]'));
    bool len = v.length >= 8;
    int score = [up, lo, dig, sp, len].where((e) => e).length;
    setState(() {
      if (score <= 2) {
        _passStrength = 'ضعيف';
        _strengthColor = Colors.red;
        _strengthValue = 0.33;
      } else if (score <= 4) {
        _passStrength = 'متوسط';
        _strengthColor = const Color(0xFF6366F1); // indigo for medium
        _strengthValue = 0.66;
      } else {
        _passStrength = 'قوي 💪';
        _strengthColor = const Color(0xFF06B6D4); // Neon Cyan for strong
        _strengthValue = 1.0;
      }
    });
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final result = await DatabaseHelper.instance.registerUser(
      fullName: _nameCtrl.text,
      email: _emailCtrl.text,
      password: _passCtrl.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success']) {
      final login = await DatabaseHelper.instance
          .loginUser(email: _emailCtrl.text, password: _passCtrl.text);
      if (login['success']) await UserSession.saveSession(login['user']);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('تم إنشاء الحساب بنجاح 🎉'),
        backgroundColor: Colors.green.shade600,
      ));
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (_) => const HomeScreen()), (r) => false);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['message']),
        backgroundColor: Colors.red.shade600,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // ── Subtle radial indigo glow at the top ──
          Positioned(
            top: -120,
            left: 0,
            right: 0,
            child: Container(
              height: 400,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 1.2,
                  colors: [
                    const Color(0xFF6366F1).withOpacity(0.25),
                    const Color(0xFF6366F1).withOpacity(0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ── Main content ──
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    const SizedBox(height: 40),

                    // سهم الرجوع في صفحة الساين
                    Align(
                      alignment: Alignment.topLeft, // عشان يظهر فوق على الشمال
                      child: IconButton(
                        icon: const Icon(
                          Icons
                              .arrow_back_ios_new_rounded, // نفس شكل السهم المودرن
                          color: Colors.white70,
                          size: 28,
                        ),
                        onPressed: () {
                          // هيرجعك للوجين أو للشاشة اللي قبلها
                          Navigator.pop(context);
                        },
                      ),
                    ),

                    const SizedBox(
                        height: 10), // مسافة بسيطة قبل الأيقونة أو العنوان
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6366F1).withOpacity(0.5),
                            blurRadius: 30,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.person_add_rounded,
                          color: Colors.white, size: 34),
                    ),

                    const SizedBox(height: 20),

                    ShaderMask(
                      shaderCallback: (b) => const LinearGradient(
                        colors: [AppColors.primary, AppColors.accent],
                      ).createShader(b),
                      child: const Text(
                        "SIGN SENSE",
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                    ),

                    const SizedBox(height: 6),

                    const Text(
                      "Create Account",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Full Name
                    _field(
                        ctrl: _nameCtrl,
                        label: "Full Name",
                        icon: Icons.person_outline,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'ادخل اسمك';
                          if (v.trim().length < 3)
                            return 'الاسم لازم 3 حروف على الأقل';
                          return null;
                        }),

                    const SizedBox(height: 16),

                    // Email
                    _field(
                        ctrl: _emailCtrl,
                        label: "Email Address",
                        icon: Icons.email_outlined,
                        keyboard: TextInputType.emailAddress,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty)
                            return 'ادخل الإيميل';
                          if (!RegExp(
                                  r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
                              .hasMatch(v.trim()))
                            return 'صيغة الإيميل غير صحيحة';
                          return null;
                        }),

                    const SizedBox(height: 16),

                    // Password
                    _field(
                      ctrl: _passCtrl,
                      label: "Password",
                      icon: Icons.lock_outline,
                      obscure: !_showPass,
                      onChanged: _checkStrength,
                      suffix: IconButton(
                        icon: Icon(
                            _showPass ? Icons.visibility : Icons.visibility_off,
                            color: Colors.white54),
                        onPressed: () => setState(() => _showPass = !_showPass),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'ادخل الباسورد';
                        if (v.length < 8) return 'لازم 8 أحرف على الأقل';
                        if (!v.contains(RegExp(r'[A-Z]')))
                          return 'لازم حرف كبير (A-Z)';
                        if (!v.contains(RegExp(r'[a-z]')))
                          return 'لازم حرف صغير (a-z)';
                        if (!v.contains(RegExp(r'[0-9]'))) return 'لازم رقم';
                        return null;
                      },
                    ),

                    // Strength bar
                    if (_passStrength.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, left: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Text('قوة الباسورد: ',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.white54)),
                              Text(_passStrength,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _strengthColor)),
                            ]),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: _strengthValue,
                                color: _strengthColor,
                                backgroundColor:
                                    Colors.white.withOpacity(0.1),
                                minHeight: 5,
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 16),

                    // Confirm Password
                    _field(
                      ctrl: _confirmCtrl,
                      label: "Confirm Password",
                      icon: Icons.lock_outline,
                      obscure: !_showConfirm,
                      suffix: IconButton(
                        icon: Icon(
                            _showConfirm
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: Colors.white54),
                        onPressed: () =>
                            setState(() => _showConfirm = !_showConfirm),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'أكّد الباسورد';
                        if (v != _passCtrl.text) return 'الباسورد مش متطابق';
                        return null;
                      },
                    ),

                    const SizedBox(height: 32),

                    // Sign Up Button — gradient indigo→purple with glow
                    SparkleButton(
                      onTap: _isLoading ? null : _signUp,
                      child: Container(
                        width: double.infinity,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6366F1).withOpacity(0.45),
                              blurRadius: 24,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Center(
                          child: _isLoading
                              ? const CircularProgressIndicator(
                                  color: Colors.white)
                              : const Text(
                                  "Sign Up",
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboard,
    void Function(String)? onChanged,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF6366F1).withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withOpacity(0.08),
            blurRadius: 24,
          ),
        ],
      ),
      child: TextFormField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: keyboard,
        onChanged: onChanged,
        validator: validator,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white38),
          prefixIcon: Icon(icon, color: Colors.white54),
          suffixIcon: suffix,
          filled: false,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide(
              color: const Color(0xFF6366F1).withOpacity(0.6),
              width: 1.5,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Colors.red),
          ),
          errorStyle: TextStyle(color: Colors.red.shade300),
        ),
      ),
    );
  }
}

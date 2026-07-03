import 'package:flutter/material.dart';
import 'theme.dart';
import 'bubble_screen.dart';

class SupportScreen extends StatefulWidget {
  final bool isDarkMode;
  const SupportScreen({super.key, this.isDarkMode = false});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _submitted = false;
  bool _sending = false;
  int _expandedFaq = -1;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Color get _bg =>
      widget.isDarkMode ? AppColors.darkBg : AppColors.scaffoldLight;
  Color get _card =>
      widget.isDarkMode ? AppColors.darkCard : Colors.white;
  Color get _txt => widget.isDarkMode ? Colors.white : AppColors.black;
  Color get _sub =>
      widget.isDarkMode ? Colors.white54 : Colors.grey.shade500;

  static const _faqs = [
    {
      'q': 'How does sign language recognition work?',
      'a':
          'Sign Sense uses your camera to detect hand gestures in real time and translates them into text using a machine learning model trained on sign language data.',
    },
    {
      'q': 'Is my data stored on the device?',
      'a':
          'Yes. All your personal data (name, email, password) is stored locally on your device using SQLite. Nothing is sent to external servers.',
    },
    {
      'q': 'Can I use the app without an internet connection?',
      'a':
          'Yes! Sign Sense works fully offline. The ML model runs on-device so no internet is needed for recognition.',
    },
    {
      'q': 'How do I change my account information?',
      'a':
          'Go to Profile → Edit Profile to update your name and email. You can also change your password from Profile → Change Password.',
    },
    {
      'q': 'The camera is not working. What should I do?',
      'a':
          'Make sure camera permissions are granted in your device settings. On Windows, camera support requires additional setup.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor:
            widget.isDarkMode ? AppColors.darkSurface : Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: widget.isDarkMode ? Colors.white : AppColors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: ShaderMask(
          shaderCallback: (b) => const LinearGradient(
            colors: [AppColors.primary, AppColors.accent],
          ).createShader(b),
          child: const Text('Support',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 20)),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Header ────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primaryLight, AppColors.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(children: [
              const Icon(Icons.headset_mic_rounded,
                  color: Colors.white, size: 40),
              const SizedBox(height: 10),
              const Text('How can we help?',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('We usually respond within 24 hours',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.75), fontSize: 13)),
            ]),
          ),

          const SizedBox(height: 28),

          // ── Contact Buttons ────────────────────────────────────────
          _sectionLabel('Contact Us'),
          const SizedBox(height: 10),

          Row(children: [
            Expanded(
              child: _contactCard(
                icon: Icons.email_rounded,
                label: 'Email',
                sub: 'support@signsense.app',
                color: Colors.blue,
                onTap: () {},
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _contactCard(
                icon: Icons.chat_bubble_rounded,
                label: 'Live Chat',
                sub: 'Available 9am–5pm',
                color: Colors.teal,
                onTap: () {},
              ),
            ),
          ]),

          const SizedBox(height: 28),

          // ── FAQ ───────────────────────────────────────────────────
          _sectionLabel('Frequently Asked Questions'),
          const SizedBox(height: 10),

          Container(
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: List.generate(_faqs.length, (i) {
                final faq = _faqs[i];
                final isOpen = _expandedFaq == i;
                return Column(children: [
                  RippleTap(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () =>
                        setState(() => _expandedFaq = isOpen ? -1 : i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            isOpen
                                ? Icons.remove_rounded
                                : Icons.add_rounded,
                            color: AppColors.primary,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(faq['q']!,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _txt,
                                  fontSize: 13)),
                        ),
                      ]),
                    ),
                  ),
                  if (isOpen)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(52, 0, 16, 14),
                      child: Text(faq['a']!,
                          style: TextStyle(color: _sub, fontSize: 13, height: 1.5)),
                    ),
                  if (i < _faqs.length - 1)
                    Divider(
                        height: 1,
                        color: widget.isDarkMode
                            ? Colors.white10
                            : Colors.grey.shade100,
                        indent: 16),
                ]);
              }),
            ),
          ),

          const SizedBox(height: 28),

          // ── Contact Form ──────────────────────────────────────────
          _sectionLabel('Send a Message'),
          const SizedBox(height: 10),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: _submitted
                ? Container(
                    key: const ValueKey('success'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(children: [
                      const Icon(Icons.check_circle_rounded,
                          color: Colors.green, size: 56),
                      const SizedBox(height: 12),
                      Text('Message Sent!',
                          style: TextStyle(
                              color: _txt,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text("We'll get back to you soon.",
                          style: TextStyle(color: _sub)),
                    ]),
                  )
                : Container(
                    key: const ValueKey('form'),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.06),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(children: [
                        _formField(
                          ctrl: _subjectCtrl,
                          label: 'Subject',
                          icon: Icons.subject_rounded,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Please enter a subject'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        _formField(
                          ctrl: _messageCtrl,
                          label: 'Message',
                          icon: Icons.message_rounded,
                          maxLines: 5,
                          validator: (v) => (v == null || v.trim().length < 10)
                              ? 'Message must be at least 10 characters'
                              : null,
                        ),
                        const SizedBox(height: 20),
                        RippleTap(
                          onTap: _sending
                              ? null
                              : () async {
                                  if (!_formKey.currentState!.validate())
                                    return;
                                  setState(() => _sending = true);
                                  await Future.delayed(
                                      const Duration(seconds: 1));
                                  setState(() {
                                    _sending = false;
                                    _submitted = true;
                                  });
                                },
                          child: Container(
                            width: double.infinity,
                            height: 52,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [
                                AppColors.primaryLight,
                                AppColors.primary
                              ]),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      AppColors.primary.withOpacity(0.35),
                                  blurRadius: 14,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Center(
                              child: _sending
                                  ? const CircularProgressIndicator(
                                      color: Colors.white)
                                  : const Text('Send Message',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
          ),

          const SizedBox(height: 30),
        ]),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(label.toUpperCase(),
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _sub,
            letterSpacing: 1));
  }

  Widget _contactCard({
    required IconData icon,
    required String label,
    required String sub,
    required Color color,
    required VoidCallback onTap,
  }) {
    return RippleTap(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 10),
          Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: _txt, fontSize: 14)),
          const SizedBox(height: 3),
          Text(sub, style: TextStyle(color: _sub, fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _formField({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      validator: validator,
      style: TextStyle(color: _txt),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: _sub),
        prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
        filled: true,
        fillColor: widget.isDarkMode ? AppColors.darkSurface : AppColors.lightGrey,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: AppColors.primary, width: 2)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.red)),
      ),
    );
  }
}

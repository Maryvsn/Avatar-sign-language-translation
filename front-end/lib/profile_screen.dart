import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme.dart';
import 'bubble_screen.dart';
import 'database_helper.dart';
import 'user_session.dart';
import 'welcome_screen.dart';
import 'support_screen.dart';

class ProfileScreen extends StatefulWidget {
  final bool isDarkMode;
  const ProfileScreen({super.key, this.isDarkMode = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  String _userName = '';
  String _userEmail = '';
  int? _userId;
  bool _isLoading = true;
  late bool _dark;
  late AnimationController _avatarCtrl;
  late Animation<double> _avatarAnim;

  // ── Glassmorphism constants ─────────────────────────────────────
  static const _indigo = Color(0xFF6366F1);
  static const _neonCyan = Color(0xFF06B6D4);

  @override
  void initState() {
    super.initState();
    _dark = widget.isDarkMode;
    _avatarCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _avatarAnim =
        CurvedAnimation(parent: _avatarCtrl, curve: Curves.elasticOut);
    _loadUser();
  }

  @override
  void dispose() {
    _avatarCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final name = await UserSession.getUserName();
    final email = await UserSession.getUserEmail();
    final id = await UserSession.getUserId();
    setState(() {
      _userName = name;
      _userEmail = email;
      _userId = id;
      _isLoading = false;
    });
    _avatarCtrl.forward();
  }

  void _snack(String msg, bool ok) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? Colors.green.shade600 : Colors.red.shade600,
    ));
  }

  // ── Edit Info ──────────────────────────────────────────────────────────
  void _editInfo() {
    final nameCtrl = TextEditingController(text: _userName);
    final emailCtrl = TextEditingController(text: _userEmail);
    final key = GlobalKey<FormState>();
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => _styledDialog(
          ctx: ctx,
          title: 'Edit Profile',
          icon: Icons.edit_rounded,
          content: Form(
            key: key,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _dialogField(ctrl: nameCtrl, label: 'Full Name',
                  icon: Icons.person_outline, validator: (v) {
                if (v == null || v.trim().length < 3)
                  return 'At least 3 characters';
                return null;
              }),
              const SizedBox(height: 14),
              _dialogField(ctrl: emailCtrl, label: 'Email',
                  icon: Icons.email_outlined,
                  keyboard: TextInputType.emailAddress, validator: (v) {
                if (v == null ||
                    !RegExp(r'^[\w.]+@[\w]+\.[a-z]{2,}$').hasMatch(v.trim()))
                  return 'Invalid email';
                return null;
              }),
            ]),
          ),
          saving: saving,
          confirmLabel: 'Save',
          onConfirm: () async {
            if (!key.currentState!.validate()) return;
            set(() => saving = true);
            final res = await DatabaseHelper.instance.updateUserInfo(
                id: _userId!, fullName: nameCtrl.text, email: emailCtrl.text);
            if (!mounted) return;
            set(() => saving = false);
            if (res['success']) {
              await UserSession.updateLocalInfo(
                  fullName: nameCtrl.text.trim(),
                  email: emailCtrl.text.trim().toLowerCase());
              setState(() {
                _userName = nameCtrl.text.trim();
                _userEmail = emailCtrl.text.trim().toLowerCase();
              });
              Navigator.pop(ctx);
              _snack('Profile updated ✅', true);
            } else {
              _snack(res['message'], false);
            }
          },
        ),
      ),
    );
  }

  // ── Change Password ────────────────────────────────────────────────────
  void _changePassword() {
    final curCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final conCtrl = TextEditingController();
    final key = GlobalKey<FormState>();
    bool saving = false;
    bool sCur = false, sNew = false, sCon = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => _styledDialog(
          ctx: ctx,
          title: 'Change Password',
          icon: Icons.lock_rounded,
          content: Form(
            key: key,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _passField(ctrl: curCtrl, label: 'Current Password',
                  show: sCur, toggle: () => set(() => sCur = !sCur),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Required' : null),
              const SizedBox(height: 12),
              _passField(ctrl: newCtrl, label: 'New Password',
                  show: sNew, toggle: () => set(() => sNew = !sNew),
                  validator: (v) {
                if (v == null || v.length < 8) return 'Min 8 characters';
                if (!v.contains(RegExp(r'[A-Z]'))) return 'Add uppercase letter';
                if (!v.contains(RegExp(r'[0-9]'))) return 'Add a number';
                return null;
              }),
              const SizedBox(height: 12),
              _passField(ctrl: conCtrl, label: 'Confirm New Password',
                  show: sCon, toggle: () => set(() => sCon = !sCon),
                  validator: (v) =>
                      v != newCtrl.text ? 'Passwords do not match' : null),
            ]),
          ),
          saving: saving,
          confirmLabel: 'Change',
          onConfirm: () async {
            if (!key.currentState!.validate()) return;
            set(() => saving = true);
            final res = await DatabaseHelper.instance.changePassword(
                id: _userId!,
                currentPassword: curCtrl.text,
                newPassword: newCtrl.text);
            if (!mounted) return;
            set(() => saving = false);
            if (res['success']) {
              Navigator.pop(ctx);
              _snack('Password changed ✅', true);
            } else {
              _snack(res['message'], false);
            }
          },
        ),
      ),
    );
  }

  // ── Rate App ───────────────────────────────────────────────────────────
  void _rateApp() {
    int stars = 0;
    final commentCtrl = TextEditingController();
    bool submitted = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: AppColors.darkSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: _indigo.withOpacity(0.3), width: 1),
          ),
          title: Column(children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                    colors: [AppColors.primaryLight, AppColors.primary]),
                boxShadow: [
                  BoxShadow(
                    color: _indigo.withOpacity(0.4),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: const Icon(Icons.star_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(height: 10),
            const Text('Rate AI Hand 🤟',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
          ]),
          content: submitted
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle_rounded,
                      color: _neonCyan, size: 50),
                  const SizedBox(height: 10),
                  const Text('Thank you for your feedback! 🎉',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white)),
                ])
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('How would you rate your experience?',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 16),
                  // Stars
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      return RippleTap(
                        borderRadius: BorderRadius.circular(50),
                        onTap: () => set(() => stars = i + 1),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            i < stars
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: i < stars
                                ? Colors.amber
                                : Colors.white.withOpacity(0.3),
                            size: 38,
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: commentCtrl,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Leave a comment (optional)',
                      hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: _indigo.withOpacity(0.2),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: _indigo.withOpacity(0.2),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                            color: AppColors.primary, width: 2),
                      ),
                    ),
                  ),
                ]),
          actions: submitted
              ? [
                  SizedBox(
                    width: double.infinity,
                    child: RippleTap(
                      onTap: () => Navigator.pop(ctx),
                      child: _gradBtn('Close'),
                    ),
                  )
                ]
              : [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel',
                        style: TextStyle(color: Colors.white54)),
                  ),
                  RippleTap(
                    onTap: () {
                      if (stars == 0) {
                        _snack('Please select a rating', false);
                        return;
                      }
                      set(() => submitted = true);
                    },
                    child: _gradBtn('Submit'),
                  ),
                ],
        ),
      ),
    );
  }

  // ── Logout ─────────────────────────────────────────────────────────────
  void _logout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.red.withOpacity(0.4), width: 1),
        ),
        title: Column(children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red.withOpacity(0.15),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.3),
                  blurRadius: 20,
                ),
              ],
            ),
            child: const Icon(Icons.logout_rounded,
                color: Colors.redAccent, size: 28),
          ),
          const SizedBox(height: 10),
          const Text('Sign Out',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold)),
        ]),
        content: const Text('Are you sure you want to sign out?',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          RippleTap(
            onTap: () async {
              await UserSession.logout();
              if (!mounted) return;
              Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                  (_) => false);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.4),
                      blurRadius: 12,
                    ),
                  ]),
              child: const Text('Sign Out',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: ShaderMask(
          shaderCallback: (b) => const LinearGradient(
            colors: [AppColors.primary, AppColors.accent],
          ).createShader(b),
          child: const Text('Profile',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 20)),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                // ── Avatar ──────────────────────────────────────────
                ScaleTransition(
                  scale: _avatarAnim,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      // Glowing indigo ring
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [_indigo, AppColors.accent],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _indigo.withOpacity(0.5),
                              blurRadius: 30,
                              spreadRadius: 2,
                            ),
                            BoxShadow(
                              color: AppColors.accent.withOpacity(0.3),
                              blurRadius: 40,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(4),
                        child: CircleAvatar(
                          radius: 52,
                          backgroundColor: AppColors.darkSurface,
                          child: Text(
                            _userName.isNotEmpty
                                ? _userName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                          ),
                        ),
                      ),
                      // Edit button
                      RippleTap(
                        borderRadius: BorderRadius.circular(50),
                        onTap: _editInfo,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _indigo,
                            border: Border.all(
                                color: AppColors.background, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: _indigo.withOpacity(0.5),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.edit_rounded,
                              color: Colors.white, size: 14),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                Text(_userName,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                Text(_userEmail,
                    style: const TextStyle(color: Colors.white70, fontSize: 14)),

                const SizedBox(height: 28),

                // ── Info Card ────────────────────────────────────────
                _section('Account Info', [
                  _infoRow(Icons.person_outline, 'Name', _userName),
                  _divider(),
                  _infoRow(Icons.email_outlined, 'Email', _userEmail),
                ]),

                const SizedBox(height: 18),

                // ── Actions Card ─────────────────────────────────────
                _section('Account Settings', [
                  _actionRow(
                    icon: Icons.edit_outlined,
                    label: 'Edit Profile',
                    color: _indigo,
                    onTap: _editInfo,
                  ),
                  _divider(),
                  _actionRow(
                    icon: Icons.lock_outline_rounded,
                    label: 'Change Password',
                    color: Colors.orange,
                    onTap: _changePassword,
                  ),
                ]),

                const SizedBox(height: 18),

                // ── More Card ─────────────────────────────────────────
                _section('More', [
                  _actionRow(
                    icon: Icons.headset_mic_rounded,
                    label: 'Support',
                    color: _neonCyan,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              SupportScreen(isDarkMode: _dark)),
                    ),
                  ),
                  _divider(),
                  _actionRow(
                    icon: Icons.star_rounded,
                    label: 'Rate the App',
                    color: Colors.amber.shade700,
                    onTap: _rateApp,
                  ),
                  _divider(),
                  _actionRow(
                    icon: Icons.logout_rounded,
                    label: 'Sign Out',
                    color: Colors.red,
                    onTap: _logout,
                  ),
                ]),

                const SizedBox(height: 30),

                // ── Footer ───────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ShaderMask(
                      shaderCallback: (b) => const LinearGradient(
                        colors: [AppColors.primary, AppColors.accent],
                      ).createShader(b),
                      child: const Text('AI HAND ',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.white,
                              letterSpacing: 2)),
                    ),
                    const Text('🤟',
                        style: TextStyle(
                            fontSize: 15,
                            color: Colors.amberAccent,
                            fontFamilyFallback: [
                              'Segoe UI Emoji',
                              'Apple Color Emoji'
                            ])),
                  ],
                ),
                const SizedBox(height: 6),
                const Text('v1.0.0',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 20),
              ]),
            ),
    );
  }

  // ── Reusable widgets ───────────────────────────────────────────────────
  Widget _section(String title, List<Widget> children) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: _indigo,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(title.toUpperCase(),
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 1)),
          ],
        ),
      ),
      Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _indigo.withOpacity(0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: _indigo.withOpacity(0.08),
              blurRadius: 24,
            ),
          ],
        ),
        child: Column(children: children),
      ),
    ]);
  }

  Widget _divider() => Divider(
      height: 1,
      color: Colors.white.withOpacity(0.08),
      indent: 56);

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _indigo.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _indigo.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Icon(icon, color: _indigo, size: 18),
        ),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.white54)),
          Text(value,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
        ]),
      ]),
    );
  }

  Widget _actionRow({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return RippleTap(
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: color.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w600))),
          const Icon(Icons.chevron_right_rounded,
              color: Colors.white54, size: 20),
        ]),
      ),
    );
  }

  Widget _gradBtn(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [_indigo, AppColors.accent]),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: _indigo.withOpacity(0.4),
            blurRadius: 12,
          ),
        ],
      ),
      child: Text(label,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }

  Widget _styledDialog({
    required BuildContext ctx,
    required String title,
    required IconData icon,
    required Widget content,
    required bool saving,
    required String confirmLabel,
    required VoidCallback onConfirm,
  }) {
    return AlertDialog(
      backgroundColor: AppColors.darkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: _indigo.withOpacity(0.3), width: 1),
      ),
      title: Column(children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
                colors: [AppColors.primaryLight, AppColors.primary]),
            boxShadow: [
              BoxShadow(
                color: _indigo.withOpacity(0.4),
                blurRadius: 20,
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 26),
        ),
        const SizedBox(height: 10),
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
      ]),
      content: content,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
        RippleTap(
          onTap: saving ? null : onConfirm,
          child: saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      color: AppColors.primary, strokeWidth: 2))
              : _gradBtn(confirmLabel),
        ),
      ],
    );
  }

  Widget _dialogField({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    TextInputType? keyboard,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboard,
      validator: validator,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Icon(icon, color: _indigo, size: 20),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: _indigo.withOpacity(0.2))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: _indigo.withOpacity(0.2))),
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

  Widget _passField({
    required TextEditingController ctrl,
    required String label,
    required bool show,
    required VoidCallback toggle,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: ctrl,
      obscureText: !show,
      validator: validator,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        prefixIcon:
            Icon(Icons.lock_outline, color: _indigo, size: 20),
        suffixIcon: IconButton(
          icon: Icon(show ? Icons.visibility : Icons.visibility_off,
              color: Colors.white54, size: 20),
          onPressed: toggle,
        ),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: _indigo.withOpacity(0.2))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: _indigo.withOpacity(0.2))),
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

import 'package:flutter/material.dart';
import 'theme.dart';
import 'bubble_screen.dart';
import 'user_session.dart';
import 'welcome_screen.dart';

class SettingsScreen extends StatefulWidget {
  final Function(bool)? onThemeChanged;
  const SettingsScreen({super.key, this.onThemeChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isDark = false;
  bool _isLoading = true;
  bool _notificationsOn = true;
  String _language = 'English';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dark = await UserSession.getDarkMode();
    setState(() { _isDark = dark; _isLoading = false; });
  }

  Future<void> _toggleDark(bool v) async {
    await UserSession.setDarkMode(v);
    setState(() => _isDark = v);
    widget.onThemeChanged?.call(v);
  }

  // ── All colors now locked to dark glassmorphism ─────────────────
  static const _indigo = Color(0xFF6366F1);
  static const _neonCyan = Color(0xFF06B6D4);

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
            child: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 28),
          ),
          const SizedBox(height: 10),
          const Text('Sign Out',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.4),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: const Text('Sign Out',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

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
          child: const Text('Settings',
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
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                // ── Appearance ───────────────────────────────────────
                _label('Appearance'),
                const SizedBox(height: 10),
                _glassCard(children: [
                  _switchTile(
                    icon: _isDark
                        ? Icons.dark_mode_rounded
                        : Icons.light_mode_rounded,
                    iconColor: _isDark ? Colors.amber : _indigo,
                    title: 'Dark Mode',
                    subtitle: _isDark ? 'Dark theme active' : 'Light theme active',
                    value: _isDark,
                    onChanged: _toggleDark,
                  ),
                ]),

                const SizedBox(height: 20),

                // ── Notifications ────────────────────────────────────
                _label('Notifications'),
                const SizedBox(height: 10),
                _glassCard(children: [
                  _switchTile(
                    icon: Icons.notifications_rounded,
                    iconColor: Colors.orange,
                    title: 'Push Notifications',
                    subtitle: _notificationsOn ? 'Enabled' : 'Disabled',
                    value: _notificationsOn,
                    onChanged: (v) => setState(() => _notificationsOn = v),
                  ),
                ]),

                const SizedBox(height: 20),

                // ── Language ─────────────────────────────────────────
                _label('Language'),
                const SizedBox(height: 10),
                _glassCard(children: [
                  RippleTap(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _showLangPicker(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _neonCyan.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _neonCyan.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: const Icon(Icons.language_rounded,
                              color: _neonCyan, size: 18),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('App Language',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white)),
                                Text(_language,
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 12)),
                              ]),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            color: Colors.white54, size: 20),
                      ]),
                    ),
                  ),
                ]),

                const SizedBox(height: 20),

                // ── About ────────────────────────────────────────────
                _label('About'),
                const SizedBox(height: 10),
                _glassCard(children: [
                  _infoTile(
                    icon: Icons.info_outline_rounded,
                    iconColor: _indigo,
                    title: 'Version',
                    trailing: '1.0.0',
                  ),
                  _divider(),
                  _infoTile(
                    icon: Icons.code_rounded,
                    iconColor: _indigo,
                    title: 'App Name',
                    trailing: 'AI Hand',
                  ),
                  _divider(),
                  _infoTile(
                    icon: Icons.security_rounded,
                    iconColor: const Color(0xFF10B981),
                    title: 'Privacy Policy',
                    trailing: '',
                    isLink: true,
                  ),
                ]),

                const SizedBox(height: 20),

                // ── Account ──────────────────────────────────────────
                _label('Account'),
                const SizedBox(height: 10),
                _signOutCard(),

                const SizedBox(height: 30),

                // ── Footer ───────────────────────────────────────────
                Center(
                  child: Column(children: [
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
                                  fontSize: 14,
                                  color: Colors.white,
                                  letterSpacing: 2)),
                        ),
                        const Text('🤟',
                            style: TextStyle(
                                fontSize: 14,
                                color: Colors.amberAccent,
                                fontFamilyFallback: [
                                  'Segoe UI Emoji',
                                  'Apple Color Emoji'
                                ])),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text('v1.0.0 • All rights reserved',
                        style: TextStyle(color: Colors.white54, fontSize: 11)),
                  ]),
                ),
                const SizedBox(height: 20),
              ]),
            ),
    );
  }

  // ── helpers ───────────────────────────────────────────────────────────
  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(left: 4),
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
            Text(t.toUpperCase(),
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 1)),
          ],
        ),
      );

  Widget _glassCard({required List<Widget> children}) => Container(
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
      );

  Widget _signOutCard() => Container(
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.red.withOpacity(0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.06),
              blurRadius: 24,
            ),
          ],
        ),
        child: RippleTap(
          borderRadius: BorderRadius.circular(20),
          onTap: _logout,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.red.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: const Icon(Icons.logout_rounded,
                    color: Colors.redAccent, size: 18),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text('Sign Out',
                    style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w600)),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.white54, size: 20),
            ]),
          ),
        ),
      );

  Widget _divider() => Divider(
      height: 1,
      color: Colors.white.withOpacity(0.08),
      indent: 16);

  Widget _switchTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required void Function(bool) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: SwitchListTile(
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: iconColor.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
        subtitle:
            Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        value: value,
        activeColor: _indigo,
        onChanged: onChanged,
      ),
    );
  }

  Widget _infoTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String trailing,
    bool isLink = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: iconColor.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: Colors.white))),
        if (isLink)
          const Icon(Icons.open_in_new_rounded, color: Colors.white54, size: 16)
        else
          Text(trailing, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ]),
    );
  }

  void _showLangPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: _indigo.withOpacity(0.3), width: 1),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Select Language',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ...['English', 'Arabic', 'French', 'Spanish'].map((lang) {
            final selected = _language == lang;
            return RippleTap(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() => _language = lang);
                Navigator.pop(context);
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: selected
                      ? _indigo.withOpacity(0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? _indigo.withOpacity(0.5)
                        : Colors.white.withOpacity(0.08),
                  ),
                ),
                child: Row(children: [
                  Text(lang,
                      style: TextStyle(
                          color: selected ? _indigo : Colors.white,
                          fontWeight: selected
                              ? FontWeight.bold
                              : FontWeight.normal)),
                  const Spacer(),
                  if (selected)
                    Icon(Icons.check_rounded,
                        color: _neonCyan, size: 18),
                ]),
              ),
            );
          }),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

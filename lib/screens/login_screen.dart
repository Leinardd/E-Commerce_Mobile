import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../services/address_service.dart';
import '../services/auth_service.dart';
import 'email_verification_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  bool isLogin = true;
  bool loading = false;

  // Login
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();

  // Signup — personal
  final firstCtrl = TextEditingController();
  final lastCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final signupEmailCtrl = TextEditingController();
  final signupPassCtrl = TextEditingController();
  final confirmPassCtrl = TextEditingController();

  // Signup — address
  final houseNumberCtrl = TextEditingController();
  final streetNameCtrl = TextEditingController();
  Map<String, String>? _selectedLocation;

  // Password visibility
  bool _obscureLogin = true;
  bool _obscureSignupPass = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.8, curve: Curves.easeOut),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.8, curve: Curves.easeOutCubic),
    ));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    emailCtrl.dispose();
    passCtrl.dispose();
    firstCtrl.dispose();
    lastCtrl.dispose();
    phoneCtrl.dispose();
    signupEmailCtrl.dispose();
    signupPassCtrl.dispose();
    confirmPassCtrl.dispose();
    houseNumberCtrl.dispose();
    streetNameCtrl.dispose();
    super.dispose();
  }

  void toggle(bool login) => setState(() => isLogin = login);

  void _goBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacementNamed('/');
    }
  }

  Future<void> login() async {
    if (emailCtrl.text.isEmpty || passCtrl.text.isEmpty) {
      _showSnack('Please enter email and password');
      return;
    }
    setState(() => loading = true);

    final error = await AuthService.login(emailCtrl.text, passCtrl.text);

    if (!mounted) return;
    setState(() => loading = false);

    if (error != null) {
      _showSnack(error);
      return;
    }
    Navigator.of(context).pushReplacementNamed('/auth-loading');
  }

  Future<void> signup() async {
    if (firstCtrl.text.isEmpty ||
        lastCtrl.text.isEmpty ||
        signupEmailCtrl.text.isEmpty ||
        phoneCtrl.text.isEmpty ||
        signupPassCtrl.text.isEmpty) {
      _showSnack('Please fill all required fields');
      return;
    }
    if (!_emailPattern.hasMatch(signupEmailCtrl.text.trim())) {
      _showSnack('Enter a valid email address');
      return;
    }
    final phone = phoneCtrl.text.trim();
    if (!RegExp(r'^\d+$').hasMatch(phone)) {
      _showSnack('Phone number must contain digits only');
      return;
    }
    if (phone.length > 12) {
      _showSnack('Phone number must not exceed 12 digits');
      return;
    }
    if (signupPassCtrl.text != confirmPassCtrl.text) {
      _showSnack('Passwords do not match');
      return;
    }

    setState(() => loading = true);

    final error = await AuthService.signUp(
      email: signupEmailCtrl.text,
      password: signupPassCtrl.text,
      firstName: firstCtrl.text,
      lastName: lastCtrl.text,
      phone: phoneCtrl.text,
    );

    if (!mounted) return;

    // Build and persist the address before any early return so it survives
    // the email-verification redirect and is available at checkout.
    final addressMap = {
      'houseNumber': houseNumberCtrl.text.trim(),
      'streetName': streetNameCtrl.text.trim(),
      'barangay': _selectedLocation?['barangay'] ?? '',
      'city': _selectedLocation?['city'] ?? '',
      'province': _selectedLocation?['province'] ?? '',
      'region': _selectedLocation?['region'] ?? '',
      'barangayCode': _selectedLocation?['barangayCode'] ?? '',
      'cityCode': _selectedLocation?['cityCode'] ?? '',
      'provinceCode': _selectedLocation?['provinceCode'] ?? '',
      'regionCode': _selectedLocation?['regionCode'] ?? '',
    };
    await AddressService.saveAddress(addressMap);

    if (error == 'VERIFY_EMAIL') {
      setState(() => loading = false);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => EmailVerificationScreen(
            email: signupEmailCtrl.text.trim()),
      ));
      return;
    }

    if (error != null) {
      setState(() => loading = false);
      _showSnack(error);
      return;
    }

    // Session exists (no email confirmation required) — also sync to Supabase.
    await AddressService.saveToSupabase(addressMap);

    if (!mounted) return;

    for (final c in [
      firstCtrl, lastCtrl, phoneCtrl, signupEmailCtrl,
      signupPassCtrl, confirmPassCtrl, houseNumberCtrl, streetNameCtrl,
    ]) {
      c.clear();
    }
    setState(() {
      _selectedLocation = null;
      loading = false;
      isLogin = true;
    });
    _showSnack('Account created — please sign in');
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF0A0A0A),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _openLocationPicker() async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (_) => const _LocationPickerSheet(),
    );
    if (result != null && mounted) {
      setState(() => _selectedLocation = result);
    }
  }

  String get _locationDisplay {
    if (_selectedLocation == null) return '';
    return [
      _selectedLocation!['barangay'],
      _selectedLocation!['city'],
      _selectedLocation!['province'],
      _selectedLocation!['region'],
    ].where((s) => s != null && s.isNotEmpty).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 720;
    return Scaffold(
      backgroundColor:
          isMobile ? const Color(0xFF0A0A0A) : const Color(0xFFF4F3F0),
      resizeToAvoidBottomInset: true,
      body: FadeTransition(
        opacity: _fade,
        child: isMobile ? _mobileLayout() : _desktopLayout(),
      ),
    );
  }

  // ── Mobile ──────────────────────────────────────────────────────────────────

  Widget _mobileLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SafeArea(
          bottom: false,
          child: SlideTransition(
            position: _slide,
            child: _mobileBrandHeader(),
          ),
        ),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(28),
                topRight: Radius.circular(28),
              ),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(28),
                topRight: Radius.circular(28),
              ),
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.fromLTRB(28, 32, 28, 48),
                child: _mobileFormContent(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _mobileBrandHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 28, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: _goBack,
            child: const Icon(Icons.arrow_back_ios,
                color: Colors.white, size: 20),
          ),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          Text(
            'VARÓN',
            style: GoogleFonts.commissioner(
              fontSize: 20,
              fontWeight: FontWeight.w200,
              color: Colors.white,
              letterSpacing: 10,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'PREMIUM MINIMALIST FASHION',
            style: GoogleFonts.commissioner(
              fontSize: 7,
              color: Colors.white.withValues(alpha: 0.35),
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 36),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: Text(
              key: ValueKey(isLogin ? 'h_login' : 'h_signup'),
              isLogin ? 'Welcome\nback.' : 'Create your\naccount.',
              style: GoogleFonts.commissioner(
                fontSize: 34,
                fontWeight: FontWeight.w200,
                color: Colors.white,
                height: 1.2,
                letterSpacing: 0.5,
              ),
            ),
          ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileFormContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Pill tab switcher
        _mobilePillTabs(),
        const SizedBox(height: 32),

        // Animated form swap
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: isLogin
              ? Column(
                  key: const ValueKey('m_login'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ..._mobileLoginFields(),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const ForgotPasswordScreen()),
                        ),
                        child: Text(
                          'Forgot password?',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: const Color(0xFF888888),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  key: const ValueKey('m_signup'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _mobileSignupFields(),
                ),
        ),

        const SizedBox(height: 32),
        _mobileSubmitButton(),

        if (!isLogin) ...[
          const SizedBox(height: 16),
          Center(
            child: Text(
              'By signing up you agree to our Terms of Service\nand Privacy Policy.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: const Color(0xFFAAAAAA),
                height: 1.7,
              ),
            ),
          ),
        ],

        const SizedBox(height: 28),
        Center(
          child: GestureDetector(
            onTap: () => toggle(!isLogin),
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.inter(
                    fontSize: 13, color: const Color(0xFF888888)),
                children: [
                  TextSpan(
                    text: isLogin
                        ? "Don't have an account?  "
                        : 'Already have an account?  ',
                  ),
                  TextSpan(
                    text: isLogin ? 'Sign up' : 'Sign in',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0A0A0A),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _mobilePillTabs() {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0EE),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          // Sliding white pill
          AnimatedAlign(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            alignment:
                isLogin ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Tab labels
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => toggle(true),
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: Text(
                      'LOGIN',
                      style: GoogleFonts.commissioner(
                        fontSize: 11,
                        fontWeight:
                            isLogin ? FontWeight.w700 : FontWeight.w500,
                        letterSpacing: 1.5,
                        color: isLogin
                            ? const Color(0xFF0A0A0A)
                            : const Color(0xFFAAAAAA),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => toggle(false),
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: Text(
                      'SIGN UP',
                      style: GoogleFonts.commissioner(
                        fontSize: 11,
                        fontWeight:
                            !isLogin ? FontWeight.w700 : FontWeight.w500,
                        letterSpacing: 1.5,
                        color: !isLogin
                            ? const Color(0xFF0A0A0A)
                            : const Color(0xFFAAAAAA),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _mobileLoginFields() => [
        _mobileField('Email address', emailCtrl,
            keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 16),
        _mobileField('Password', passCtrl,
            obscure: _obscureLogin,
            onToggleObscure: () =>
                setState(() => _obscureLogin = !_obscureLogin)),
      ];

  List<Widget> _mobileSignupFields() => [
        Row(
          children: [
            Expanded(child: _mobileField('First name', firstCtrl)),
            const SizedBox(width: 12),
            Expanded(child: _mobileField('Last name', lastCtrl)),
          ],
        ),
        const SizedBox(height: 16),
        _mobileField('Email address', signupEmailCtrl,
            keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 16),
        _mobileField('Phone number', phoneCtrl,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(12),
            ]),
        const SizedBox(height: 16),
        _mobileField('Password', signupPassCtrl,
            obscure: _obscureSignupPass,
            onToggleObscure: () =>
                setState(() => _obscureSignupPass = !_obscureSignupPass)),
        const SizedBox(height: 16),
        _mobileField('Confirm password', confirmPassCtrl,
            obscure: _obscureConfirm,
            onToggleObscure: () =>
                setState(() => _obscureConfirm = !_obscureConfirm)),

        // Address section
        const SizedBox(height: 36),
        Row(
          children: [
            Expanded(
                child:
                    Container(height: 1, color: const Color(0xFFEEEEEE))),
            const SizedBox(width: 12),
            Column(
              children: [
                Text(
                  'DELIVERY ADDRESS',
                  style: GoogleFonts.commissioner(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF999999),
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Optional — for faster checkout',
                  style: GoogleFonts.inter(
                      fontSize: 10, color: const Color(0xFFBBBBBB)),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
                child:
                    Container(height: 1, color: const Color(0xFFEEEEEE))),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
                child: _mobileField('House / Unit no.', houseNumberCtrl)),
            const SizedBox(width: 12),
            Expanded(child: _mobileField('Street', streetNameCtrl)),
          ],
        ),
        const SizedBox(height: 16),
        _mobileLocationField(),
      ];

  Widget _mobileLocationField() {
    final hasLocation = _locationDisplay.isNotEmpty;
    return GestureDetector(
      onTap: _openLocationPicker,
      child: Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F6F4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasLocation
                ? const Color(0xFF0A0A0A)
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                hasLocation
                    ? _locationDisplay
                    : 'Location (barangay, city, province)',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: hasLocation
                      ? const Color(0xFF0A0A0A)
                      : const Color(0xFF999999),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              hasLocation
                  ? Icons.check_circle_outline
                  : Icons.keyboard_arrow_right,
              size: 18,
              color: hasLocation
                  ? const Color(0xFF0A0A0A)
                  : const Color(0xFFBBBBBB),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mobileField(
    String label,
    TextEditingController ctrl, {
    bool obscure = false,
    VoidCallback? onToggleObscure,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF0A0A0A)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(
          fontSize: 14,
          color: const Color(0xFF999999),
        ),
        floatingLabelStyle: GoogleFonts.commissioner(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF0A0A0A),
          letterSpacing: 1,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        filled: true,
        fillColor: const Color(0xFFF7F6F4),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: Color(0xFF0A0A0A), width: 1.5),
        ),
        suffixIcon: onToggleObscure != null
            ? IconButton(
                onPressed: onToggleObscure,
                icon: Icon(
                  obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 18,
                  color: const Color(0xFF999999),
                ),
              )
            : null,
      ),
    );
  }

  Widget _mobileSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: loading ? null : (isLogin ? login : signup),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0A0A0A),
          foregroundColor: Colors.white,
          elevation: 0,
          disabledBackgroundColor: const Color(0xFF555555),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: loading
              ? const SizedBox(
                  key: ValueKey('m_spinner'),
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: Colors.white),
                )
              : Text(
                  key: ValueKey(isLogin ? 'm_signin' : 'm_create'),
                  isLogin ? 'SIGN IN' : 'CREATE ACCOUNT',
                  style: GoogleFonts.commissioner(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.5,
                  ),
                ),
        ),
      ),
    );
  }

  // ── Desktop ─────────────────────────────────────────────────────────────────

  Widget _desktopLayout() {
    return Row(
      children: [
        Expanded(flex: 5, child: _brandPanel()),
        Expanded(
          flex: 4,
          child: Container(
            color: Colors.white,
            child: SlideTransition(
              position: _slide,
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 56, vertical: 72),
                child: _formContent(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _brandPanel() {
    return Container(
      color: const Color(0xFF0A0A0A),
      padding: const EdgeInsets.all(60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Brand name
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'VARÓN',
                style: GoogleFonts.commissioner(
                  fontSize: 26,
                  fontWeight: FontWeight.w200,
                  color: Colors.white,
                  letterSpacing: 12,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'PREMIUM MINIMALIST FASHION',
                style: GoogleFonts.commissioner(
                  fontSize: 8,
                  color: Colors.white.withValues(alpha: 0.35),
                  letterSpacing: 4,
                ),
              ),
            ],
          ),
          // Tagline
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 1,
                color: Colors.white.withValues(alpha: 0.25),
              ),
              const SizedBox(height: 28),
              Text(
                'Crafted for\nthe modern\ngentleman.',
                style: GoogleFonts.commissioner(
                  fontSize: 38,
                  fontWeight: FontWeight.w200,
                  color: Colors.white,
                  letterSpacing: 0.5,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Curated essentials. Timeless form.\nUncompromising quality.',
                style: GoogleFonts.commissioner(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.4),
                  letterSpacing: 0.5,
                  height: 1.9,
                ),
              ),
            ],
          ),
          // Footer
          Text(
            '© VARÓN 2025',
            style: GoogleFonts.commissioner(
              fontSize: 9,
              color: Colors.white.withValues(alpha: 0.2),
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared form ─────────────────────────────────────────────────────────────

  Widget _formContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back button
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _goBack,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.arrow_back_ios,
                    size: 14, color: Color(0xFF888888)),
                const SizedBox(width: 4),
                Text(
                  'Back',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFF888888),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
        // Tab row
        Row(
          children: [
            _tab('LOGIN', isLogin, () => toggle(true)),
            const SizedBox(width: 32),
            _tab('SIGN UP', !isLogin, () => toggle(false)),
          ],
        ),
        const SizedBox(height: 36),

        // Animated form swap
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: isLogin
              ? Column(
                  key: const ValueKey('login'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ..._loginFields(),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerRight,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const ForgotPasswordScreen()),
                          ),
                          child: Text(
                            'Forgot password?',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: const Color(0xFF888888),
                              decoration: TextDecoration.underline,
                              decorationColor: const Color(0xFFCCCCCC),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  key: const ValueKey('signup'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _signupFields(),
                ),
        ),

        const SizedBox(height: 36),
        _submitButton(),

        if (!isLogin) ...[
          const SizedBox(height: 18),
          Center(
            child: Text(
              'By creating an account you agree to our\nTerms of Service and Privacy Policy.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 10,
                color: const Color(0xFFAAAAAA),
                height: 1.7,
              ),
            ),
          ),
        ],

        const SizedBox(height: 24),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isLogin
                    ? "Don't have an account?  "
                    : 'Already have an account?  ',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: const Color(0xFF888888),
                ),
              ),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => toggle(!isLogin),
                  child: Text(
                    isLogin ? 'Sign up' : 'Sign in',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0A0A0A),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _submitButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: loading ? null : (isLogin ? login : signup),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0A0A0A),
          foregroundColor: Colors.white,
          elevation: 0,
          disabledBackgroundColor: const Color(0xFF444444),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: loading
              ? const SizedBox(
                  key: ValueKey('spinner'),
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: Colors.white,
                  ),
                )
              : Text(
                  key: ValueKey(isLogin ? 'signin' : 'create'),
                  isLogin ? 'SIGN IN' : 'CREATE ACCOUNT',
                  style: GoogleFonts.commissioner(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.5,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _tab(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.commissioner(
                fontSize: 10,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 2,
                color: active
                    ? const Color(0xFF0A0A0A)
                    : const Color(0xFFBBBBBB),
              ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              height: 1.5,
              width: active ? 36 : 0,
              color: const Color(0xFF0A0A0A),
            ),
          ],
        ),
      ),
    );
  }

  // ── Fields ──────────────────────────────────────────────────────────────────

  List<Widget> _loginFields() => [
        _field(
          'Email address',
          emailCtrl,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 24),
        _field(
          'Password',
          passCtrl,
          obscure: _obscureLogin,
          onToggleObscure: () =>
              setState(() => _obscureLogin = !_obscureLogin),
        ),
      ];

  List<Widget> _signupFields() => [
        Row(
          children: [
            Expanded(child: _field('First name', firstCtrl)),
            const SizedBox(width: 16),
            Expanded(child: _field('Last name', lastCtrl)),
          ],
        ),
        const SizedBox(height: 24),
        _field(
          'Email address',
          signupEmailCtrl,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 24),
        _field(
          'Phone number',
          phoneCtrl,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(12),
          ],
        ),
        const SizedBox(height: 24),
        _field(
          'Password',
          signupPassCtrl,
          obscure: _obscureSignupPass,
          onToggleObscure: () =>
              setState(() => _obscureSignupPass = !_obscureSignupPass),
        ),
        const SizedBox(height: 24),
        _field(
          'Confirm password',
          confirmPassCtrl,
          obscure: _obscureConfirm,
          onToggleObscure: () =>
              setState(() => _obscureConfirm = !_obscureConfirm),
        ),

        // ── Address section ───────────────────────────────────────
        const SizedBox(height: 40),
        _sectionDivider('DELIVERY ADDRESS', 'Optional — for faster checkout'),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(child: _field('House / Unit no.', houseNumberCtrl)),
            const SizedBox(width: 16),
            Expanded(child: _field('Street name', streetNameCtrl)),
          ],
        ),
        const SizedBox(height: 24),
        _locationField(),
      ];

  Widget _sectionDivider(String title, String subtitle) {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: const Color(0xFFEEEEEE))),
        const SizedBox(width: 16),
        Column(
          children: [
            Text(
              title,
              style: GoogleFonts.commissioner(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF888888),
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: GoogleFonts.inter(
                fontSize: 9,
                color: const Color(0xFFBBBBBB),
              ),
            ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(child: Container(height: 1, color: const Color(0xFFEEEEEE))),
      ],
    );
  }

  Widget _locationField() {
    final hasLocation = _locationDisplay.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'LOCATION',
          style: GoogleFonts.commissioner(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF888888),
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _openLocationPicker,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.only(bottom: 10),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFDDDDDD), width: 1),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    hasLocation
                        ? _locationDisplay
                        : 'Select barangay, city, province',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: hasLocation
                          ? const Color(0xFF0A0A0A)
                          : const Color(0xFFBBBBBB),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  hasLocation
                      ? Icons.check_circle_outline
                      : Icons.keyboard_arrow_right,
                  size: 16,
                  color: hasLocation
                      ? const Color(0xFF0A0A0A)
                      : const Color(0xFFAAAAAA),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    bool obscure = false,
    VoidCallback? onToggleObscure,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.commissioner(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF888888),
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          obscureText: obscure,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: const Color(0xFF0A0A0A),
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.only(bottom: 8),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFDDDDDD), width: 1),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF0A0A0A), width: 1.5),
            ),
            suffixIcon: onToggleObscure != null
                ? GestureDetector(
                    onTap: onToggleObscure,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Icon(
                        obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 16,
                        color: const Color(0xFF888888),
                      ),
                    ),
                  )
                : null,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 28,
              minHeight: 28,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Location picker bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _LocationPickerSheet extends StatefulWidget {
  const _LocationPickerSheet();

  @override
  State<_LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<_LocationPickerSheet> {
  List<dynamic> regions = [];
  List<dynamic> provinces = [];
  List<dynamic> cities = [];
  List<dynamic> barangays = [];

  String? regionCode, regionName;
  String? provinceCode, provinceName;
  String? cityCode, cityName;
  String? barangayCode, barangayName;

  bool loadingRegions = true;
  bool loadingProvinces = false;
  bool loadingCities = false;
  bool loadingBarangays = false;

  @override
  void initState() {
    super.initState();
    _load('https://psgc.gitlab.io/api/regions/', (data) {
      regions = data;
      loadingRegions = false;
    });
  }

  Future<void> _load(String url, void Function(List<dynamic>) onSuccess) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200 && mounted) {
        final data = json.decode(res.body) as List;
        data.sort(
            (a, b) => (a['name'] as String).compareTo(b['name'] as String));
        setState(() => onSuccess(data));
      }
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  void _onRegionChanged(String code, String name) {
    setState(() {
      regionCode = code;
      regionName = name;
      provinceCode = provinceName = null;
      cityCode = cityName = null;
      barangayCode = barangayName = null;
      provinces = cities = barangays = [];
      loadingProvinces = true;
    });
    _load('https://psgc.gitlab.io/api/regions/$code/provinces/', (data) {
      provinces = data;
      loadingProvinces = false;
    });
  }

  void _onProvinceChanged(String code, String name) {
    setState(() {
      provinceCode = code;
      provinceName = name;
      cityCode = cityName = null;
      barangayCode = barangayName = null;
      cities = barangays = [];
      loadingCities = true;
    });
    _load(
      'https://psgc.gitlab.io/api/provinces/$code/cities-municipalities/',
      (data) {
        cities = data;
        loadingCities = false;
      },
    );
  }

  void _onCityChanged(String code, String name) {
    setState(() {
      cityCode = code;
      cityName = name;
      barangayCode = barangayName = null;
      barangays = [];
      loadingBarangays = true;
    });
    _load(
      'https://psgc.gitlab.io/api/cities-municipalities/$code/barangays/',
      (data) {
        barangays = data;
        loadingBarangays = false;
      },
    );
  }

  bool get _canConfirm =>
      regionCode != null &&
      provinceCode != null &&
      cityCode != null &&
      barangayCode != null;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 14, bottom: 4),
            width: 32,
            height: 3,
            decoration: BoxDecoration(
              color: const Color(0xFFDDDDDD),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 20, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'SELECT LOCATION',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                    color: Color(0xFF0A0A0A),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close,
                      size: 18, color: Color(0xFF888888)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFEEEEEE)),
          Expanded(
            child: SingleChildScrollView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _dropdown(
                    label: 'REGION',
                    loading: loadingRegions,
                    items: regions,
                    value: regionCode,
                    hint: 'Select region',
                    enabled: true,
                    onChanged: _onRegionChanged,
                  ),
                  const SizedBox(height: 24),
                  _dropdown(
                    label: 'PROVINCE',
                    loading: loadingProvinces,
                    items: provinces,
                    value: provinceCode,
                    hint: regionCode == null
                        ? 'Select region first'
                        : 'Select province',
                    enabled: regionCode != null && !loadingProvinces,
                    onChanged: _onProvinceChanged,
                  ),
                  const SizedBox(height: 24),
                  _dropdown(
                    label: 'CITY / MUNICIPALITY',
                    loading: loadingCities,
                    items: cities,
                    value: cityCode,
                    hint: provinceCode == null
                        ? 'Select province first'
                        : 'Select city',
                    enabled: provinceCode != null && !loadingCities,
                    onChanged: _onCityChanged,
                  ),
                  const SizedBox(height: 24),
                  _dropdown(
                    label: 'BARANGAY',
                    loading: loadingBarangays,
                    items: barangays,
                    value: barangayCode,
                    hint: cityCode == null
                        ? 'Select city first'
                        : 'Select barangay',
                    enabled: cityCode != null && !loadingBarangays,
                    onChanged: (code, name) =>
                        setState(() {
                          barangayCode = code;
                          barangayName = name;
                        }),
                  ),
                  if (_canConfirm) ...[
                    const SizedBox(height: 28),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      color: const Color(0xFFF6F6F6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'SELECTED',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                              color: Color(0xFF888888),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$barangayName, $cityName,\n$provinceName, $regionName',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF0A0A0A),
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _canConfirm
                          ? () => Navigator.of(context).pop({
                                'region': regionName ?? '',
                                'province': provinceName ?? '',
                                'city': cityName ?? '',
                                'barangay': barangayName ?? '',
                                'regionCode': regionCode ?? '',
                                'provinceCode': provinceCode ?? '',
                                'cityCode': cityCode ?? '',
                                'barangayCode': barangayCode ?? '',
                              })
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A0A0A),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        disabledBackgroundColor: const Color(0xFFCCCCCC),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                      ),
                      child: const Text(
                        'CONFIRM LOCATION',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required bool loading,
    required List<dynamic> items,
    required String? value,
    required String hint,
    required bool enabled,
    required void Function(String code, String name) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: Color(0xFF888888),
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFFDDDDDD), width: 1),
            ),
          ),
          padding: const EdgeInsets.only(bottom: 2),
          child: loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Color(0xFF0A0A0A),
                    ),
                  ),
                )
              : DropdownButton<String>(
                  value: value,
                  isExpanded: true,
                  underline: const SizedBox(),
                  icon: Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: enabled
                        ? const Color(0xFF888888)
                        : const Color(0xFFCCCCCC),
                  ),
                  hint: Text(
                    hint,
                    style: TextStyle(
                      fontSize: 14,
                      color: enabled
                          ? const Color(0xFFBBBBBB)
                          : const Color(0xFFDDDDDD),
                    ),
                  ),
                  disabledHint: Text(
                    hint,
                    style: const TextStyle(
                        fontSize: 14, color: Color(0xFFDDDDDD)),
                  ),
                  items: enabled
                      ? items
                          .map<DropdownMenuItem<String>>(
                            (item) => DropdownMenuItem<String>(
                              value: item['code'] as String,
                              child: Text(
                                item['name'] as String,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF0A0A0A),
                                ),
                              ),
                            ),
                          )
                          .toList()
                      : null,
                  onChanged: enabled
                      ? (code) {
                          if (code == null) return;
                          final item =
                              items.firstWhere((i) => i['code'] == code);
                          onChanged(code, item['name'] as String);
                        }
                      : null,
                ),
        ),
      ],
    );
  }
}

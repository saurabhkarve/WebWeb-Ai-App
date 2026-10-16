import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth_provider.dart';
import '../config.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets.dart';

const _resendSeconds = 30;
const _emerald = Color(0xFF10B981);
const _rise = Cubic(0.22, 1, 0.36, 1);
const _pop = Cubic(0.34, 1.56, 0.64, 1);

String _formatPhone(String d) => d.length > 5 ? '${d.substring(0, 5)} ${d.substring(5)}' : d;

/// Sign in, as the web (auth)/login page on a phone: the stacked lockup, "Welcome", a +91 mobile number
/// (or an email), then six code boxes with a resend countdown. The step follows [AuthProvider.otpSent].
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  final _contactFocus = FocusNode();
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  bool _byEmail = false;
  String? _error;
  int _resendIn = 0;
  Timer? _timer;

  AuthProvider get _auth => context.read<AuthProvider>();

  String get _digits => _phone.text.replaceAll(RegExp(r'\D'), '');
  bool get _phoneValid => RegExp(r'^[6-9]\d{9}$').hasMatch(_digits);
  bool get _emailValid => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(_email.text.trim());
  bool get _badStart => !_byEmail && _digits.isNotEmpty && !RegExp(r'^[6-9]').hasMatch(_digits);
  bool get _contactValid => _byEmail ? _emailValid : _phoneValid;

  @override
  void initState() {
    super.initState();
    for (final f in [_contactFocus, _codeFocus]) {
      f.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shake.dispose();
    _phone.dispose();
    _email.dispose();
    _code.dispose();
    _codeFocus.dispose();
    _contactFocus.dispose();
    super.dispose();
  }

  void _fail(String? msg) {
    setState(() => _error = msg ?? t('Something went wrong'));
    _shake.forward(from: 0);
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _resendIn = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (tm) {
      if (!mounted) return tm.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) tm.cancel();
    });
  }

  Future<void> _submitContact() async {
    if (!_contactValid || _auth.loading) return;
    setState(() => _error = null);
    final ok = _byEmail ? await _auth.sendEmailOtp(_email.text) : await _auth.sendOtp(_digits);
    if (!mounted) return;
    if (!ok) return _fail(_auth.error);
    _code.clear();
    _startCountdown();
    WidgetsBinding.instance.addPostFrameCallback((_) => _codeFocus.requestFocus());
  }

  Future<void> _verify() async {
    final code = _code.text;
    if (code.length != 6 || _auth.loading) return;
    setState(() => _error = null);
    final ok = await _auth.verifyOtp(code);
    if (!mounted || ok) return;
    _fail(_auth.error);
    _code.clear();
    _codeFocus.requestFocus();
  }

  Future<void> _resend() async {
    if (_resendIn > 0 || _auth.loading) return;
    setState(() => _error = null);
    final ok = await _auth.resendOtp();
    if (!mounted) return;
    if (!ok) return setState(() => _error = _auth.error);
    _code.clear();
    _startCountdown();
    _codeFocus.requestFocus();
  }

  void _changeContact() {
    _timer?.cancel();
    setState(() {
      _error = null;
      _resendIn = 0;
    });
    _auth.backToLogin();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final p = Pal.of(context);
    final otp = auth.otpSent;
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(children: [
            const Align(alignment: Alignment.centerRight, child: _LanguageMenu()),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 384),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Center(child: LogoInline(size: 40, markSize: 60)),
                      const SizedBox(height: 24),
                      _Rise(key: ValueKey(otp), child: otp ? _otpStep(auth, p) : _contactStep(auth, p)),
                    ]),
                  ),
                ),
              ),
            ),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: '${t('A product of')} '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: GestureDetector(
                    onTap: () => launchUrl(Uri.parse('https://skyq.tech/?r=ww1'), mode: LaunchMode.externalApplication),
                    child: Text('SkyQ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.text)),
                  ),
                ),
              ]),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: p.muted),
            ),
          ]),
        ),
      ),
    );
  }

  // ---------- step 1: mobile number or email ----------
  Widget _contactStep(AuthProvider auth, Pal p) {
    final valid = _contactValid;
    final focused = _contactFocus.hasFocus;
    final borderColor = _error != null ? p.danger : (focused ? kGold : (valid ? _emerald.withValues(alpha: .6) : p.border));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('Welcome'), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, height: 1.25)),
      const SizedBox(height: 24),
      Text(t(_byEmail ? 'Email address' : 'Mobile number'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      _Shake(
        controller: _shake,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 56,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: p.canvas,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
            boxShadow: focused ? [BoxShadow(color: kGold.withValues(alpha: .25), spreadRadius: 4)] : null,
          ),
          child: Row(children: [
            if (!_byEmail)
              Container(
                height: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: p.chip.withValues(alpha: .7), border: Border(right: BorderSide(color: p.border))),
                child: const Text('🇮🇳 +91', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            Expanded(
              child: TextField(
                key: ValueKey(_byEmail),
                controller: _byEmail ? _email : _phone,
                focusNode: _contactFocus,
                autofocus: true,
                keyboardType: _byEmail ? TextInputType.emailAddress : TextInputType.phone,
                autofillHints: [_byEmail ? AutofillHints.email : AutofillHints.telephoneNumberNational],
                inputFormatters: _byEmail ? null : [_PhoneFormatter()],
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _submitContact(),
                onChanged: (_) => setState(() => _error = null),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: _byEmail ? 0 : .45, color: p.text),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  hintText: _byEmail ? 'you@example.com' : '98765 43210',
                  hintStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, letterSpacing: 0, color: p.muted.withValues(alpha: .6)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: valid ? const _Pop(child: WIcon(WI.checkCircle, size: 24, color: _emerald)) : const SizedBox(width: 24),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 20),
        child: _error != null
            ? Text(_error!, style: TextStyle(fontSize: 14, color: p.danger))
            : _badStart
                ? Text(t('Indian mobile numbers start with 6, 7, 8 or 9.'), style: TextStyle(fontSize: 14, color: p.danger))
                : null,
      ),
      const SizedBox(height: 16),
      _BigGoldButton(
        label: auth.loading ? t('Sending code…') : '${t('Continue')}  →',
        onPressed: valid && !auth.loading ? _submitContact : null,
      ),
      const SizedBox(height: 12),
      Text.rich(
        TextSpan(children: [
          TextSpan(text: '${t('By continuing you confirm you are 18 or older and agree to our')} '),
          _link(t('Terms'), '$siteUrl/terms', p),
          TextSpan(text: ' ${t('and')} '),
          _link(t('Privacy Policy'), '$siteUrl/privacy', p),
          const TextSpan(text: '.'),
        ]),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: p.muted, height: 1.4),
      ),
      const SizedBox(height: 12),
      Center(
        child: GestureDetector(
          onTap: () => setState(() {
            _byEmail = !_byEmail;
            _error = null;
          }),
          child: Text(
            t(_byEmail ? 'Use my mobile number instead' : 'No mobile number? Use email instead'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.link),
          ),
        ),
      ),
    ]);
  }

  InlineSpan _link(String text, String url, Pal p) => WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: GestureDetector(
          onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.link)),
        ),
      );

  // ---------- step 2: the six-digit code ----------
  Widget _otpStep(AuthProvider auth, Pal p) {
    final code = _code.text;
    final target = auth.email ?? '+91 ${_formatPhone(auth.phone)}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onTap: _changeContact,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            WIcon(WI.back, size: 16, color: p.muted),
            const SizedBox(width: 4),
            Text(t(auth.email != null ? 'Change email' : 'Change number'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.muted)),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Text(t('Enter the code'), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, height: 1.25)),
      const SizedBox(height: 8),
      Text.rich(
        TextSpan(children: [
          TextSpan(text: '${t('We sent a 6-digit code to')} '),
          TextSpan(text: target, style: TextStyle(fontWeight: FontWeight.w700, color: p.text)),
        ]),
        style: TextStyle(fontSize: 16, color: p.muted),
      ),
      const SizedBox(height: 24),
      _Shake(
        controller: _shake,
        child: SizedBox(
          height: 56,
          child: Stack(children: [
            Row(children: [
              for (var i = 0; i < 6; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _box(i < code.length ? code[i] : '', _codeFocus.hasFocus && i == math.min(code.length, 5), p)),
              ],
            ]),
            // one invisible field drives the boxes: paste and SMS autofill land in one go
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                child: TextField(
                  controller: _code,
                  focusNode: _codeFocus,
                  autofocus: true,
                  enabled: !auth.loading,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                  showCursor: false,
                  enableInteractiveSelection: false,
                  decoration: const InputDecoration(border: InputBorder.none, counterText: ''),
                  onChanged: (v) {
                    setState(() => _error = null);
                    if (v.length == 6) _verify();
                  },
                ),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 20),
        child: _error != null
            ? Text(_error!, style: TextStyle(fontSize: 14, color: p.danger))
            : auth.loading
                ? Text(t('Verifying…'), style: TextStyle(fontSize: 14, color: p.muted))
                : null,
      ),
      const SizedBox(height: 16),
      _BigGoldButton(label: auth.loading ? t('Verifying…') : t('Verify & continue'), onPressed: code.length == 6 && !auth.loading ? _verify : null),
      const SizedBox(height: 16),
      Center(
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: '${t("Didn't get it?")} '),
            _resendIn > 0
                ? TextSpan(text: t('Resend in {n}s', {'n': _resendIn}), style: TextStyle(fontWeight: FontWeight.w700, color: p.text, fontFeatures: const [FontFeature.tabularFigures()]))
                : WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: GestureDetector(onTap: _resend, child: Text(t('Resend code'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.link))),
                  ),
          ]),
          style: TextStyle(fontSize: 14, color: p.muted),
        ),
      ),
    ]);
  }

  Widget _box(String d, bool focused, Pal p) {
    final filled = d.isNotEmpty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      transform: Matrix4.translationValues(0, focused ? -2 : 0, 0),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? kGold.withValues(alpha: .1) : p.canvas,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _error != null ? p.danger : (filled || focused ? kGold : p.border)),
        boxShadow: focused ? [BoxShadow(color: kGold.withValues(alpha: .25), spreadRadius: 4)] : null,
      ),
      child: Text(d, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
    );
  }
}

/// The web's sign-in submit: full-width gold pill with a soft amber glow.
class _BigGoldButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const _BigGoldButton({required this.label, this.onPressed});
  @override
  Widget build(BuildContext context) {
    final on = onPressed != null;
    return Opacity(
      opacity: on ? 1 : .5,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          boxShadow: on ? const [BoxShadow(color: Color(0xE6FFA000), blurRadius: 28, spreadRadius: -12, offset: Offset(0, 12))] : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(40)),
            child: InkWell(
              borderRadius: BorderRadius.circular(40),
              onTap: onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kInk)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Globe + current language, opening English / Hindi / Marathi (web LanguageMenu with label).
class _LanguageMenu extends StatelessWidget {
  const _LanguageMenu();
  @override
  Widget build(BuildContext context) {
    final i18n = context.watch<I18n>();
    final p = Pal.of(context);
    final current = kLangs.firstWhere((l) => l.code == i18n.lang, orElse: () => kLangs.first);
    return PopupMenuButton<String>(
      tooltip: t('Change language'),
      color: p.card,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: p.border)),
      onSelected: (code) {
        if (code != i18n.lang) i18n.set(code);
      },
      itemBuilder: (_) => [
        for (final l in kLangs)
          PopupMenuItem(
            value: l.code,
            height: 40,
            child: Row(children: [
              Text(l.native, style: TextStyle(fontSize: 14, fontWeight: l.code == i18n.lang ? FontWeight.w700 : FontWeight.w400, color: p.text)),
              const Spacer(),
              if (l.code != 'en') Text(l.name, style: TextStyle(fontSize: 12, color: p.muted)),
            ]),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          WIcon(WI.globe, size: 20, color: p.text),
          const SizedBox(width: 6),
          Text(current.native, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

/// "98765 43210" while typing; keeps digits only, at most ten.
class _PhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var d = newValue.text.replaceAll(RegExp(r'\D'), '');
    // a pasted "+91 98765 43210" or "098765..." keeps the last ten digits
    if (d.length > 10) d = d.substring(d.length - 10);
    final out = _formatPhone(d);
    return TextEditingValue(text: out, selection: TextSelection.collapsed(offset: out.length));
  }
}

/// mk-rise: fades in while sliding up 18px.
class _Rise extends StatelessWidget {
  final Widget child;
  const _Rise({super.key, required this.child});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 700),
        curve: _rise,
        builder: (_, v, c) => Opacity(opacity: v.clamp(0, 1), child: Transform.translate(offset: Offset(0, 18 * (1 - v)), child: c)),
        child: child,
      );
}

/// mk-pop: scales in from .6 with a small overshoot.
class _Pop extends StatelessWidget {
  final Widget child;
  const _Pop({required this.child});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 500),
        curve: _pop,
        builder: (_, v, c) => Opacity(opacity: v.clamp(0, 1), child: Transform.scale(scale: .6 + .4 * v, child: c)),
        child: child,
      );
}

/// mk-shake: a quick left-right shudder on a wrong number or code.
class _Shake extends StatelessWidget {
  final AnimationController controller;
  final Widget child;
  const _Shake({required this.controller, required this.child});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (_, c) {
          final v = controller.value;
          // 0 → -7 → 7 → -7 → 7 → 0 across the run
          final x = controller.isAnimating ? 7 * math.sin(v * math.pi * 4) * -1 : 0.0;
          return Transform.translate(offset: Offset(x, 0), child: c);
        },
        child: child,
      );
}

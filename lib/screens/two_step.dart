import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr/qr.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../auth_provider.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets.dart';

/// Two-step verification (TOTP), as the web /profile/security: off -> add WEBWEB AI to an authenticator app
/// (QR, key, or the otpauth link on this phone) -> enter its code -> save the 10 recovery codes. When on:
/// how many recovery codes are left, new codes, turn off (each needs a current code).
class TwoStepScreen extends StatefulWidget {
  const TwoStepScreen({super.key});
  @override
  State<TwoStepScreen> createState() => _TwoStepScreenState();
}

enum _Mode { idle, disable, regenerate }

class _TwoStepScreenState extends State<TwoStepScreen> {
  Map? _status; // {enabled, enabledAt, recoveryCodesLeft}
  Map? _setup; // {secret, otpauthUrl}
  List<String>? _codes; // fresh recovery codes, shown once
  _Mode _mode = _Mode.idle;
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  Api get _api => context.read<AuthProvider>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await _api.get('/me/two-step') as Map;
      if (mounted) setState(() => _status = d);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// Runs one call with the busy flag and error line; returns its answer, or null when it failed.
  Future<Map?> _run(Future<dynamic> Function() call) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      return await call() as Map;
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    final d = await _run(() => _api.post('/me/two-step/setup'));
    if (d != null && mounted) {
      _code.clear();
      setState(() => _setup = d);
    }
  }

  bool get _codeValid {
    final c = _code.text.trim();
    // turning off accepts a recovery code too (lost phone)
    return RegExp(r'^\d{6}$').hasMatch(c) || (_mode == _Mode.disable && RegExp(r'^[a-zA-Z0-9]{4}-?[a-zA-Z0-9]{4}$').hasMatch(c));
  }

  Future<void> _submit() async {
    if (!_codeValid || _busy) return;
    final code = _code.text.trim();
    if (_setup != null) {
      final d = await _run(() => _api.post('/me/two-step/enable', {'code': code}));
      if (d == null || !mounted) return;
      _code.clear();
      setState(() {
        _setup = null;
        _codes = (d['recoveryCodes'] as List).cast<String>();
      });
    } else if (_mode == _Mode.disable) {
      final d = await _run(() => _api.post('/me/two-step/disable', {'code': code}));
      if (d == null || !mounted) return;
      _code.clear();
      setState(() => _mode = _Mode.idle);
      toast(context, t('Two-step verification is off.'));
    } else if (_mode == _Mode.regenerate) {
      final d = await _run(() => _api.post('/me/two-step/recovery-codes', {'code': code}));
      if (d == null || !mounted) return;
      _code.clear();
      setState(() {
        _mode = _Mode.idle;
        _codes = (d['recoveryCodes'] as List).cast<String>();
      });
    }
    await _load();
  }

  void _copy(String text, String done) {
    Clipboard.setData(ClipboardData(text: text));
    toast(context, done);
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final s = _status;
    Widget body;
    if (s == null) {
      body = _error != null ? Text(_error!, style: TextStyle(color: p.danger)) : const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
    } else if (_codes != null) {
      body = _recoveryCodes(p);
    } else if (_setup != null) {
      body = _setupCard(p);
    } else if (s['enabled'] == true) {
      body = _onCard(p, s);
    } else {
      body = _offCard(p);
    }
    return Scaffold(
      appBar: AppBar(title: Text(t('Two-step verification'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        Text(
          t('Optional. When it is on, signing in needs the code we send you and a code from an authenticator app on your phone, so a stolen SIM or email alone cannot open your account.'),
          style: TextStyle(fontSize: 14, color: p.muted, height: 1.4),
        ),
        const SizedBox(height: 16),
        body,
      ]),
    );
  }

  Widget _card(Pal p, List<Widget> children, {bool gold = false}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: gold ? kGold.withValues(alpha: .06) : p.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: gold ? kGold.withValues(alpha: .5) : p.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _dot(Color c) => Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle));

  Widget _errorLine(Pal p) => _error == null ? const SizedBox() : Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(fontSize: 13, color: p.danger)));

  Widget _codeField(Pal p, {bool allowRecovery = false}) => TextField(
        controller: _code,
        autofocus: true,
        enabled: !_busy,
        textAlign: TextAlign.center,
        keyboardType: allowRecovery ? TextInputType.visiblePassword : TextInputType.number,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: allowRecovery
            ? [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9-]')), LengthLimitingTextInputFormatter(9)]
            : [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 3, fontFeatures: [FontFeature.tabularFigures()]),
        decoration: InputDecoration(
          hintText: allowRecovery ? t('6-digit code or recovery code') : '123456',
          hintStyle: TextStyle(fontSize: allowRecovery ? 14 : 22, letterSpacing: allowRecovery ? 0 : 6, color: p.muted.withValues(alpha: .6)),
        ),
        onChanged: (_) => setState(() => _error = null),
        onSubmitted: (_) => _submit(),
      );

  Widget _offCard(Pal p) => _card(p, [
        Row(children: [_dot(p.muted.withValues(alpha: .5)), const SizedBox(width: 8), Text(t('Off'), style: const TextStyle(fontWeight: FontWeight.w700))]),
        const SizedBox(height: 8),
        Text(t('You need an authenticator app such as Google Authenticator, Microsoft Authenticator or Authy.'), style: TextStyle(fontSize: 14, color: p.muted)),
        const SizedBox(height: 16),
        GoldButton(label: t('Turn on two-step verification'), loading: _busy, onPressed: _busy ? null : _start),
        _errorLine(p),
      ]);

  Widget _setupCard(Pal p) {
    final secret = '${_setup!['secret']}';
    final url = '${_setup!['otpauthUrl']}';
    return _card(p, [
      Text(t('1. Add WEBWEB AI to your authenticator app'), style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(t('Scan this QR code with the app. On this phone, open the link or type the key instead.'), style: TextStyle(fontSize: 14, color: p.muted)),
      const SizedBox(height: 12),
      // on the phone itself the link is the easy way; the QR is for an authenticator on another device
      GoldButton(
        label: t('Open in authenticator app'),
        wi: WI.lock,
        onPressed: () async {
          final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);
          if (!ok && mounted) toast(context, t('No authenticator app found. Install one, or copy the key.'), error: true);
        },
      ),
      const SizedBox(height: 16),
      Center(
        child: Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: CustomPaint(painter: _PlainQr(url)),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
        SelectableText(secret, style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        TextButton(onPressed: () => _copy(secret.replaceAll(' ', ''), t('Copied')), child: Text(t('Copy key'))),
      ]),
      const SizedBox(height: 16),
      Text(t('2. Enter the 6-digit code it shows'), style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      _codeField(p),
      _errorLine(p),
      const SizedBox(height: 12),
      GoldButton(label: t('Turn on'), loading: _busy, onPressed: _codeValid && !_busy ? _submit : null),
      const SizedBox(height: 4),
      TextButton(
        onPressed: _busy
            ? null
            : () => setState(() {
                  _setup = null;
                  _error = null;
                }),
        child: Text(t('Cancel'), style: TextStyle(color: p.muted)),
      ),
    ]);
  }

  Widget _onCard(Pal p, Map s) {
    final left = (s['recoveryCodesLeft'] as num?)?.toInt() ?? 0;
    final since = DateTime.tryParse('${s['enabledAt']}')?.toLocal();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return _card(p, [
      Row(children: [
        _dot(const Color(0xFF2F9E6E)),
        const SizedBox(width: 8),
        Text(t('On'), style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF2F9E6E))),
        if (since != null) ...[
          const SizedBox(width: 6),
          Flexible(child: Text('· ${t('since {date}', {'date': '${since.day} ${months[since.month - 1]} ${since.year}'})}', style: TextStyle(fontSize: 13, color: p.muted))),
        ],
      ]),
      const SizedBox(height: 8),
      Text(t('{n} of 10 recovery codes left.', {'n': left}), style: TextStyle(fontSize: 14, color: left <= 3 ? p.danger : p.muted, fontWeight: left <= 3 ? FontWeight.w700 : null)),
      const SizedBox(height: 16),
      if (_mode == _Mode.idle) ...[
        GoldButton(
          label: t('New recovery codes'),
          outlined: true,
          onPressed: () => setState(() {
            _mode = _Mode.regenerate;
            _error = null;
            _code.clear();
          }),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() {
            _mode = _Mode.disable;
            _error = null;
            _code.clear();
          }),
          child: Text(t('Turn off'), style: TextStyle(color: p.danger, fontWeight: FontWeight.w700)),
        ),
      ] else ...[
        Text(
          t(_mode == _Mode.disable
              ? 'To turn it off, enter a code from your authenticator app (or a recovery code).'
              : 'Enter a code from your authenticator app. Your old recovery codes will stop working.'),
          style: TextStyle(fontSize: 14, color: p.muted),
        ),
        const SizedBox(height: 8),
        _codeField(p, allowRecovery: _mode == _Mode.disable),
        _errorLine(p),
        const SizedBox(height: 12),
        GoldButton(
          label: t(_mode == _Mode.disable ? 'Turn off two-step verification' : 'Make new codes'),
          loading: _busy,
          onPressed: _codeValid && !_busy ? _submit : null,
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                    _mode = _Mode.idle;
                    _error = null;
                  }),
          child: Text(t('Cancel'), style: TextStyle(color: p.muted)),
        ),
      ],
    ]);
  }

  Widget _recoveryCodes(Pal p) {
    final codes = _codes!;
    final text = '${t('WEBWEB AI recovery codes')}\n\n${codes.join('\n')}\n';
    return _card(p, gold: true, [
      Text(t('Save your recovery codes'), style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(
        t('If you lose the phone with your authenticator app, each of these codes lets you sign in once. Keep them somewhere safe. They are shown only now.'),
        style: TextStyle(fontSize: 14, color: p.muted),
      ),
      const SizedBox(height: 12),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 3.6,
        children: [
          for (final c in codes)
            Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(8)),
              child: Text(c, style: const TextStyle(fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: GoldButton(label: t('Copy'), outlined: true, height: 40, onPressed: () => _copy(codes.join('\n'), t('Copied')))),
        const SizedBox(width: 8),
        Expanded(child: GoldButton(label: t('Share'), outlined: true, height: 40, onPressed: () => SharePlus.instance.share(ShareParams(text: text, subject: t('WEBWEB AI recovery codes'))))),
      ]),
      const SizedBox(height: 8),
      GoldButton(label: t('I have saved them'), onPressed: () => setState(() => _codes = null)),
    ]);
  }
}

/// A plain square-module QR (authenticator scanners are fussy, so none of the profile card's styling).
class _PlainQr extends CustomPainter {
  final String data;
  _PlainQr(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final img = QrImage(QrCode(payload: QrPayload.fromString(data), errorCorrectLevel: QrErrorCorrectLevel.medium));
    final n = img.moduleCount;
    final pad = size.width * .06;
    final cell = (size.width - pad * 2) / n;
    final ink = Paint()..color = const Color(0xFF1E1E1E);
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (img.isDark(r, c)) canvas.drawRect(Rect.fromLTWH(pad + c * cell, pad + r * cell, cell + .5, cell + .5), ink);
      }
    }
  }

  @override
  bool shouldRepaint(_PlainQr old) => old.data != data;
}

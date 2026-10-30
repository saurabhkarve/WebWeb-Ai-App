import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../api.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets.dart';

/// The check after 2 wrong sign-in codes (api/src/captcha.ts): a picture from the API, the member types its
/// characters, and the API gives a one-time pass to send with the real request. Returns the pass, or null when
/// the member cancels (then nothing is sent).
Future<String?> askCaptcha(BuildContext context, Api api) =>
    showDialog<String>(context: context, barrierDismissible: false, builder: (_) => _CaptchaDialog(api: api));

class _CaptchaDialog extends StatefulWidget {
  final Api api;
  const _CaptchaDialog({required this.api});
  @override
  State<_CaptchaDialog> createState() => _CaptchaDialogState();
}

class _CaptchaDialogState extends State<_CaptchaDialog> {
  final _answer = TextEditingController();
  Map? _challenge; // {id, svg}
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _challenge = null;
      _answer.clear();
    });
    try {
      final c = await widget.api.post('/captcha', {}) as Map;
      if (mounted) setState(() => _challenge = c);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _submit() async {
    final c = _challenge;
    if (c == null || _answer.text.trim().isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.api.post('/captcha/verify', {'id': c['id'], 'answer': _answer.text.trim()}) as Map;
      if (mounted) Navigator.of(context).pop(r['pass'] as String);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
      _load(); // each picture can be answered once
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final c = _challenge;
    return AlertDialog(
      title: Text(t('Quick check')),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('After a few wrong codes we check that it is really you. Type the characters in the picture.'), style: TextStyle(fontSize: 14, color: p.muted)),
        const SizedBox(height: 14),
        Row(children: [
          Container(
            width: 210,
            height: 70,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: const Color(0xFFFFF7D6), borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border)),
            clipBehavior: Clip.antiAlias,
            child: c == null
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : SvgPicture.string('${c['svg']}', width: 210, height: 70, fit: BoxFit.contain, semanticsLabel: t('Characters to type')),
          ),
          const SizedBox(width: 6),
          Flexible(child: TextButton(onPressed: _busy ? null : _load, child: Text(t('New picture')))),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _answer,
          autofocus: true,
          enabled: !_busy,
          textAlign: TextAlign.center,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          inputFormatters: [LengthLimitingTextInputFormatter(12)],
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 2),
          decoration: InputDecoration(hintText: t('Characters in the picture'), hintStyle: const TextStyle(fontSize: 14, letterSpacing: 0)),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(fontSize: 13, color: p.danger))),
      ]),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: Text(t('Cancel'))),
        GoldButton(label: _busy ? t('Checking…') : t('Continue'), height: 40, onPressed: c != null && _answer.text.trim().isNotEmpty && !_busy ? _submit : null),
      ],
    );
  }
}

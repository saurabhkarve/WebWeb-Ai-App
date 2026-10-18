import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets.dart';

/// "Write to us" (the Help page form, in the app): help, feedback, something not working… Sent signed in
/// (POST /support), so the team sees who wrote and replies on the registered number; it also lands in
/// Admin > Support and the support inbox.
Future<void> showSupportSheet(BuildContext context, {String kind = 'help'}) {
  final p = Pal.of(context);
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.canvas,
    barrierColor: kInk.withValues(alpha: .6),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _SupportSheet(kind: kind),
  );
}

const _kinds = [
  ('help', 'Need help'),
  ('feedback', 'Feedback'),
  ('bug', 'Something is not working'),
  ('account', 'Account'),
  ('other', 'Other'),
];

class _SupportSheet extends StatefulWidget {
  final String kind;
  const _SupportSheet({required this.kind});
  @override
  State<_SupportSheet> createState() => _SupportSheetState();
}

class _SupportSheetState extends State<_SupportSheet> {
  late String _kind = widget.kind;
  final _msg = TextEditingController();
  bool _busy = false;
  int? _sentId;

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final auth = context.read<AuthProvider>();
    setState(() => _busy = true);
    try {
      String? version;
      try {
        final i = await PackageInfo.fromPlatform();
        version = '${i.version}+${i.buildNumber}';
      } catch (_) {}
      final r = await auth.api.post('/support', {
        'kind': _kind,
        'message': _msg.text.trim(),
        'page': 'app',
        'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        if (version != null) 'appVersion': version,
        'lang': currentLang,
      }) as Map;
      if (mounted) setState(() => _sentId = (r['id'] as num?)?.toInt() ?? 0);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final me = context.watch<AuthProvider>().profile;
    final bottom = MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 16;
    if (_sentId != null) {
      return Padding(
        padding: EdgeInsets.fromLTRB(24, 28, 24, bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: const Color(0xFF2F9E6E).withValues(alpha: .15), shape: BoxShape.circle),
            child: const Center(child: WIcon(WI.check, size: 26, color: Color(0xFF2F9E6E), strokeWidth: 2.4)),
          ),
          const SizedBox(height: 12),
          Text(t('Thank you, we have it'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(t('Request #{id}. Our team will get back to you within one working day.', {'id': _sentId!}),
              textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: p.muted, height: 1.4)),
          const SizedBox(height: 20),
          GoldButton(label: t('Close'), height: 44, onPressed: () => Navigator.pop(context)),
        ]),
      );
    }
    final ok = _msg.text.trim().length >= 10 && !_busy;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(t('Write to us'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            GestureDetector(onTap: () => Navigator.pop(context), child: WIcon(WI.close, size: 24, color: p.text)),
          ]),
          const SizedBox(height: 4),
          Text(t('Questions, feedback or something not working? Tell us here and our team will reply within one working day.'),
              style: TextStyle(fontSize: 13, color: p.muted, height: 1.4)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (id, label) in _kinds) ScopeChip(label: t(label), selected: _kind == id, onTap: () => setState(() => _kind = id)),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: _msg,
            autofocus: true,
            minLines: 5,
            maxLines: 10,
            maxLength: 4000,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: t('What happened, and what were you trying to do?'), counterText: ''),
          ),
          if (me != null) ...[
            const SizedBox(height: 8),
            Text(t('Sending as {handle}. We will reply on your registered mobile number.', {'handle': '@${me.handle}'}),
                style: TextStyle(fontSize: 12, color: p.muted)),
          ],
          const SizedBox(height: 14),
          GoldButton(label: t(_busy ? 'Sending…' : 'Send'), wi: WI.send, loading: _busy, onPressed: ok ? _send : null),
        ]),
      ),
    );
  }
}

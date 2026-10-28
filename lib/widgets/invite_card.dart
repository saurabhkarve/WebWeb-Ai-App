import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth_provider.dart';
import '../config.dart';
import '../i18n.dart';
import '../theme.dart';

const _hideKey = 'invite_card_until';

/// A card in the Connect feed after the 15th ask: invite people you know. WhatsApp or the link; "Not now" hides it for two weeks.
class InviteCard extends StatefulWidget {
  const InviteCard({super.key});
  @override
  State<InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends State<InviteCard> {
  bool _hidden = true;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((sp) {
      if (mounted) setState(() => _hidden = DateTime.now().millisecondsSinceEpoch < (sp.getInt(_hideKey) ?? 0));
    }).catchError((_) {});
  }

  Future<void> _hide() async {
    setState(() => _hidden = true);
    try {
      (await SharedPreferences.getInstance()).setInt(_hideKey, DateTime.now().add(const Duration(days: 14)).millisecondsSinceEpoch);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AuthProvider>().profile;
    if (_hidden || me == null) return const SizedBox();
    final p = Pal.of(context);
    final msg = '${t('Join me on WEBWEB AI, where businesses share contacts and get things done.')}\n$siteUrl/@${me.handle}';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kGold.withValues(alpha: .4)),
        gradient: LinearGradient(colors: [kGold.withValues(alpha: .15), Colors.transparent], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 40, height: 40, alignment: Alignment.center, decoration: BoxDecoration(color: kGold.withValues(alpha: .3), shape: BoxShape.circle), child: const Text('🤝', style: TextStyle(fontSize: 20))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('Know someone who should be here?'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.25)),
            const SizedBox(height: 2),
            Text(t('Invite a supplier, a buyer or a friend. Asks get better answers when more of your people are on WEBWEB.'), style: TextStyle(fontSize: 13, height: 1.3, color: p.muted)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              GestureDetector(
                onTap: () => launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(msg)}'), mode: LaunchMode.externalApplication),
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: kGold, borderRadius: BorderRadius.circular(99)),
                  child: Text(t('Invite on WhatsApp'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
                ),
              ),
              GestureDetector(
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: msg));
                  if (!mounted) return;
                  setState(() => _copied = true);
                  Future.delayed(const Duration(milliseconds: 1800), () => mounted ? setState(() => _copied = false) : null);
                },
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), border: Border.all(color: p.border)),
                  child: Text(_copied ? t('Link copied') : t('Copy invite link'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
              GestureDetector(onTap: _hide, child: Padding(padding: const EdgeInsets.all(6), child: Text(t('Not now'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.muted)))),
            ]),
          ]),
        ),
      ]),
    );
  }
}

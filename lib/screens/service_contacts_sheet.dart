import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../contact_sync.dart';
import '../i18n.dart';
import '../permissions.dart';
import '../theme.dart';
import '../widgets.dart';

/// Service contacts, explained before anything is read: what is looked for, what is sent and what is not, and
/// how to stop. Turning it on asks for contacts (if not given yet), saves the choice and looks once right away.
/// Pops with true when it was turned on. [invite]: the one-time invitation ("Not now" instead of "Cancel").
Future<bool?> showServiceContactsSheet(BuildContext context, {bool invite = false}) {
  final p = Pal.of(context);
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.canvas,
    barrierColor: kInk.withValues(alpha: .6),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _Sheet(invite: invite),
  );
}

/// Turn it off (after a confirm). Returns true when it was turned off.
Future<bool> turnOffServiceContacts(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('Turn off Service contacts?')),
      content: Text(t('The contacts you sent will be removed, and the app will stop looking.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Cancel'))),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Turn off'))),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  try {
    await ContactSync.setOn(context.read<AuthProvider>().api, false);
    if (context.mounted) toast(context, t('Service contacts is off'));
    return true;
  } catch (e) {
    if (context.mounted) toast(context, '$e', error: true);
    return false;
  }
}

class _Sheet extends StatefulWidget {
  final bool invite;
  const _Sheet({required this.invite});
  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  bool _busy = false;

  Future<void> _turnOn() async {
    final api = context.read<AuthProvider>().api;
    setState(() => _busy = true);
    try {
      final allowed = await Permissions.ensure(context, Need.contacts, reason: t('To find service providers saved in your phone book.'));
      if (!allowed || !mounted) return;
      await ContactSync.setOn(api, true);
      final n = await ContactSync.run(api, force: true);
      if (!mounted) return;
      Navigator.pop(context, true);
      toast(context, n > 0 ? t('Thank you! {n} service contacts shared.', {'n': n}) : t('Service contacts is on'));
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final bottom = MediaQuery.of(context).padding.bottom + 16;
    Widget point(WI icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(10)),
              child: WIcon(icon, size: 17, color: p.text, strokeWidth: 1.8),
            ),
            const SizedBox(width: 12),
            Expanded(child: Padding(padding: const EdgeInsets.only(top: 6), child: Text(t(text), style: const TextStyle(fontSize: 14, height: 1.35)))),
          ]),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(14)),
              child: const WIcon(WI.contactCard, size: 22, color: kInk, strokeWidth: 1.8),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(t('Share service contacts'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            GestureDetector(onTap: () => Navigator.pop(context, false), child: WIcon(WI.close, size: 24, color: p.text)),
          ]),
          const SizedBox(height: 10),
          Text(t('Help build a trusted list of local service providers: the plumbers, electricians, cabs and carpenters people already call.'),
              style: TextStyle(fontSize: 14, color: p.muted, height: 1.4)),
          const SizedBox(height: 16),
          point(WI.search, 'The app looks through your phone book on your phone for contacts saved with a service word, like plumber, electrician, cab or carpenter.'),
          point(WI.send, 'Only those contacts are sent: the name you saved, the mobile number and the word that matched.'),
          point(WI.lock, 'The rest of your phone book never leaves your phone. Our team reviews every contact before it is used.'),
          point(WI.refresh, 'It checks for new ones at most once a day while you use the app. Turn it off any time from the account menu; what you sent is removed.'),
          const SizedBox(height: 8),
          GoldButton(label: t('Turn on'), wi: WI.check, loading: _busy, onPressed: _busy ? null : _turnOn),
          const SizedBox(height: 8),
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: Text(t(widget.invite ? 'Not now' : 'Cancel'))),
        ]),
      ),
    );
  }
}

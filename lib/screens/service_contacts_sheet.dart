import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../contact_sync.dart';
import '../device_perms.dart';
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
      content: Text(t('The app will stop sharing contacts. Contacts you already shared stay until you remove them one by one under Contacts you share.')),
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
      await DevicePerms.i.refresh();
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
          Text(t('Only service contacts are shared, so members can find trusted help nearby.'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4)),
          const SizedBox(height: 18),
          const ShareFlow(steps: [(WI.search, 'Finds service words on your phone'), (WI.send, 'Shares name, number and word'), (WI.check, 'Our team reviews each one')]),
          const SizedBox(height: 14),
          Row(children: [
            WIcon(WI.lock, size: 14, color: p.muted),
            const SizedBox(width: 6),
            Expanded(child: Text(t('The rest of your phone book stays on your phone. Checked once a day. Turn off any time.'), style: TextStyle(fontSize: 12.5, color: p.muted, height: 1.35))),
          ]),
          const SizedBox(height: 14),
          const SizedBox(height: 8),
          GoldButton(label: t('Turn on'), wi: WI.check, loading: _busy, onPressed: _busy ? null : _turnOn),
          const SizedBox(height: 8),
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: Text(t(widget.invite ? 'Not now' : 'Cancel'))),
        ]),
      ),
    );
  }
}

/// Service contacts is on by default once contacts are allowed: the member sees what is shared (and can turn it off) the
/// first time, then it looks quietly. Someone who turned it off is never switched on again (the server remembers).
/// Safe to call often: it does nothing unless contacts are allowed, and asks nothing once the choice is made.
Future<void> autoServiceContacts(BuildContext context) async {
  if (!ContactSync.supported || !await Permissions.granted(Need.contacts)) return;
  if (!context.mounted) return;
  final api = context.read<AuthProvider>().api;
  try {
    final d = await api.get('/contact-sync') as Map;
    if (d['on'] == true) {
      ContactSync.run(api);
      return;
    }
    if (d['optedOut'] == true) return;
    if (!context.mounted || ModalRoute.of(context)?.isCurrent != true) return;
    final p = Pal.of(context);
    // the notice first: what is shared, and the way to turn it off
    final off = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.canvas,
      barrierColor: kInk.withValues(alpha: .6),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _Notice(),
    );
    if (!context.mounted) return;
    if (off == true) {
      await ContactSync.setOn(api, false);
      return;
    }
    await ContactSync.setOn(api, true);
    await ContactSync.run(api, force: true);
  } catch (_) {
    // quietly try again next time
  }
}

class _Notice extends StatelessWidget {
  const _Notice();

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final bottom = MediaQuery.of(context).padding.bottom + 16;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(width: 44, height: 44, alignment: Alignment.center, decoration: BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(14)), child: const WIcon(WI.contactCard, size: 22, color: kInk, strokeWidth: 1.8)),
            const SizedBox(width: 12),
            Expanded(child: Text(t('Service contacts is on'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 10),
          Text(t('Only service contacts are shared, so members can find trusted help nearby.'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4)),
          const SizedBox(height: 18),
          const ShareFlow(steps: [(WI.search, 'Finds service words on your phone'), (WI.send, 'Shares name, number and word'), (WI.check, 'Our team reviews each one')]),
          const SizedBox(height: 16),
          Row(children: [
            WIcon(WI.lock, size: 14, color: p.muted),
            const SizedBox(width: 6),
            Expanded(child: Text(t('The rest of your phone book stays on your phone. Checked once a day. Turn off any time.'), style: TextStyle(fontSize: 12.5, color: p.muted, height: 1.35))),
          ]),
          const SizedBox(height: 14),
          GoldButton(label: t('OK'), wi: WI.check, onPressed: () => Navigator.pop(context, false)),
          const SizedBox(height: 8),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(t('Turn off'))),
        ]),
      ),
    );
  }
}

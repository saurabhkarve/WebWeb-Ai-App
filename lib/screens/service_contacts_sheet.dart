import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
/// When the phone has not been asked for contacts yet, the sheet is the explanation before the phone's prompt, so it
/// has one way on, "Continue", to that prompt (App Store guideline 5.1.1(iv)); the choice is made there.
Future<bool?> showServiceContactsSheet(BuildContext context, {bool invite = false}) async {
  final p = Pal.of(context);
  final asking = ContactSync.supported && (await Permission.contacts.status).isDenied;
  if (!context.mounted) return null;
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: !asking,
    enableDrag: !asking,
    backgroundColor: p.canvas,
    barrierColor: kInk.withValues(alpha: .6),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => PopScope(canPop: !asking, child: _Sheet(invite: invite, asking: asking)),
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
  /// the phone's contacts prompt comes next: "Continue" and no way to close
  final bool asking;
  const _Sheet({required this.invite, required this.asking});
  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  bool _busy = false;

  Future<void> _turnOn() async {
    final api = context.read<AuthProvider>().api;
    setState(() => _busy = true);
    try {
      final allowed = await Permissions.ensure(context, Need.contacts, reason: t('To find service providers saved in your phone book.'), explained: true);
      await DevicePerms.i.refresh();
      if (!allowed || !mounted) {
        if (mounted && widget.asking) Navigator.pop(context, false); // they chose at the phone's prompt
        return;
      }
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
            if (!widget.asking) GestureDetector(onTap: () => Navigator.pop(context, false), child: WIcon(WI.close, size: 24, color: p.text)),
          ]),
          const SizedBox(height: 10),
          Text(t('Only service contacts are shared, so members can find trusted help nearby.'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4)),
          const SizedBox(height: 18),
          const ShareFlow(steps: [(WI.search, 'Finds service words on your phone'), (WI.send, 'Shares name, number, word and picture'), (WI.check, 'Our team reviews each one')]),
          const SizedBox(height: 14),
          Row(children: [
            WIcon(WI.lock, size: 14, color: p.muted),
            const SizedBox(width: 6),
            Expanded(child: Text(t('The rest of your phone book stays on your phone. Checked once a day. Turn off any time.'), style: TextStyle(fontSize: 12.5, color: p.muted, height: 1.35))),
          ]),
          const SizedBox(height: 14),
          const SizedBox(height: 8),
          GoldButton(label: t(widget.asking ? 'Continue' : 'Turn on'), wi: widget.asking ? null : WI.check, loading: _busy, onPressed: _busy ? null : _turnOn),
          if (!widget.asking) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: Text(t(widget.invite ? 'Not now' : 'Cancel'))),
          ],
        ]),
      ),
    );
  }
}

/// Service contacts is off until the member turns it on (opt-in; App Store guideline 5.1.2 and the DPDP Act): once
/// contacts are allowed, the invitation shows, with "Turn on" as the main button. Closing it or "Not now" shares
/// nothing; the invitation comes back after 14 days. Someone who turned it off is never asked again (the server remembers).
/// Safe to call often: it does nothing unless contacts are allowed, and asks at most once per 14 days.
const _kAskedAt = 'svc_contacts_asked_at';

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
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_kAskedAt);
    if (last != null && DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(last)) < const Duration(days: 14)) return;
    if (!context.mounted || ModalRoute.of(context)?.isCurrent != true) return;
    final p = Pal.of(context);
    // the invitation: what is shared, and how to stop; nothing is shared unless "Turn on" is tapped
    final on = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.canvas,
      barrierColor: kInk.withValues(alpha: .6),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _Notice(),
    );
    await prefs.setInt(_kAskedAt, DateTime.now().millisecondsSinceEpoch);
    if (on != true || !context.mounted) return;
    await ContactSync.setOn(api, true);
    final n = await ContactSync.run(api, force: true);
    if (context.mounted) toast(context, n > 0 ? t('Thank you! {n} service contacts shared.', {'n': n}) : t('Service contacts is on'));
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
            Expanded(child: Text(t('Be the reason someone finds help today'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.25))),
          ]),
          const SizedBox(height: 10),
          Text(t("Right now, a family near you is stuck with a leaking pipe or a car that won't start. The plumber, electrician or driver you trust could be exactly who they need. Share them, and help your neighbourhood look after each other."), style: const TextStyle(fontSize: 14, height: 1.45)),
          const SizedBox(height: 18),
          const ShareFlow(steps: [(WI.search, 'Finds service words on your phone'), (WI.send, 'Shares name, number, word and picture'), (WI.check, 'Our team reviews each one')]),
          const SizedBox(height: 16),
          Row(children: [
            WIcon(WI.lock, size: 14, color: p.muted),
            const SizedBox(width: 6),
            Expanded(child: Text(t('The rest of your phone book stays on your phone. Turn off any time in Account.'), style: TextStyle(fontSize: 12.5, color: p.muted, height: 1.35))),
          ]),
          const SizedBox(height: 18),
          // the main choice, large and gold; "Not now" stays visible below it, quieter
          GoldButton(label: t("Yes, I'll help my neighbours"), wi: WI.check, height: 52, onPressed: () => Navigator.pop(context, true)),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('Not now'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.muted)),
          ),
        ]),
      ),
    );
  }
}

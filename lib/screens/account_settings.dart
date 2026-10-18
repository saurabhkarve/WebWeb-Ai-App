import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth_provider.dart';
import '../config.dart';
import '../i18n.dart';
import '../safety.dart';
import '../theme.dart';
import '../widgets.dart';
import 'two_step.dart';

/// Edit profile > Account and privacy (as the website's tab): two-step verification, blocked people, sign out
/// of all devices, terms and privacy, delete account.
class AccountSettingsTab extends StatefulWidget {
  const AccountSettingsTab({super.key});
  @override
  State<AccountSettingsTab> createState() => _AccountSettingsTabState();
}

class _AccountSettingsTabState extends State<AccountSettingsTab> {
  bool? _twoStep;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await context.read<AuthProvider>().api.get('/me/two-step') as Map;
      if (mounted) setState(() => _twoStep = d['enabled'] == true);
    } catch (_) {}
  }

  Future<void> _signOutEverywhere() async {
    final auth = context.read<AuthProvider>();
    final nav = Navigator.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Sign out of all devices')),
        content: Text(t('Signed in on a phone or computer you no longer use? Sign out everywhere, then sign in again here.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Sign out'))),
        ],
      ),
    );
    if (yes != true) return;
    setState(() => _busy = true);
    try {
      await auth.api.post('/app/me/logout-all', {});
    } catch (_) {
      // signing this phone out still happens below
    }
    nav.popUntil((r) => r.isFirst);
    await auth.logout();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    Widget card(List<Widget> children, {Color? border}) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: border ?? p.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        );
    Text title(String s, {Color? color}) => Text(s, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color));
    Text sub(String s) => Text(s, style: TextStyle(fontSize: 13, color: p.muted, height: 1.35));

    return ListView(padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 32), children: [
      card([
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              title(t('Two-step verification')),
              const SizedBox(height: 2),
              sub(_twoStep == null ? '…' : t(_twoStep! ? 'On: signing in needs a code from your authenticator app.' : 'Off: add a code from an authenticator app to signing in.')),
            ]),
          ),
          const SizedBox(width: 10),
          GoldButton(
            label: t(_twoStep == true ? 'Manage' : 'Turn on'),
            outlined: _twoStep == true,
            height: 40,
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const TwoStepScreen()));
              _load();
            },
          ),
        ]),
      ]),
      const SizedBox(height: 12),
      card([
        title(t('Blocked people')),
        const SizedBox(height: 2),
        sub(t('People you blocked cannot message or call you.')),
        const SizedBox(height: 10),
        GoldButton(label: t('See blocked people'), outlined: true, height: 40, onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BlockedPeopleScreen()))),
      ]),
      const SizedBox(height: 12),
      card([
        title(t('Sessions')),
        const SizedBox(height: 2),
        sub(t('Signed in on a phone or computer you no longer use? Sign out everywhere, then sign in again here.')),
        const SizedBox(height: 10),
        GoldButton(label: t('Sign out of all devices'), outlined: true, height: 40, loading: _busy, onPressed: _busy ? null : _signOutEverywhere),
      ]),
      const SizedBox(height: 12),
      card([
        title(t('Privacy')),
        const SizedBox(height: 6),
        Row(children: [
          TextButton(onPressed: () => launchUrl(Uri.parse('$siteUrl/terms'), mode: LaunchMode.externalApplication), child: Text(t('Terms'))),
          TextButton(onPressed: () => launchUrl(Uri.parse('$siteUrl/privacy'), mode: LaunchMode.externalApplication), child: Text(t('Privacy Policy'))),
        ]),
      ]),
      const SizedBox(height: 12),
      card(border: p.danger.withValues(alpha: .35), [
        title(t('Delete account'), color: p.danger),
        const SizedBox(height: 2),
        sub(t('Your page, asks, chats and photos are erased for good.')),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () async {
            final nav = Navigator.of(context);
            final auth = context.read<AuthProvider>();
            await deleteAccount(context);
            // deleted (and signed out): back to the first screen, which is now the sign-in
            if (!auth.isLoggedIn) nav.popUntil((r) => r.isFirst);
          },
          child: Text(t('Delete my account'), style: TextStyle(color: p.danger, fontWeight: FontWeight.w700)),
        ),
      ]),
    ]);
  }
}

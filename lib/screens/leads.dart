import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/post_card.dart';
import 'catalog.dart';
import 'edit_profile.dart';
import 'p2.dart';

/// P1 (docs/P1-MICRO-PLAN.md), as on the web: "Leads for you" (/leads) and "Your week" (/week); both have a circle
/// at the front of Updates (p2.dart).


Future<void> openLeads(BuildContext context) =>
    Navigator.push(context, WideRoute(builder: (_) => SubPage(title: t('Leads for you'), body: const LeadsScreen())));

Future<void> _editProfile(BuildContext context) async {
  final auth = context.read<AuthProvider>();
  final me = auth.profile;
  if (me == null) return;
  if (await Navigator.push<bool>(context, WideRoute(builder: (_) => EditProfileScreen(profile: me))) == true) auth.loadProfile();
}

/// "Leads for you": open asks matched to what this member does, new ones first. Each card says why it fits and how
/// many have replied; a card counts as seen once it is on screen, so the Connect count goes down.
class LeadsScreen extends StatefulWidget {
  const LeadsScreen({super.key});
  @override
  State<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends State<LeadsScreen> {
  List<Post>? _posts;
  LeadSummary? _sum;
  // alerts: how many the member has, and the sheet to set one (the investment that brings the next lead)
  int? _alerts;
  String? _saved;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    try {
      final d = (await api.get('/posts/leads') as List).map((e) => Post.fromJson(e as Map)).toList();
      if (mounted) setState(() => _posts = d);
    } catch (_) {
      if (mounted) setState(() => _posts = []);
    }
    try {
      final s = LeadSummary.fromJson(await api.get('/posts/leads/summary') as Map);
      if (mounted) setState(() => _sum = s);
    } catch (_) {}
    try {
      final r = await api.get('/alerts') as Map;
      if (mounted) setState(() => _alerts = ((r['alerts'] as List?) ?? const []).length);
    } catch (_) {
      if (mounted) setState(() => _alerts = 0);
    }
  }

  Future<void> _setAlert() async {
    final r = await showAlertSheet(context, label: alertSuggestions(context.read<AuthProvider>().profile).firstOrNull);
    if (r == null || !mounted) return;
    setState(() => _saved = savedMessage(r.openNow));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final posts = _posts;
    if (posts == null) return const PageLoader();
    final fresh = _sum?.unseen ?? posts.where((x) => x.leadNew).length;
    final open = _sum?.open ?? posts.length;
    return LogoRefresh(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, islandSpace(context)),
        children: [
          Row(children: [
            if (posts.isNotEmpty)
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    if (fresh > 0) TextSpan(text: '${t('{n} new', {'n': fresh})} · ', style: TextStyle(color: p.tagText)),
                    TextSpan(text: t(open == 1 ? '{n} open lead' : '{n} open leads', {'n': open})),
                  ]),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.muted),
                ),
              )
            else
              const Spacer(),
            // the way to set an alert stays here on busy days, when the card below is hidden
            if (_alerts != null && _alerts! == 0 && fresh > 0)
              GestureDetector(
                onTap: _setAlert,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  WIcon(WI.bell, size: 14, color: p.link),
                  const SizedBox(width: 4),
                  Text(_alerts! > 0 ? t(_alerts == 1 ? '1 alert' : '{n} alerts', {'n': _alerts!}) : t('Set an alert'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.link)),
                ]),
              ),
          ]),
          const SizedBox(height: 2),
          Text(t('Asks that fit what you do. Reply early: the first few replies get the most attention.'), style: TextStyle(fontSize: 14, color: p.muted)),
          // the investment that pays back: a fuller catalog is what asks find
          if (_sum?.catalogAdd != null)
            GestureDetector(
              onTap: () async {
                await Navigator.push(context, WideRoute(builder: (_) => const CatalogScreen()));
                _load();
              },
              child: Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: kGold.withValues(alpha: .15), border: Border.all(color: kGold.withValues(alpha: .5)), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      _sum!.category != null && _sum!.category!.isNotEmpty
                          ? t('Add {n} more to your catalog so asks for {c} find you', {'n': _sum!.catalogAdd!, 'c': _sum!.category!})
                          : t('Add {n} more to your catalog so the right asks find you', {'n': _sum!.catalogAdd!}),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Text('→'),
                ]),
              ),
            ),
          if (_saved != null)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: kGreen.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
              child: Text(_saved!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kGreen)),
            ),
          // no alert yet, and nothing new: the moment to let them choose their own trigger
          if (_alerts == 0 && fresh == 0)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: kGold.withValues(alpha: .1), border: Border.all(color: kGold.withValues(alpha: .6)), borderRadius: BorderRadius.circular(18)),
              child: Row(children: [
                WIcon(WI.bell, size: 24, color: p.tagText),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t('Get told first'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    Text(t('Set an alert for your trade and area. New asks that fit come straight to you.'), style: TextStyle(fontSize: 12, color: p.muted)),
                  ]),
                ),
                const SizedBox(width: 8),
                GoldButton(label: t('Set an alert'), height: 32, onPressed: _setAlert),
              ]),
            ),
          if (posts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(children: [
                Text(t('No open leads right now'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(t("New asks that fit your business will show here, and we'll tell you when one arrives."), textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: p.muted)),
              ]),
            ),
          for (final post in posts) PostCard(key: ValueKey(post.id), post: post, onChanged: _load),
          if (posts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: GestureDetector(
                onTap: () => _editProfile(context),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${t('Want better leads?')} '),
                    TextSpan(text: t('Add your services to your profile'), style: TextStyle(fontWeight: FontWeight.w600, color: p.link)),
                  ]),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: p.muted),
                ),
              ),
            ),
        ],
      ),
    );
  }
}


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

/// P1 (docs/P1-MICRO-PLAN.md), as on the web: the Today strip at the top of Connect (today-strip.tsx), "Leads for
/// you" (/leads) and "Your week" (/week).

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

bool _startOfWeekIST() {
  final day = DateTime.now().toUtc().add(const Duration(minutes: 330)).weekday;
  return day == DateTime.monday || day == DateTime.tuesday;
}


Future<void> openLeads(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => SubPage(title: t('Leads for you'), body: const LeadsScreen())));
Future<void> openWeek(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => SubPage(title: t('Your week'), body: const WeekScreen())));

Future<void> _editProfile(BuildContext context) async {
  final auth = context.read<AuthProvider>();
  final me = auth.profile;
  if (me == null) return;
  if (await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => EditProfileScreen(profile: me))) == true) auth.loadProfile();
}

/// Above Updates at the start of the week: "Your week". Leads for you and Today in your area are circles at the front
/// of the Updates row (connect.dart), where members already tap every day.
class TodayStrip extends StatefulWidget {
  const TodayStrip({super.key});
  @override
  State<TodayStrip> createState() => TodayStripState();
}

class TodayStripState extends State<TodayStrip> {
  WeekStats? _week;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (!_startOfWeekIST()) return;
    try {
      final w = WeekStats.fromJson(await context.read<AuthProvider>().api.get('/me/week') as Map);
      if (mounted) setState(() => _week = w);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final w = _week;
    if (w == null || !w.hasNews) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(color: p.card, border: Border.all(color: p.border), borderRadius: BorderRadius.circular(18)),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => openWeek(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                Text(w.won > 0 ? '🏆' : '📊', style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t('Your week'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    Text(
                      [
                        t(w.leads == 1 ? '{n} lead' : '{n} leads', {'n': w.leads}),
                        t(w.replied == 1 ? '{n} reply' : '{n} replies', {'n': w.replied}),
                        t('{n} won', {'n': w.won}),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: p.muted),
                    ),
                  ]),
                ),
                Text('›', style: TextStyle(fontSize: 20, color: p.muted)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
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
            // the way to alerts stays here on busy days, when the card below is hidden
            if (_alerts != null && (_alerts! > 0 || fresh > 0))
              GestureDetector(
                onTap: () async {
                  if (_alerts! > 0) {
                    await openAlerts(context);
                    _load();
                  } else {
                    _setAlert();
                  }
                },
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
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogScreen()));
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
                          ? t('Add {n} more catalog items so asks for {c} find you', {'n': _sum!.catalogAdd!, 'c': _sum!.category!})
                          : t('Add {n} more catalog items so the right asks find you', {'n': _sum!.catalogAdd!}),
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

/// "Your week" (the Monday scorecard): the last 7 days, rank in trade and area, and what to do next.
class WeekScreen extends StatefulWidget {
  const WeekScreen({super.key});
  @override
  State<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends State<WeekScreen> {
  WeekStats? _w;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    context.read<AuthProvider>().api.get('/me/week').then((d) {
      if (mounted) setState(() => _w = WeekStats.fromJson(d as Map));
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final w = _w;
    if (_failed) return Center(child: Text(t('Could not load. Please try again.'), style: TextStyle(color: p.muted)));
    if (w == null) return const PageLoader();
    final trade = (w.category ?? '').isEmpty ? '' : t(labelOf(kProfileCategories, w.category));
    final to = DateTime.now();
    final from = to.subtract(const Duration(days: 6));
    String day(DateTime d) => '${d.day} ${_months[d.month - 1]}';
    final tiles = [
      (w.leads, w.leads == 1 ? 'lead' : 'leads', false),
      (w.replied, w.replied == 1 ? 'reply sent' : 'replies sent', false),
      (w.won, 'won', w.won > 0),
      (w.askViews, 'views on your asks', false),
    ];
    Widget tile((int, String, bool) x) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: x.$3 ? kGoldGradient : null,
            color: x.$3 ? null : p.card,
            border: Border.all(color: x.$3 ? kGold : p.border),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${x.$1}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: x.$3 ? kInk : p.text)),
            Text(t(x.$2), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: x.$3 ? kInk.withValues(alpha: .75) : p.muted)),
          ]),
        );
    Widget row(String text, String action, VoidCallback onTap, {String? sub, bool bold = false}) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(text, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: bold ? p.text : p.muted)),
                  if (sub != null) Text(sub, style: TextStyle(fontSize: 12, color: p.muted)),
                ]),
              ),
              const SizedBox(width: 12),
              Text('$action →', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.link)),
            ]),
          ),
        );

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, islandSpace(context)),
      children: [
        Text('${day(from)} – ${day(to)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.muted)),
        const SizedBox(height: 12),
        Row(children: [Expanded(child: tile(tiles[0])), const SizedBox(width: 8), Expanded(child: tile(tiles[1]))]),
        const SizedBox(height: 8),
        Row(children: [Expanded(child: tile(tiles[2])), const SizedBox(width: 8), Expanded(child: tile(tiles[3]))]),
        if (w.rank != null && trade.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.chip.withValues(alpha: .4), border: Border.all(color: p.border), borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              const Text('🏅', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(text: '#${w.rank} ', style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(
                      text: w.rankArea != null
                          ? t('of {n} {trade} businesses in {area}', {'n': w.rankOf ?? 0, 'trade': trade, 'area': t(w.rankArea!)})
                          : t('of {n} {trade} businesses', {'n': w.rankOf ?? 0, 'trade': trade}),
                    ),
                  ]), style: const TextStyle(fontSize: 14)),
                  Text(t('By jobs won and replies over the last 30 days'), style: TextStyle(fontSize: 12, color: p.muted)),
                ]),
              ),
            ]),
          ),
        ],
        if (w.wonTotal > 0) ...[
          const SizedBox(height: 16),
          Text('🏆 ${t(w.wonTotal == 1 ? '{n} deal won on WEBWEB so far' : '{n} deals won on WEBWEB so far', {'n': w.wonTotal})}', style: const TextStyle(fontSize: 14)),
        ],
        if (w.responsesReceived > 0) ...[
          const SizedBox(height: 8),
          Text(t(w.responsesReceived == 1 ? '{n} response on your asks this week' : '{n} responses on your asks this week', {'n': w.responsesReceived}), style: const TextStyle(fontSize: 14)),
        ],
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(border: Border.all(color: p.border), borderRadius: BorderRadius.circular(18)),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: Column(children: [
              row(
                t(w.openLeads == 1 ? '{n} open lead' : '{n} open leads', {'n': w.openLeads}),
                t('See leads'),
                () => openLeads(context),
                bold: true,
                sub: w.newAsksInTrade > 0 && trade.isNotEmpty ? t('{n} new asks in {trade} this week', {'n': w.newAsksInTrade, 'trade': trade}) : null,
              ),
              Divider(height: 1, color: p.border),
              row(t('Add your services to get better matches'), t('Edit profile'), () => _editProfile(context)),
            ]),
          ),
        ),
      ],
    );
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../auth_provider.dart';
import '../i18n.dart';
import '../models.dart';
import '../safety.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/catalog_strip.dart';
import '../widgets/house_card.dart';
import '../widgets/post_card.dart';
import '../widgets/story_viewer.dart';
import '../widgets/tour.dart';
import 'edit_profile.dart';
import 'find.dart';
import 'leads.dart';
import 'p2.dart';

/// Connect (home), same as the web feed (feed-page.tsx): profile-strength strip, Updates row, then the
/// Asks timeline with a block after every third ask (a WEBWEB house card and a business catalog block taking turns)
/// and a WEBWEB Facts card after every tenth. Pull down to refresh (the W draws
/// itself), new asks are announced with a chip instead of shuffling the list.
class ConnectScreen extends StatefulWidget {
  final int refreshTick;
  final int topTick;
  final VoidCallback onGoAsk;
  const ConnectScreen({super.key, required this.refreshTick, this.topTick = 0, required this.onGoAsk});
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

const _page = 12;

class _ConnectScreenState extends State<ConnectScreen> {
  List<Post>? _posts;
  List<CatalogGroup> _catalog = [];
  /// WEBWEB house cards (API feed-cards.ts), taking turns with the business blocks; [_gone]: hidden from their menu
  List<HouseCard> _house = [];
  final Set<String> _gone = {};
  /// WEBWEB Facts posts: one after every 10th ask
  List<Post> _facts = [];
  List<Post> _fresh = [];
  String? _error;
  bool _hasMore = true;
  bool _loadingMore = false;
  Set<String> _blocked = {};
  int _offset = 0;
  final _scroll = ScrollController();
  final _updatesKey = GlobalKey<_UpdatesBarState>();
  final _todayKey = GlobalKey<TodayStripState>();
  Timer? _poll;
  bool _tourTried = false;

  Api get _api => context.read<AuthProvider>().api;

  @override
  void initState() {
    super.initState();
    _load();
    _loadCards();
    _api.get('/products/feed', {'limit': 10}).then((d) {
      if (mounted) setState(() => _catalog = (d as List).map((e) => CatalogGroup.fromJson(e as Map)).toList());
    }).catchError((_) {});
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _loadMore();
    });
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _checkFresh());
  }

  @override
  void didUpdateWidget(covariant ConnectScreen old) {
    super.didUpdateWidget(old);
    if (old.refreshTick != widget.refreshTick) _refresh();
    if (old.topTick != widget.topTick) _toTop();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _poll?.cancel();
    super.dispose();
  }

  void _toTop() {
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
  }

  Future<void> _load() async {
    try {
      final raw = (await _api.get('/posts', {'matched': 1, 'limit': _page}) as List).map((e) => Post.fromJson(e as Map)).toList();
      _blocked = await loadBlocked(_api);
      final d = raw.where((p) => !_blocked.contains(p.authorUid)).toList();
      if (!mounted) return;
      setState(() {
        _posts = d;
        _offset = d.length;
        _hasMore = d.length == _page;
        _error = null;
        _fresh = [];
      });
      // first visit: walk through the feed once it has something to point at
      if (!_tourTried) {
        _tourTried = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Tours.maybeShow(context, kConnectTourId, kConnectTour);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = t('Could not load posts. Please try again.'));
    }
  }

  /// The WEBWEB cards and facts (optional: the feed works without them).
  Future<void> _loadCards() async {
    await Future.wait([
      loadHouseCards(_api).then((c) {
        if (mounted) setState(() => _house = c);
      }).catchError((_) {}),
      loadFactPosts(_api).then((f) {
        if (mounted) setState(() => _facts = f);
      }).catchError((_) {}),
    ]);
  }

  /// Pull to refresh: posts, updates and the profile strength.
  Future<void> _refresh() async {
    await Future.wait([
      _load(),
      _loadCards(),
      _updatesKey.currentState?.load() ?? Future.value(),
      _todayKey.currentState?.load() ?? Future.value(),
      context.read<AuthProvider>().loadProfile(),
    ]);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _posts == null) return;
    setState(() => _loadingMore = true);
    try {
      final d = (await _api.get('/posts', {'matched': 1, 'limit': _page, 'offset': _offset}) as List).map((e) => Post.fromJson(e as Map)).toList();
      if (!mounted) return;
      _offset += d.length;
      setState(() {
        final seen = _posts!.map((p) => p.id).toSet();
        _posts = [..._posts!, ...d.where((p) => !seen.contains(p.id) && !_blocked.contains(p.authorUid))];
        _hasMore = d.length == _page;
      });
    } catch (_) {
      // stay put; the next scroll tries again
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Quietly look for newer posts; never shuffle the list under the reader.
  Future<void> _checkFresh() async {
    final cur = _posts;
    if (cur == null || !mounted) return;
    try {
      final latest = (await _api.get('/posts', {'limit': 20}) as List).map((e) => Post.fromJson(e as Map)).toList();
      final seen = cur.map((p) => p.id).toSet();
      final newest = cur.fold<int>(0, (m, p) => p.createdAt.millisecondsSinceEpoch > m ? p.createdAt.millisecondsSinceEpoch : m);
      final fresh = latest.where((p) => !seen.contains(p.id) && p.createdAt.millisecondsSinceEpoch > newest).toList();
      if (mounted && fresh.length != _fresh.length) setState(() => _fresh = fresh);
    } catch (_) {}
  }

  void _showFresh() {
    setState(() {
      _posts = [..._fresh, ...?_posts];
      _fresh = [];
    });
    _toTop();
  }

  /// The blocks between asks take turns: a WEBWEB card, then a business block; when one kind runs out the other fills in.
  List<Object> get _blocks {
    final cards = _house.where((c) => !_gone.contains(c.key)).toList();
    return [
      for (var k = 0; k < (cards.length > _catalog.length ? cards.length : _catalog.length); k++) ...[
        if (k < cards.length) cards[k],
        if (k < _catalog.length) _catalog[k],
      ],
    ];
  }

  Widget _block(Object b) => b is HouseCard
      ? HouseCardView(key: ValueKey('hc-${b.key}'), card: b, onGone: () => setState(() => _gone.add(b.key)))
      : CatalogStrip(key: ValueKey('cat-${(b as CatalogGroup).owner.uid}'), group: b);

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final posts = _posts;
    final firstAsk = posts?.indexWhere((x) => x.isRequirement) ?? -1;
    final blocks = _blocks;
    final slotCount = posts == null ? 0 : (posts.length < 3 ? (posts.isEmpty ? 0 : 1) : posts.length ~/ 3);
    final houseShown = blocks.take(slotCount).whereType<HouseCard>().length;
    final children = <Widget>[
      const _StrengthNudge(),
      // at the start of the week, your week (leads and Today are circles in Updates)
      TodayStrip(key: _todayKey),
      const SizedBox(height: 12),
      RuleHeading(WI.updates, t('Updates')),
      const SizedBox(height: 6),
      KeyedSubtree(key: Tours.key('updates'), child: _UpdatesBar(key: _updatesKey)),
      const SizedBox(height: 12),
      RuleHeading(WI.ask, t('Asks')),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(fontSize: 14, color: p.danger))),
      if (posts == null && _error == null) const PageLoader(),
      if (posts != null && posts.isEmpty) _empty(p),
      if (posts != null)
        for (var i = 0; i < posts.length; i++) ...[
          if (i == firstAsk)
            KeyedSubtree(key: Tours.key('first-ask'), child: PostCard(key: ValueKey(posts[i].id), post: posts[i], onBlocked: _load, tourTarget: true))
          else
            PostCard(key: ValueKey(posts[i].id), post: posts[i], onBlocked: _load),
          // one block after every 3rd ask: ask 3, 6, 9 ... (and after the last ask of a short feed)
          if (((i + 1) % 3 == 0 ? (i + 1) ~/ 3 - 1 : (posts.length < 3 && i == posts.length - 1 ? 0 : -1)) case final slot when slot >= 0 && slot < blocks.length) _block(blocks[slot]),
          // a short feed: WEBWEB cards that got no slot go after the last ask, up to 3 cards in all
          if (i == posts.length - 1) ...blocks.skip(slotCount).whereType<HouseCard>().take((3 - houseShown).clamp(0, 3)).map(_block),
          // a fact after ask 10, 20, 30 ... (a short feed of 4+ asks gets one at its end)
          if ((i + 1) % 10 == 0 && (i + 1) ~/ 10 - 1 < _facts.length)
            PostCard(key: ValueKey('fact-${_facts[(i + 1) ~/ 10 - 1].id}'), post: _facts[(i + 1) ~/ 10 - 1])
          else if (posts.length < 10 && posts.length >= 4 && i == posts.length - 1 && _facts.isNotEmpty)
            PostCard(key: ValueKey('fact-${_facts.first.id}'), post: _facts.first),
        ],
      if (posts != null && posts.isNotEmpty)
        (_loadingMore || _hasMore)
            ? const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: LogoLoader(size: 40)))
            : _EndOfFeed(count: posts.length, onAsk: widget.onGoAsk, onFind: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FindScreen(standalone: true))), onTop: _toTop),
    ];
    return Stack(children: [
      LogoRefresh(
        onRefresh: _refresh,
        child: ListView(
          controller: _scroll,
          padding: EdgeInsets.only(bottom: islandSpace(context)),
          // catalog strips scroll edge to edge (web -mx-4); everything else keeps the 16 px gutter
          children: [for (final c in children) c is CatalogStrip ? c : Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: c)],
        ),
      ),
      if (_fresh.isNotEmpty)
        Positioned(
          top: 8,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: _showFresh,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  gradient: kGoldGradient,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: const [BoxShadow(color: Color(0x2E1E1E1E), blurRadius: 28, spreadRadius: -12, offset: Offset(0, 10))],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const RotatedBox(quarterTurns: 3, child: WIcon(WI.arrow, size: 16, color: kInk, strokeWidth: 2.2)),
                  const SizedBox(width: 6),
                  Text(t(_fresh.length == 1 ? '{n} new ask' : '{n} new asks', {'n': _fresh.length}), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _empty(Pal p) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(children: [
          Text(t('Nothing here yet'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(t('Tap Ask to post a requirement or an update.'), textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: p.muted)),
        ]),
      );
}

// ======================= profile strength strip =======================

/// Own profile below 100 %: one thin edge-to-edge line with the percent and the single most valuable next step.
class _StrengthNudge extends StatefulWidget {
  const _StrengthNudge();
  @override
  State<_StrengthNudge> createState() => _StrengthNudgeState();
}

class _StrengthNudgeState extends State<_StrengthNudge> {
  static bool _hidden = false; // closed for this app session (web: sessionStorage)

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final me = context.watch<AuthProvider>().profile;
    final c = me?.completion;
    if (c == null || c.percent >= 100 || _hidden) return const SizedBox(height: 0);
    final next = c.next;
    final ink = p.dark ? const Color(0xFFFFD84A) : const Color(0xFF7A5A00);
    // the list has 16 px side padding; the strip reaches the screen edges like the web's -mx-4
    return SizedBox(
      height: 28,
      child: OverflowBox(
      maxWidth: MediaQuery.of(context).size.width,
      child: Container(
        height: 28,
        width: MediaQuery.of(context).size.width,
        padding: const EdgeInsets.only(left: 16, right: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [kGold.withValues(alpha: .2), kGold.withValues(alpha: .07), kGold.withValues(alpha: 0)]),
          border: Border(bottom: BorderSide(color: kGold.withValues(alpha: .2))),
        ),
        child: Row(children: [
          Text('${c.percent}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ink, fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                height: 4,
                color: p.text.withValues(alpha: .1),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(widthFactor: c.percent / 100, child: Container(decoration: const BoxDecoration(gradient: kGoldGradient))),
              ),
            ),
          ),
          if (next != null) ...[
            const SizedBox(width: 10),
            Flexible(
              child: GestureDetector(
                onTap: () async {
                  final auth = context.read<AuthProvider>();
                  if (await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => EditProfileScreen(profile: me!))) == true) auth.loadProfile();
                },
                child: Text('${t('Add')} ${t(next.label)} · +${next.weight}%', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ink)),
              ),
            ),
          ],
          GestureDetector(
            onTap: () => setState(() => _hidden = true),
            behavior: HitTestBehavior.opaque,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: Text('×', style: TextStyle(fontSize: 14, color: p.muted, height: 1.2))),
          ),
        ]),
      ),
      ),
    );
  }
}

// ======================= updates row =======================

const _seenKey = 'webweb_seen_updates';
const _dailySeenKey = 'webweb_seen_daily';

/// Updates row above the feed (web updates-bar.tsx): your tile first ("+" always adds), then everyone
/// else; gold ring = unseen, grey ring = seen.
class _UpdatesBar extends StatefulWidget {
  const _UpdatesBar({super.key});
  @override
  State<_UpdatesBar> createState() => _UpdatesBarState();
}

/// Paged: the first 12 people, then the next 12 as the row is swiped towards its end (and when the viewer
/// passes the last loaded person).
const _updatesPage = 12;

class _UpdatesBarState extends State<_UpdatesBar> {
  List<StoryGroup> _groups = [];
  // the daily circles: Leads for you by kind of ask, Today in your area by kind of item, New here
  LeadSummary? _leads;
  List<Post>? _leadList;
  TodayFeed? _today;
  List<Profile>? _biz;
  Set<String> _dailySeen = {};
  Set<String> _seen = {};
  bool _hasMore = false;
  Future<int>? _loadingMore;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((sp) {
      try {
        final ids = (jsonDecode(sp.getString(_seenKey) ?? '[]') as List).map((e) => '$e').toSet();
        final daily = (jsonDecode(sp.getString(_dailySeenKey) ?? '[]') as List).map((e) => '$e').toSet();
        if (mounted) {
          setState(() {
            _seen = ids;
            _dailySeen = daily;
          });
        }
      } catch (_) {}
    });
    _scroll.addListener(() {
      // within about three tiles of the end: fetch the next page
      if (_hasMore && _scroll.position.extentAfter < 300) _loadMore();
    });
    load();
  }

  Future<void> _daily() async {
    final api = context.read<AuthProvider>().api;
    await Future.wait([
      api.get('/posts/leads/summary').then((d) {
        if (mounted) setState(() => _leads = LeadSummary.fromJson(d as Map));
      }).catchError((_) {}),
      api.get('/posts/leads').then((d) {
        if (mounted) setState(() => _leadList = [for (final e in d as List) Post.fromJson(e as Map)]);
      }).catchError((_) {}),
      api.get('/today').then((d) {
        if (mounted) setState(() => _today = TodayFeed.fromJson(d as Map));
      }).catchError((_) {}),
      api.get('/today/new-businesses').then((d) {
        if (mounted) setState(() => _biz = [for (final e in d as List) Profile.fromJson(e as Map)]);
      }).catchError((_) {}),
    ]);
  }

  Future<void> _markDailySeen(String id) async {
    if (_dailySeen.contains(id) || !mounted) return;
    setState(() => _dailySeen = {..._dailySeen, id});
    final sp = await SharedPreferences.getInstance();
    final list = _dailySeen.toList();
    sp.setString(_dailySeenKey, jsonEncode(list.length > 500 ? list.sublist(list.length - 500) : list));
  }

  Future<void> load() async {
    _loadingMore = null;
    _daily();
    try {
      final d = await context.read<AuthProvider>().api.get('/updates?limit=$_updatesPage&offset=0') as List;
      if (mounted) {
        setState(() {
          _groups = d.map((e) => StoryGroup.fromJson(e as Map)).toList();
          _hasMore = d.length == _updatesPage;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _groups = []);
    }
  }

  /// The next page, added to the same list the viewer holds; resolves to how many people it added.
  Future<int> _loadMore() {
    if (!_hasMore) return Future.value(0);
    return _loadingMore ??= () async {
      try {
        final d = await context.read<AuthProvider>().api.get('/updates?limit=$_updatesPage&offset=${_groups.length}') as List;
        final known = {for (final g in _groups) g.uid};
        final fresh = [for (final e in d) StoryGroup.fromJson(e as Map)].where((g) => !known.contains(g.uid)).toList();
        if (mounted) {
          setState(() {
            _groups.addAll(fresh);
            _hasMore = d.length == _updatesPage;
          });
        }
        return fresh.length;
      } catch (_) {
        return 0;
      } finally {
        _loadingMore = null;
      }
    }();
  }

  Future<void> _markSeen(String id) async {
    if (_seen.contains(id)) return;
    setState(() => _seen = {..._seen, id});
    final sp = await SharedPreferences.getInstance();
    final list = _seen.toList();
    sp.setString(_seenKey, jsonEncode(list.length > 300 ? list.sublist(list.length - 300) : list));
  }

  Future<void> _open(int idx) async {
    final api = context.read<AuthProvider>().api;
    final me = context.read<AuthProvider>().profile?.uid;
    final deleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StoryViewer(
          groups: _groups,
          startGroup: idx,
          meUid: me,
          onSeen: _markSeen,
          onDelete: (id) async => api.delete('/updates/$id'),
          onLoadMore: _loadMore,
        ),
      ),
    );
    if (deleted == true) load();
  }

  Future<void> _compose() async {
    if (await showStoryComposer(context) == true) load();
  }

  bool _allSeen(StoryGroup g) => g.items.every((it) => _seen.contains(it.id));

  /// Before the member has said what they do there's nothing to match: what they do is the investment that brings leads.
  Widget _getLeadsTile(Pal p) => KeyedSubtree(
        key: Tours.key('today'),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            final auth = context.read<AuthProvider>();
            if (auth.profile == null) return;
            if (await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => EditProfileScreen(profile: auth.profile!))) == true) auth.loadProfile();
            _daily();
          },
          child: Container(
            width: 84,
            margin: const EdgeInsets.only(right: 12),
            child: Column(children: [
              Container(
                width: 74,
                height: 74,
                padding: const EdgeInsets.all(2.5),
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: kGoldGradient),
                child: Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: p.canvas),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: kGold.withValues(alpha: .15)),
                    child: const Text('✨', style: TextStyle(fontSize: 28, height: 1)),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(t('Get leads'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final me = context.watch<AuthProvider>().profile;
    final mineIdx = _groups.indexWhere((g) => g.uid == me?.uid);
    final others = [for (var i = 0; i < _groups.length; i++) if (_groups[i].uid != me?.uid) i];
    final api = context.read<AuthProvider>().api;
    final dailies = buildDailyGroups(leads: _leadList, today: _today, biz: _biz, seen: _dailySeen, api: api);
    // circles with something new come before people's updates, the ones already seen after them, as seen updates do
    final order = [...dailies.where((g) => g.fresh > 0), ...dailies.where((g) => g.fresh == 0)];
    Widget circle(DailyGroup g) => DailyCircle(
          key: ValueKey(g.id),
          group: g,
          onTap: () async {
            await openDailyStories(context, order, order.indexOf(g), _markDailySeen);
            _daily();
            // views of the leads go out in a batch a few seconds later: count again once they have
            Future.delayed(const Duration(milliseconds: 3500), () => mounted ? _daily() : null);
          },
        );
    final getLeads = _leads != null && !_leads!.hasTrade;
    return SizedBox(
      height: 100,
      child: ListView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        children: [
          _UpdateTile(
            name: me?.name ?? '',
            photoUrl: me?.photoUrl,
            label: t('Your update'),
            ring: mineIdx >= 0 ? (_allSeen(_groups[mineIdx]) ? _Ring.seen : _Ring.unseen) : _Ring.none,
            onTap: mineIdx >= 0 ? () => _open(mineIdx) : _compose,
            plus: _compose,
          ),
          if (getLeads) _getLeadsTile(p),
          for (final g in order.where((g) => g.fresh > 0)) circle(g),
          for (final i in others)
            _UpdateTile(
              name: _groups[i].shownName,
              photoUrl: _groups[i].photoUrl,
              label: _groups[i].shownName,
              type: _groups[i].userType,
              verification: _groups[i].verification,
              ring: _allSeen(_groups[i]) ? _Ring.seen : _Ring.unseen,
              onTap: () => _open(i),
            ),
          for (final g in order.where((g) => g.fresh == 0)) circle(g),
          if (_hasMore)
            const SizedBox(width: 48, child: Align(alignment: Alignment(0, -.45), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))),
          // the daily circles already fill an empty row
          if (others.isEmpty && dailies.isEmpty && !getLeads)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: SizedBox(
                  width: MediaQuery.of(context).size.width - 32 - 96,
                  child: Text(t('Updates from other members will show up here.'), style: TextStyle(fontSize: 12, color: p.muted)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _Ring { none, seen, unseen }

class _UpdateTile extends StatelessWidget {
  final String name, label;
  final String? photoUrl, type;
  final int verification;
  final _Ring ring;
  final VoidCallback onTap;
  final VoidCallback? plus;
  const _UpdateTile({required this.name, required this.label, this.photoUrl, this.type, this.verification = 0, required this.ring, required this.onTap, this.plus});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    const box = 74.0; // 64 photo + 2 x 2.5 ring + 2 x 2.5 gap
    final ini = Text(initials(name), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.muted));
    return Container(
      width: 84,
      margin: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(children: [
          SizedBox(
            width: box,
            height: box,
            child: Stack(clipBehavior: Clip.none, children: [
              Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: ring == _Ring.unseen ? kGoldGradient : null,
                  color: ring == _Ring.seen ? p.border : (ring == _Ring.none ? Colors.transparent : null),
                ),
                child: Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: p.canvas),
                  child: Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: p.chip),
                    child: (photoUrl ?? '').isNotEmpty
                        ? Image.network(mediaUrl(photoUrl!), width: 64, height: 64, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ini)
                        : ini,
                  ),
                ),
              ),
              // type badge (others) or the "+" (own tile), centred on the ring's 45 degree edge
              if (plus != null)
                Positioned(
                  left: box * .854 - 12,
                  top: box * .854 - 12,
                  child: GestureDetector(
                    onTap: plus,
                    child: Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(gradient: kGoldGradient, shape: BoxShape.circle, border: Border.all(color: p.canvas, width: 2)),
                      child: const WIcon(WI.plus, size: 16, color: kInk, strokeWidth: 3),
                    ),
                  ),
                )
              else if (type != null)
                Positioned(
                  left: box * .854 - 8.5,
                  top: box * .854 - 8.5,
                  child: Container(
                    width: 17,
                    height: 17,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: p.typeBadge, shape: BoxShape.circle, border: Border.all(color: p.canvas, width: 2)),
                    child: WIcon(type == 'entrepreneur' ? WI.business : WI.user, size: 9, color: p.onInk, strokeWidth: 2.4),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
            if (verification > 0) ...[const SizedBox(width: 2), VerifiedBadge(level: verification, size: 12)],
          ]),
        ]),
      ),
    );
  }
}

// ======================= end of feed =======================

class _EndOfFeed extends StatefulWidget {
  final int count;
  final VoidCallback onAsk, onFind, onTop;
  const _EndOfFeed({required this.count, required this.onAsk, required this.onFind, required this.onTop});
  @override
  State<_EndOfFeed> createState() => _EndOfFeedState();
}

class _EndOfFeedState extends State<_EndOfFeed> {
  int _play = 1; // plays once when it appears, again on every tap

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    Widget btn(String label, {WI? icon, String? glyph, bool gold = false, required VoidCallback onTap}) => GestureDetector(
          onTap: onTap,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(gradient: gold ? kGoldGradient : null, color: gold ? null : p.chip, borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) WIcon(icon, size: 16, color: gold ? kInk : p.text, strokeWidth: 1.9),
              if (glyph != null) Text(glyph, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
              const SizedBox(width: 6),
              Text(t(label), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: gold ? kInk : p.text)),
            ]),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
      child: Column(children: [
        GestureDetector(onTap: () => setState(() => _play++), child: AnimatedLogo(size: 44, playKey: _play)),
        const SizedBox(height: 12),
        Text(t("You're all caught up"), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(t(widget.count == 1 ? "That's all {n} ask near you for now." : "That's all {n} asks near you for now.", {'n': widget.count}),
            textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: p.muted)),
        const SizedBox(height: 16),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          btn('Post an Ask', icon: WI.ask, gold: true, onTap: widget.onAsk),
          btn('Find people', icon: WI.search, onTap: widget.onFind),
          btn('Back to top', glyph: '↑', onTap: widget.onTop),
        ]),
      ]),
    );
  }
}

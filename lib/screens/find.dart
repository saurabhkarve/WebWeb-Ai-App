import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/post_card.dart';
import 'post_detail.dart';
import 'profile.dart';

/// Find (web /find): one box for businesses, job seekers, jobs, asks and catalog items, with scope
/// chips, location / category selects and the budget / timing chips that asks link to. Before
/// anything is typed it shows the Explore grid (GET /explore).
class FindScreen extends StatefulWidget {
  /// pushed on its own (from an ask's chips or the end of the feed) rather than shown as a tab
  final bool standalone;
  final String? initialQuery, initialScope, initialLocation, initialBudget, initialUrgency;
  const FindScreen({super.key, this.standalone = false, this.initialQuery, this.initialScope, this.initialLocation, this.initialBudget, this.initialUrgency});
  @override
  State<FindScreen> createState() => _FindScreenState();
}

const _scopes = [('all', 'All'), ('business', 'Businesses'), ('catalog', 'Products & Services'), ('jobs', 'Jobs'), ('asks', 'Asks'), ('people', 'People')];

class _FindScreenState extends State<FindScreen> {
  late final _q = TextEditingController(text: widget.initialQuery ?? '');
  late String _scope = widget.initialScope ??
      ((widget.initialLocation ?? widget.initialBudget ?? widget.initialUrgency) != null ? 'asks' : 'all');
  late String _location = widget.initialLocation ?? '';
  String _askCat = '';
  late String _budget = widget.initialBudget ?? '';
  late String _urgency = widget.initialUrgency ?? '';

  List<Profile>? _users;
  List<Post>? _posts;
  List<Map<String, dynamic>>? _items;
  bool _loading = false;
  // more asks on scroll: the query behind the current results, and whether another page exists
  static const _page = 20;
  Map<String, String>? _postQuery;
  bool _postsMore = false, _loadingMore = false;
  // under Explore: the latest asks (or jobs), paged the same way
  List<Post>? _latest;
  String? _latestFor;
  bool _latestMore = false;
  Timer? _debounce;
  int _seq = 0;
  final _explore = GlobalKey<_ExploreState>();

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _run);
    setState(() {});
  }

  Future<void> _run() async {
    final q = _q.text.trim();
    final filtered = _location.isNotEmpty || _askCat.isNotEmpty || _budget.isNotEmpty || _urgency.isNotEmpty;
    final seq = ++_seq;
    if (q.length < 2 && !filtered) {
      setState(() {
        _users = _posts = null;
        _items = null;
        _loading = false;
        _postQuery = null;
        _postsMore = false;
      });
      _loadLatest(reset: true);
      return;
    }
    setState(() => _loading = true);
    final api = context.read<AuthProvider>().api;
    final wantUsers = _scope == 'all' || _scope == 'business' || _scope == 'people';
    final wantPosts = _scope == 'all' || _scope == 'jobs' || _scope == 'asks';
    final wantItems = _scope == 'all' || _scope == 'catalog';
    final hasText = q.length >= 2;
    final postQuery = <String, String>{
      'kind': 'requirement',
      if (hasText) 'search': q,
      if (_askCat.isNotEmpty || _scope == 'jobs') 'category': _askCat.isNotEmpty ? _askCat : 'job',
      if (_location.isNotEmpty) 'location': _location,
      if (_budget.isNotEmpty) 'budget': _budget,
      if (_urgency.isNotEmpty) 'urgency': _urgency,
    };
    _postQuery = wantPosts ? postQuery : null;
    _postsMore = false;
    try {
      final res = await Future.wait([
        // a category narrows asks only, so members and items drop out while it is set
        wantUsers && hasText && _askCat.isEmpty && _budget.isEmpty && _urgency.isEmpty
            ? api.get('/users/search', {'q': q, if (_scope != 'all') 'type': _scope}).then((d) {
                final all = (d as List).map((e) => Profile.fromJson(e as Map)).toList();
                return _location.isEmpty ? all : all.where((m) => m.location == _location).toList();
              })
            : Future.value(<Profile>[]),
        wantPosts
            ? api.get('/posts', {...postQuery, 'limit': '$_page'}).then((d) => (d as List).map((e) => Post.fromJson(e as Map)).toList())
            : Future.value(<Post>[]),
        wantItems && hasText && _askCat.isEmpty && _location.isEmpty && _budget.isEmpty && _urgency.isEmpty
            ? api.get('/products/search', {'q': q}).then((d) => (d as List).map((e) => Map<String, dynamic>.from(e as Map)).toList())
            : Future.value(<Map<String, dynamic>>[]),
      ]);
      if (!mounted || seq != _seq) return;
      setState(() {
        _users = res[0] as List<Profile>;
        _posts = res[1] as List<Post>;
        _items = res[2] as List<Map<String, dynamic>>;
        _postsMore = wantPosts && _posts!.length == _page;
      });
    } catch (_) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _users = [];
        _posts = [];
        _items = [];
      });
    } finally {
      if (mounted && seq == _seq) setState(() => _loading = false);
    }
  }

  /// Next page of search results.
  Future<void> _morePosts() async {
    final query = _postQuery, have = _posts;
    if (query == null || have == null || !_postsMore || _loadingMore) return;
    final seq = _seq;
    setState(() => _loadingMore = true);
    try {
      final d = await context.read<AuthProvider>().api.get('/posts', {...query, 'limit': '$_page', 'offset': '${have.length}'});
      final next = (d as List).map((e) => Post.fromJson(e as Map)).toList();
      if (!mounted || seq != _seq) return; // the search changed meanwhile
      final seen = {for (final x in have) x.id};
      setState(() {
        _posts = [...have, ...next.where((x) => !seen.contains(x.id))];
        _postsMore = next.length == _page;
      });
    } catch (_) {
      // the next scroll tries again
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// The latest asks (Jobs: latest jobs) under Explore, a page at a time.
  Future<void> _loadLatest({bool reset = false}) async {
    final want = _scope == 'all' || _scope == 'asks' || _scope == 'jobs';
    final key = _scope == 'jobs' ? 'job' : 'all';
    if (!want) {
      if (_latest != null) setState(() => _latest = null);
      return;
    }
    if (reset && _latestFor == key && _latest != null) return; // already showing this list
    if (!reset && (!_latestMore || _loadingMore)) return;
    final have = reset || _latestFor != key ? <Post>[] : (_latest ?? <Post>[]);
    _latestFor = key;
    setState(() => _loadingMore = true);
    try {
      final d = await context.read<AuthProvider>().api.get('/posts', {
        'kind': 'requirement',
        if (key == 'job') 'category': 'job',
        'limit': '$_page',
        'offset': '${have.length}',
      });
      final next = (d as List).map((e) => Post.fromJson(e as Map)).toList();
      if (!mounted || _latestFor != key) return;
      final seen = {for (final x in have) x.id};
      setState(() {
        _latest = [...have, ...next.where((x) => !seen.contains(x.id))];
        _latestMore = next.length == _page;
      });
    } catch (_) {
      // the next scroll tries again
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _set(void Function() f) {
    setState(f);
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final idle = _users == null && _posts == null && _items == null;
    final empty = _users?.isEmpty == true && _posts?.isEmpty == true && _items?.isEmpty == true;
    final bottom = widget.standalone ? MediaQuery.of(context).padding.bottom + 24 : islandSpace(context);

    Widget goldChip(String label, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(20)),
            child: Text('$label ✕', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kInk)),
          ),
        );

    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottom),
      children: [
        // search box
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(30)),
          child: Row(children: [
            WIcon(WI.search, size: 20, color: p.muted),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _q,
                onChanged: (_) => _changed(),
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: t('Search businesses, jobs, people, asks'),
                  hintStyle: TextStyle(color: p.muted, fontWeight: FontWeight.w500),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (_loading) const LogoLoader(size: 22)
            else if (_q.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _q.clear();
                  _changed();
                },
                child: WIcon(WI.close, size: 18, color: p.muted),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        // scopes
        SizedBox(
          height: 36,
          child: OverflowBox(
            maxWidth: MediaQuery.of(context).size.width,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _scopes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ScopeChip(label: t(_scopes[i].$2), selected: _scope == _scopes[i].$1, onTap: () => _set(() => _scope = _scopes[i].$1)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: SelectPill(value: _location, placeholder: t('Any location'), options: kLocations, onChanged: (v) => _set(() => _location = v))),
          const SizedBox(width: 8),
          Expanded(
            child: SelectPill(
              value: _askCat,
              placeholder: t('Any ask category'),
              options: [for (final c in kPostCategories) Option(c.value, t(kCategoryShort[c.value] ?? c.label))],
              onChanged: (v) => _set(() => _askCat = v),
            ),
          ),
        ]),
        if (_budget.isNotEmpty || _urgency.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              if (_budget.isNotEmpty) goldChip(_budget, () => _set(() => _budget = '')),
              if (_urgency.isNotEmpty) goldChip(t(labelOf(kUrgencies, _urgency)), () => _set(() => _urgency = '')),
            ]),
          ),
        const SizedBox(height: 16),
        if (idle) _Explore(key: _explore, scope: _scope),
        if (empty && !_loading) EmptyState(title: t('Nothing found'), hint: t('Try a different word or another tab.')),
        if (_users?.isNotEmpty == true) ...[
          if (_scope == 'all') _sectionLabel(p, 'Businesses & people'),
          ..._divided(p, [for (final u in _users!) _MemberRow(u)]),
          const SizedBox(height: 16),
        ],
        if (_items?.isNotEmpty == true) ...[
          if (_scope == 'all') Padding(padding: const EdgeInsets.only(bottom: 4), child: _sectionLabel(p, 'Products & services')),
          _Grid(gap: 8, children: [for (final it in _items!) _ItemTile(it)]),
          const SizedBox(height: 16),
        ],
        if (_posts?.isNotEmpty == true) ...[
          if (_scope == 'all') _sectionLabel(p, 'Asks & jobs'),
          for (final post in _posts!) PostCard(key: ValueKey(post.id), post: post),
          if (_postsMore || _loadingMore) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: LogoLoader(size: 32))),
        ],
        // under the discovery grid, the latest asks keep coming as you scroll
        if (idle && _latest?.isNotEmpty == true) ...[
          const SizedBox(height: 24),
          Text(t(_latestFor == 'job' ? 'Latest jobs' : 'Latest asks'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          for (final post in _latest!) PostCard(key: ValueKey('latest-${post.id}'), post: post),
          if (_latestMore || _loadingMore) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: LogoLoader(size: 32))),
        ],
      ],
    );
    // near the end of the list, fetch the next page
    final scrolling = NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.depth == 0 && n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 600) {
          if (idle) {
            _loadLatest();
          } else {
            _morePosts();
          }
        }
        return false;
      },
      child: list,
    );

    final body = LogoRefresh(
      onRefresh: () async {
        if (idle) {
          await _explore.currentState?.load();
        } else {
          await _run();
        }
      },
      child: scrolling,
    );
    if (!widget.standalone) return body;
    return SubPage(title: t('Find'), body: body);
  }

  Widget _sectionLabel(Pal p, String s) => Text(t(s), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.muted));
}

List<Widget> _divided(Pal p, List<Widget> rows) => [
      for (var i = 0; i < rows.length; i++)
        Container(
          decoration: i == 0 ? null : BoxDecoration(border: Border(top: BorderSide(color: p.border))),
          child: rows[i],
        ),
    ];

void _openProfile(BuildContext context, String handle) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: handle)));

/// Search hit for a member (web MemberRow).
class _MemberRow extends StatelessWidget {
  final Profile u;
  const _MemberRow(this.u);
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final name = displayName(u.userType, u.name, u.company);
    final sub = u.isEntrepreneur ? u.name : (u.skills.isEmpty ? t('Job seeker') : u.skills.take(3).join(' · '));
    return InkWell(
      onTap: () => _openProfile(context, u.handle),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          Avatar(name: name, photoUrl: u.photoUrl, size: 48, type: u.userType, badge: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                const SizedBox(width: 4),
                VerifiedBadge(level: u.verification, premium: u.premium),
              ]),
              Text('$sub · ${t(labelOf(kProfileCategories, u.category))} · ${u.location}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: p.muted)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Catalog search hit (web Find: 3 across, square photo, Product / Service tag, name, price, owner).
class _ItemTile extends StatelessWidget {
  final Map<String, dynamic> it;
  const _ItemTile(this.it);
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final owner = Peer.fromJson(it['owner'] as Map);
    final service = it['kind'] == 'service';
    final icon = service ? WI.service : WI.box;
    final img = it['imageUrl'] as String?;
    final price = it['price'] as String?;
    return Opacity(
      opacity: it['available'] == false ? .6 : 1,
      child: GestureDetector(
        onTap: () => _openProfile(context, owner.handle),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(fit: StackFit.expand, children: [
                if ((img ?? '').isNotEmpty) NetImg(img!) else ColoredBox(color: p.chip, child: Center(child: WIcon(icon, size: 28, color: p.muted))),
                Positioned(
                  left: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: kInk.withValues(alpha: .55), borderRadius: BorderRadius.circular(10)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      WIcon(icon, size: 10, color: Colors.white, strokeWidth: 2.4),
                      const SizedBox(width: 4),
                      Text(t(service ? 'Service' : 'Product'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, height: 1, color: Colors.white)),
                    ]),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${it['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.25)),
                if ((price ?? '').isNotEmpty) Text(price!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.25, color: p.link)),
                Text(owner.shownName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, height: 1.25, color: p.muted)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Simple 3-column grid that sizes itself to its children (no nested scrolling).
class _Grid extends StatelessWidget {
  final List<Widget> children;
  final double gap;
  const _Grid({required this.children, this.gap = 4});
  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 3) {
      if (i > 0) rows.add(SizedBox(height: gap));
      rows.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var j = i; j < i + 3; j++) ...[
            if (j > i) SizedBox(width: gap),
            Expanded(child: j < children.length ? children[j] : const SizedBox()),
          ],
        ]),
      ));
    }
    return Column(children: rows);
  }
}

// ======================= Explore (web explore.tsx) =======================

class _Explore extends StatefulWidget {
  final String scope;
  const _Explore({super.key, required this.scope});
  @override
  State<_Explore> createState() => _ExploreState();
}

class _ExploreState extends State<_Explore> {
  Map<String, dynamic>? _data;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final d = await context.read<AuthProvider>().api.get('/explore');
      if (mounted) {
        setState(() {
          _data = Map<String, dynamic>.from(d as Map);
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted && _data == null) setState(() => _failed = true);
    }
  }

  List<Map<String, dynamic>> _list(String k) => ((_data?[k] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    if (_failed) return Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Text(t('Could not load suggestions.'), textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: p.muted)));
    if (_data == null) return const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: LogoLoader(size: 32)));
    bool show(String s) => widget.scope == 'all' || widget.scope == s;
    final asks = _list('asks'), hiring = _list('hiring'), products = _list('products');
    final businesses = _list('businesses').map(Profile.fromJson).toList();
    final people = _list('people').map(Profile.fromJson).toList();

    Widget heading(String s) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t(s), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)));
    final sections = <Widget>[
      if (show('asks') && asks.isNotEmpty) Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [heading('Trending asks'), _TrendingGrid(asks)]),
      if (show('business') && businesses.isNotEmpty)
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          heading('Businesses to connect with'),
          SizedBox(
            height: 176,
            child: OverflowBox(
              maxWidth: MediaQuery.of(context).size.width,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: businesses.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _BusinessCard(businesses[i]),
              ),
            ),
          ),
        ]),
      if (show('jobs') && hiring.isNotEmpty)
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          heading('Hiring now'),
          Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
            clipBehavior: Clip.antiAlias,
            child: Column(children: _divided(p, [
              for (final j in hiring)
                InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailScreen(postId: '${j['id']}'))),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(children: [
                      Avatar(name: '${j['by']}', photoUrl: j['photoURL'] as String?, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${j['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          Text([j['by'], j['location'], j['budget']].where((e) => e != null && '$e'.isNotEmpty).join(' · '),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted)),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      Text(timeAgo(DateTime.fromMillisecondsSinceEpoch((j['createdAt'] as num).toInt())), style: TextStyle(fontSize: 12, color: p.muted)),
                    ]),
                  ),
                ),
            ])),
          ),
        ]),
      if (show('catalog') && products.isNotEmpty)
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          heading('Products & services'),
          _Grid(children: [
            for (final pr in products)
              GestureDetector(
                onTap: () => _openProfile(context, '${pr['handle']}'),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(fit: StackFit.expand, children: [
                      NetImg('${pr['imageUrl']}'),
                      const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xB3000000), Color(0x00000000), Color(0x00000000)]))),
                      Positioned(
                        left: 6,
                        right: 6,
                        bottom: 6,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${pr['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, height: 1.25, color: Colors.white)),
                          Text('${(pr['price'] as String?)?.isNotEmpty == true ? pr['price'] : pr['by']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, height: 1.25, color: Colors.white.withValues(alpha: .85))),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
          ]),
        ]),
      if (show('people') && people.isNotEmpty)
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          heading('People looking for work'),
          ..._divided(p, [
            for (final u in people)
              InkWell(
                onTap: () => _openProfile(context, u.handle),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(children: [
                    Avatar(name: u.name, photoUrl: u.photoUrl, size: 44, type: u.userType),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Flexible(child: Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                          const SizedBox(width: 4),
                          VerifiedBadge(level: u.verification, premium: u.premium),
                        ]),
                        Text(
                          [u.skills.isEmpty ? t(labelOf(kProfileCategories, u.category)) : u.skills.take(3).join(' · '), u.location].where((e) => e.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: p.muted),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
          ]),
        ]),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < sections.length; i++) ...[if (i > 0) const SizedBox(height: 24), sections[i]],
    ]);
  }
}

/// Instagram-style grid: the first ask takes a 2x2 block, the rest fill three across.
class _TrendingGrid extends StatelessWidget {
  final List<Map<String, dynamic>> asks;
  const _TrendingGrid(this.asks);
  @override
  Widget build(BuildContext context) {
    const gap = 4.0;
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 2 * gap) / 3;
      Widget tile(int i) => SizedBox.square(dimension: i == 0 ? 2 * w + gap : w, child: _AskTile(asks[i], big: i == 0));
      final rows = <Widget>[
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          tile(0),
          if (asks.length > 1) ...[
            const SizedBox(width: gap),
            Column(children: [tile(1), if (asks.length > 2) ...[const SizedBox(height: gap), tile(2)]]),
          ],
        ]),
      ];
      for (var i = 3; i < asks.length; i += 3) {
        rows.add(const SizedBox(height: gap));
        rows.add(Row(children: [
          for (var j = i; j < i + 3 && j < asks.length; j++) ...[if (j > i) const SizedBox(width: gap), tile(j)],
        ]));
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
    });
  }
}

class _AskTile extends StatelessWidget {
  final Map<String, dynamic> a;
  final bool big;
  const _AskTile(this.a, {this.big = false});
  @override
  Widget build(BuildContext context) {
    final cat = a['category'] as String?;
    final img = a['image'] as String?;
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailScreen(postId: '${a['id']}'))),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(fit: StackFit.expand, children: [
          if ((img ?? '').isNotEmpty) NetImg(img!) else CoverPattern(seed: '${a['id']}'),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xB3000000), Color(0x1A000000), Color(0x00000000)]),
            ),
          ),
          if (cat != null)
            Positioned(
              left: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: .55), borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  WIcon(categoryIcon(cat), size: 10, color: Colors.white),
                  const SizedBox(width: 4),
                  Text((a['categoryLabel'] as String?) ?? t(kCategoryShort[cat] ?? 'Ask'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                ]),
              ),
            ),
          Positioned(
            left: 6,
            right: 6,
            bottom: 6,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${a['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: big ? 14 : 11, fontWeight: FontWeight.w700, height: 1.25, color: Colors.white)),
              if (big) Padding(padding: const EdgeInsets.only(top: 2), child: Text('${a['by']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: .8)))),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// web explore BusinessCard: banner, overlapping avatar, name + badge, category · area, "View page".
class _BusinessCard extends StatelessWidget {
  final Profile u;
  const _BusinessCard(this.u);
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final name = displayName(u.userType, u.name, u.company);
    return GestureDetector(
      onTap: () => _openProfile(context, u.handle),
      child: Container(
        width: 160,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
        child: Column(children: [
          SizedBox(height: 56, width: double.infinity, child: (u.bannerUrl ?? '').isNotEmpty ? NetImg(u.bannerUrl!) : CoverPattern(seed: u.handle)),
          Transform.translate(
            offset: const Offset(0, -24),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(children: [
                Container(padding: const EdgeInsets.all(2), decoration: BoxDecoration(color: p.card, shape: BoxShape.circle), child: Avatar(name: name, photoUrl: u.photoUrl, size: 48)),
                const SizedBox(height: 4),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.25))),
                  const SizedBox(width: 4),
                  VerifiedBadge(level: u.verification, premium: u.premium, size: 14),
                ]),
                Text([t(labelOf(kProfileCategories, u.category)), u.location].where((e) => e.isNotEmpty).join(' · '),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(20)),
                  child: Text(t('View page'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Old name for [ScopeChip], used by screens not yet moved over.
class FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const FilterPill({super.key, required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => ScopeChip(label: label, selected: selected, onTap: onTap);
}

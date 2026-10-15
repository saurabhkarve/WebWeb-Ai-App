import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../auth_provider.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/post_card.dart';
import '../widgets/story_viewer.dart';

/// Connect tab: Updates (24h stories) + the Asks / updates feed (GET /posts?matched=1, newest + relevance first).
class ConnectScreen extends StatefulWidget {
  final int refreshTick;
  final VoidCallback onGoAsk;
  const ConnectScreen({super.key, required this.refreshTick, required this.onGoAsk});
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  List<StoryGroup> _stories = [];
  List<Post> _posts = [];
  bool _loading = true;
  bool _more = true;
  bool _loadingMore = false;
  String? _error;
  final _scroll = ScrollController();

  Api get _api => context.read<AuthProvider>().api;

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _loadMore();
    });
  }

  @override
  void didUpdateWidget(covariant ConnectScreen old) {
    super.didUpdateWidget(old);
    if (old.refreshTick != widget.refreshTick) _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([_api.get('/posts', {'matched': 1, 'limit': 30}), _api.get('/stories')]);
      if (!mounted) return;
      setState(() {
        _posts = (results[0] as List).map((e) => Post.fromJson(e as Map)).toList();
        _stories = (results[1] as List).map((e) => StoryGroup.fromJson(e as Map)).toList();
        _more = _posts.length >= 30;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_more || _posts.isEmpty) return;
    _loadingMore = true;
    try {
      final d = (await _api.get('/posts', {'before': _posts.last.createdAt.millisecondsSinceEpoch, 'limit': 30}) as List).map((e) => Post.fromJson(e as Map)).toList();
      if (mounted) setState(() {
        _posts.addAll(d.where((x) => !_posts.any((y) => y.id == x.id)));
        _more = d.length >= 30;
      });
    } catch (_) {
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> _addStory() async {
    if (await showStoryComposer(context) == true) _load();
  }

  Future<void> _openStories(int index) async {
    final me = context.read<AuthProvider>().profile?.uid;
    final deleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => StoryViewer(groups: _stories, startGroup: index, meUid: me, onDelete: (id) async => _api.delete('/stories/$id'))),
    );
    if (deleted == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final me = context.watch<AuthProvider>().profile;
    final mineIdx = _stories.indexWhere((g) => g.uid == me?.uid);
    final others = [for (var i = 0; i < _stories.length; i++) if (i != mineIdx) i];
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: kGold,
        onRefresh: _load,
        child: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
          const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Align(alignment: Alignment.centerLeft, child: LogoInline())),
          const SizedBox(height: 8),
          const RuleHeading(Icons.campaign_outlined, 'UPDATES'),
          const SizedBox(height: 12),
          SizedBox(
            height: 96,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              _tile(
                avatar: Stack(clipBehavior: Clip.none, children: [
                  Avatar(name: me?.name ?? '?', photoUrl: me?.photoUrl, size: 62, ring: mineIdx >= 0),
                  Positioned(right: -4, bottom: -2, child: Container(width: 24, height: 24, decoration: const BoxDecoration(color: kGold, shape: BoxShape.circle), child: const Icon(Icons.add, size: 18, color: Color(0xFF1E1E1E)))),
                ]),
                label: 'Your update',
                onTap: mineIdx >= 0 ? () => _openStories(mineIdx) : _addStory,
                onLongPress: _addStory,
              ),
              for (final i in others)
                _tile(avatar: Avatar(name: _stories[i].name, photoUrl: _stories[i].photoUrl, size: 62, ring: true), label: _stories[i].name, onTap: () => _openStories(i)),
            ]),
          ),
          const SizedBox(height: 14),
          const RuleHeading(Icons.back_hand_outlined, 'ASKS'),
          if (_loading) const Padding(padding: EdgeInsets.all(40), child: PageLoader()),
          if (_error != null) Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: p.muted))),
          if (!_loading && _error == null && _posts.isEmpty)
            Padding(padding: const EdgeInsets.all(24), child: Column(children: [
              Text('Nothing here yet', style: TextStyle(color: p.muted, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              GoldButton(label: 'Post an ask', onPressed: widget.onGoAsk),
            ])),
          for (final post in _posts) PostCard(key: ValueKey(post.id), post: post),
          if (_loadingMore) const Padding(padding: EdgeInsets.all(16), child: PageLoader(size: 36)),
        ]),
      ),
    );
  }

  Widget _tile({required Widget avatar, required String label, required VoidCallback onTap, VoidCallback? onLongPress}) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 78,
        margin: const EdgeInsets.only(right: 8),
        child: Column(children: [
          avatar,
          const SizedBox(height: 6),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

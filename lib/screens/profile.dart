import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import '../auth_provider.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/post_card.dart';
import '../widgets/story_viewer.dart';
import 'catalog.dart';
import 'edit_profile.dart';
import 'find.dart' show FilterPill;
import 'post_detail.dart';
import 'talk.dart';

/// One profile for everyone: the Profile tab (own, [handle] == null) and any member's page.
/// Contact numbers are never shown in full; people reach you through Talk, Call or "Ask contact".
class ProfileScreen extends StatefulWidget {
  final String? handle;
  const ProfileScreen({super.key, this.handle});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

enum _Tab { posts, deals, stories, products }

class _ProfileScreenState extends State<ProfileScreen> {
  Profile? _u;
  String? _error;
  _Tab? _tabSel;
  List<Post>? _posts;
  List<Deal>? _deals;
  List<AskItem> _asks = [];
  List<StoryItem>? _stories;
  List<Product>? _products;
  bool _requested = false;

  Api get _api => context.read<AuthProvider>().api;
  bool get _own => widget.handle == null || widget.handle == context.read<AuthProvider>().profile?.handle;
  String get _handle => widget.handle ?? context.read<AuthProvider>().profile!.handle;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final u = Profile.fromJson(await _api.get('/users/handle/$_handle') as Map);
      if (!mounted) return;
      setState(() {
        _u = u;
        _error = null;
      });
      _loadTabs(u);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _loadTabs(Profile u) async {
    final api = _api;
    api.get('/users/${u.uid}/products').then((d) {
      if (mounted) setState(() => _products = (d as List).map((e) => Product.fromJson(e as Map)).toList());
    }).catchError((_) {
      if (mounted) setState(() => _products = []);
    });
    api.get('/posts', {'authorId': u.uid, 'limit': 30}).then((d) {
      if (mounted) setState(() => _posts = (d as List).map((e) => Post.fromJson(e as Map)).toList());
    }).catchError((_) {
      if (mounted) setState(() => _posts = []);
    });
    api.get('/users/${u.uid}/stories').then((d) {
      if (mounted) setState(() => _stories = (d as List).map((e) => StoryItem.fromJson(e as Map)).toList());
    }).catchError((_) {
      if (mounted) setState(() => _stories = []);
    });
    _loadDeals(u);
  }

  void _loadDeals(Profile u) {
    _api.get('/users/${u.uid}/deals').then((d) {
      if (mounted) setState(() => _deals = (d as List).map((e) => Deal.fromJson(e as Map)).toList());
    }).catchError((_) {
      if (mounted) setState(() => _deals = []);
    });
    if (_own) {
      _api.get('/posts/asks/me').then((d) {
        if (mounted) setState(() => _asks = (d as List).map((e) => AskItem.fromJson(e as Map)).toList());
      }).catchError((_) {});
    }
  }

  Future<void> _message() async => openChat(context, Peer.fromProfile(_u!));

  Future<void> _askContact() async {
    try {
      await _api.post('/users/${_u!.uid}/contact-request');
      if (mounted) setState(() => _requested = true);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  Future<void> _shareLink() async {
    final text = '${_u!.name} · ${_u!.company}\nhttps://webweb.ai/@${_u!.handle}';
    try {
      await Share.share(text);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) toast(context, 'Link copied');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final u = _u;
    if (u == null) {
      return Scaffold(
        appBar: widget.handle == null ? null : AppBar(),
        body: _error != null ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: p.muted)))) : const PageLoader(),
      );
    }
    final isJob = u.isJobSeeker;
    final own = _own;
    final tabs = own && !isJob
        ? [_Tab.posts, _Tab.deals, _Tab.stories, _Tab.products]
        : [_Tab.products, _Tab.posts, _Tab.deals, _Tab.stories];
    final tab = _tabSel ?? (own && !isJob ? _Tab.posts : _Tab.products);
    return Scaffold(
      body: RefreshIndicator(
        color: kGold,
        onRefresh: _load,
        child: ListView(padding: EdgeInsets.zero, children: [
          SizedBox(
            height: 160,
            child: Stack(clipBehavior: Clip.none, children: [
              Container(height: 112, decoration: const BoxDecoration(gradient: kGoldGradient)),
              if (widget.handle != null && !own)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 6,
                  left: 12,
                  child: CircleAvatar(backgroundColor: Colors.black38, child: IconButton(icon: const Icon(Icons.chevron_left, color: Colors.white, size: 26), onPressed: () => Navigator.pop(context))),
                ),
              Positioned(left: 16, top: 112 - 40, child: Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(color: p.canvas, shape: BoxShape.circle), child: Avatar(name: u.name, size: 80, ring: true, photoUrl: u.photoUrl))),
              Positioned(
                right: 16,
                top: 124,
                child: own
                    ? OutlinedButton.icon(
                        onPressed: () async {
                          if (await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => EditProfileScreen(profile: u))) == true) _load();
                        },
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit'),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(20), border: Border.all(color: p.border)),
                        child: Text(labelOf(kUserTypes, u.userType), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(u.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
              Text('@${u.handle}', style: const TextStyle(color: kGold, fontWeight: FontWeight.w700)),
              Text(u.company, style: TextStyle(color: p.muted, fontWeight: FontWeight.w500)),
              if ((u.bio ?? '').isNotEmpty) ...[const SizedBox(height: 10), Text(u.bio!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))],
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                InfoPill(icon: Icons.location_on_outlined, text: u.location),
                InfoPill(text: u.category),
                if (own) InfoPill(text: labelOf(kUserTypes, u.userType)),
                if ((u.contactMasked ?? '').isNotEmpty && !own) InfoPill(icon: Icons.call_outlined, text: u.contactMasked!),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: _stat('${u.statPosts ?? '–'}', 'Asks', p)),
                const SizedBox(width: 8),
                Expanded(child: _stat('${u.statShared ?? '–'}', 'Connects', p)),
                const SizedBox(width: 8),
                Expanded(child: _stat('${u.contributions}', 'Contributions', p)),
              ]),
              const SizedBox(height: 16),
              if (own)
                SizedBox(width: double.infinity, child: GoldButton(label: 'Share my page', icon: Icons.share_outlined, onPressed: _shareLink))
              else ...[
                Row(children: [
                  Expanded(child: GoldButton(label: 'Talk', icon: Icons.chat_bubble_outline, onPressed: _message)),
                  const SizedBox(width: 10),
                  Expanded(child: GoldButton(label: 'Call', icon: Icons.call_outlined, outlined: true, onPressed: () => placeCall(context, Peer.fromProfile(u), false))),
                ]),
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: GoldButton(label: _requested ? 'Requested' : 'Ask contact', icon: Icons.person_add_alt, outlined: true, onPressed: _requested ? null : _askContact)),
              ],
              const SizedBox(height: 18),
            ]),
          ),
          Container(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
            child: Row(children: [
              for (final t in tabs)
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _tabSel = t),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tab == t ? p.text : Colors.transparent, width: 2))),
                      child: Column(children: [
                        Icon(_tabIcon(t, isJob), size: 18, color: tab == t ? p.text : p.muted),
                        const SizedBox(height: 3),
                        Text(_tabLabel(t, isJob), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tab == t ? p.text : p.muted)),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: _tabBody(tab, u, p)),
          if (own) _settings(u),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  Widget _stat(String v, String l, Pal p) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.border.withValues(alpha: .6))),
        child: Column(children: [Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)), Text(l, style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w600))]),
      );

  static IconData _tabIcon(_Tab t, bool job) => switch (t) {
        _Tab.posts => Icons.grid_view_outlined,
        _Tab.deals => Icons.handshake_outlined,
        _Tab.stories => Icons.auto_stories_outlined,
        _Tab.products => job ? Icons.description_outlined : Icons.inventory_2_outlined,
      };

  static String _tabLabel(_Tab t, bool job) => switch (t) {
        _Tab.posts => 'Posts',
        _Tab.deals => 'Deals',
        _Tab.stories => 'Stories',
        _Tab.products => job ? 'Resume' : 'Products',
      };

  Widget _empty(String t, Pal p) => Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Center(child: Text(t, textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontWeight: FontWeight.w500))));

  Widget _tabBody(_Tab tab, Profile u, Pal p) {
    switch (tab) {
      case _Tab.posts:
        if (_posts == null) return const Padding(padding: EdgeInsets.all(24), child: PageLoader(size: 40));
        if (_posts!.isEmpty) return _empty('No posts yet.', p);
        return Column(children: [for (final x in _posts!) PostCard(key: ValueKey(x.id), post: x)]);
      case _Tab.deals:
        return _deals == null ? const Padding(padding: EdgeInsets.all(24), child: PageLoader(size: 40)) : _dealsBody(p);
      case _Tab.stories:
        if (_stories == null) return const Padding(padding: EdgeInsets.all(24), child: PageLoader(size: 40));
        if (_stories!.isEmpty) return _empty('No stories yet.', p);
        return GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: 3 / 4,
          children: [
            for (final s in _stories!)
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StoryViewer(groups: [StoryGroup(uid: u.uid, name: u.name, handle: u.handle, photoUrl: u.photoUrl, items: [s])]))),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: s.imageUrl != null
                      ? Image.network(mediaUrl(s.imageUrl!), fit: BoxFit.cover)
                      : Container(color: p.chip, padding: const EdgeInsets.all(8), alignment: Alignment.center, child: Text(s.text ?? '', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                ),
              ),
          ],
        );
      case _Tab.products:
        return u.isJobSeeker ? _resume(u, p) : _catalog(u, p);
    }
  }

  Widget _dealsBody(Pal p) {
    const kind = {'contact': 'contact', 'media': 'a photo', 'info': 'information'};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_asks.isNotEmpty) ...[
        const Text('Asked you to share', style: TextStyle(fontWeight: FontWeight.w700)),
        for (final a in _asks)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${a.ownerName} (${a.ownerCompany}) asked you to reveal ${kind[a.kind] ?? a.kind} for "${a.postTitle}"'),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: GoldButton(label: 'Approve', onPressed: () => _answer(a, true))),
                const SizedBox(width: 10),
                Expanded(child: GoldButton(label: 'Decline', outlined: true, onPressed: () => _answer(a, false))),
              ]),
            ]),
          ),
        const SizedBox(height: 14),
      ],
      if (_deals!.isEmpty)
        _empty('No deals yet. Respond to asks to build your track record.', p)
      else
        for (final d in _deals!)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.check_circle, color: kGreen, size: 28),
            title: Text(d.postTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
            subtitle: Text('Shared ${kind[d.kind] ?? d.kind} with ${d.ownerName} · ${timeAgo(d.createdAt)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12.5)),
            trailing: Text('${d.rating == 1 ? '👍' : d.rating == -1 ? '👎' : ''}${d.reaction == null ? '' : kReactionEmoji[d.reaction] ?? ''}', style: const TextStyle(fontSize: 18)),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailScreen(postId: d.postId))),
          ),
    ]);
  }

  Future<void> _answer(AskItem a, bool approve) async {
    try {
      await _api.post('/posts/${a.postId}/share/answer', {'approve': approve});
      if (mounted && _u != null) _loadDeals(_u!);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  Widget _catalog(Profile u, Pal p) {
    final all = _products;
    if (all == null) return const Padding(padding: EdgeInsets.all(24), child: PageLoader(size: 40));
    final goods = all.where((x) => x.kind != 'service').toList();
    final offered = all.where((x) => x.kind == 'service').toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (goods.isNotEmpty) ...[
        const Text('Catalog', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: .8,
          children: [
            for (final g in goods)
              Opacity(
                opacity: g.available ? 1 : .55,
                child: Container(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
                  clipBehavior: Clip.antiAlias,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: SizedBox(width: double.infinity, child: g.imageUrl != null ? Image.network(mediaUrl(g.imageUrl!), fit: BoxFit.cover) : Container(color: p.chip, child: Icon(Icons.inventory_2_outlined, size: 36, color: p.muted)))),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                        if ((g.price ?? '').isNotEmpty) Text(g.price!, style: const TextStyle(color: kGold, fontWeight: FontWeight.w800)),
                        if (!g.available) Text('Unavailable', style: TextStyle(color: p.muted, fontSize: 12)),
                      ]),
                    ),
                  ]),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
      ],
      if (offered.isNotEmpty || u.services.isNotEmpty) ...[
        const Text('Services', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 8),
        for (final s in offered)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
            child: Row(children: [
              if (s.imageUrl != null) Padding(padding: const EdgeInsets.only(right: 12), child: NetImage(s.imageUrl, size: 48)),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)), if ((s.description ?? '').isNotEmpty) Text(s.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12.5))])),
              if ((s.price ?? '').isNotEmpty) Text(s.price!, style: const TextStyle(color: kGold, fontWeight: FontWeight.w800)),
            ]),
          ),
        for (final s in u.services) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.check_circle_outline, size: 18, color: kGold), const SizedBox(width: 8), Expanded(child: Text(s))])),
      ],
      if (all.isEmpty && u.services.isEmpty) _empty(_own ? 'Add your products and services so people can find you.' : 'Nothing listed yet.', p),
      if (_own) ...[
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: GoldButton(label: 'Manage catalog', outlined: true, icon: Icons.edit_outlined, onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogScreen()));
            if (_u != null) _loadTabs(_u!);
          }),
        ),
      ],
    ]);
  }

  /// One resume entry per line; "Role · Company · Years" renders as title + detail.
  Widget _resumeList(String title, String? text, Pal p) {
    final rows = (text ?? '').split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.only(left: 14),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: p.border, width: 2))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Builder(builder: (_) {
                  final parts = r.split(RegExp(r'\s[·|]\s'));
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(parts.first, style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (parts.length > 1) Text(parts.skip(1).join(' · '), style: TextStyle(color: p.muted, fontSize: 13)),
                  ]);
                }),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _resume(Profile u, Pal p) {
    final empty = u.skills.isEmpty && (u.experience ?? '').isEmpty && (u.education ?? '').isEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (u.skills.isNotEmpty) ...[
        const Text('Skills', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final s in u.skills) InfoPill(text: s)]),
        const SizedBox(height: 16),
      ],
      _resumeList('Experience', u.experience, p),
      _resumeList('Education', u.education, p),
      if (empty) _empty(_own ? 'Add your skills, experience and education.' : 'No resume details yet.', p),
      if (_own)
        SizedBox(
          width: double.infinity,
          child: GoldButton(label: 'Update resume', outlined: true, onPressed: () async {
            if (await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => EditProfileScreen(profile: u))) == true) _load();
          }),
        ),
    ]);
  }

  // ---------- own-profile settings ----------
  Widget _settings(Profile u) {
    final p = Pal.of(context);
    final theme = context.watch<ThemeController>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Divider(color: p.border),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: GoldButton(label: 'Saved posts', outlined: true, icon: Icons.bookmark_border, onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _SavedPosts())))),
        const SizedBox(height: 18),
        Text('Appearance', style: TextStyle(color: p.muted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          height: 52,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(30), border: Border.all(color: p.border)),
          child: Row(children: [
            for (final m in [(ThemeMode.system, 'System'), (ThemeMode.light, 'Light'), (ThemeMode.dark, 'Dark')])
              Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: FilterPill(label: m.$2, selected: theme.mode == m.$1, onTap: () => theme.set(m.$1)))),
          ]),
        ),
        const SizedBox(height: 18),
        SizedBox(width: double.infinity, child: GoldButton(label: 'Log out', icon: Icons.logout, outlined: true, onPressed: () => context.read<AuthProvider>().logout())),
      ]),
    );
  }
}

class _SavedPosts extends StatefulWidget {
  const _SavedPosts();
  @override
  State<_SavedPosts> createState() => _SavedPostsState();
}

class _SavedPostsState extends State<_SavedPosts> {
  List<Post>? _posts;
  @override
  void initState() {
    super.initState();
    context.read<AuthProvider>().api.get('/posts/bookmarks').then((d) {
      if (mounted) setState(() => _posts = (d as List).map((e) => Post.fromJson(e as Map)).toList());
    }).catchError((_) {
      if (mounted) setState(() => _posts = []);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Saved posts', style: TextStyle(fontWeight: FontWeight.w700))),
        body: _posts == null
            ? const PageLoader()
            : _posts!.isEmpty
                ? Center(child: Text('Nothing saved yet', style: TextStyle(color: Pal.of(context).muted, fontWeight: FontWeight.w600)))
                : ListView(padding: const EdgeInsets.all(16), children: [for (final x in _posts!) PostCard(key: ValueKey(x.id), post: x)]),
      );
}

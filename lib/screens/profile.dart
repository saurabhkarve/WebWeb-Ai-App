import 'dart:ui' as ui;


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../auth_provider.dart';
import '../config.dart';
import '../i18n.dart';
import '../models.dart';
import '../safety.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/post_card.dart';
import '../widgets/qr_card.dart';
import '../widgets/catalog_strip.dart' show CatalogItemCard;
import '../widgets/story_viewer.dart';
import 'catalog.dart';
import 'edit_profile.dart';
import 'find.dart';
import 'post_detail.dart';
import 'talk.dart';
import '../share_log.dart';
import '../widgets/picture_picker.dart';
import '../widgets/resume.dart';
import '../widgets/upi.dart';
import '../widgets/p1.dart' show OfferChips;
import '../widgets/area_map.dart' show AreaMap;

/// One profile for everyone (web profile-view.tsx): your own page ([handle] == null) and any member's.
/// Cover band with the back arrow, picture, one quiet stats line, name, tags, then the actions and
/// the Asks / Connects / Updates / Catalog (or Resume) tabs. Contact numbers are never shown in full.
class ProfileScreen extends StatefulWidget {
  final String? handle;
  /// a shared catalog item to open once the catalog has loaded
  final String? itemId;
  const ProfileScreen({super.key, this.handle, this.itemId});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

enum _Tab { posts, deals, updates, products }

const _kindText = {'contact': 'contact', 'media': 'a photo', 'info': 'information'};

class _ProfileScreenState extends State<ProfileScreen> {
  Profile? _u;
  String? _error;
  _Tab? _tabSel;
  /// direction of the last tab change (1 = to the right), for the slide
  int _tabDir = 1;
  List<Post>? _posts;
  // text updates (posts that aren't asks) live under Updates, with the 24-hour photo updates
  List<Post>? _textUpdates;
  List<Deal>? _deals;
  List<AskItem> _asks = [];
  List<StoryItem>? _updates;
  List<Product>? _products;
  List<Map<String, dynamic>>? _areas;
  /// the area whose map is open (a chip in the areas line)
  int? _areaOpen;
  String _catFilter = 'all';

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

  void _loadTabs(Profile u) {
    final api = _api;
    api.get('/users/${u.uid}/products').then((d) {
      if (!mounted) return;
      // with the same counts and my reactions as the Connect feed (FeedProduct), for the item cards
      setState(() => _products = (d as List).map((e) => FeedProduct.fromJson(e as Map)).toList());
      _openLinkedItem(u);
    }).catchError((_) {
      if (mounted) setState(() => _products = []);
    });
    api.get('/posts', {'authorId': u.uid, 'limit': 30, 'kind': 'requirement'}).then((d) {
      if (mounted) setState(() => _posts = (d as List).map((e) => Post.fromJson(e as Map)).toList());
    }).catchError((_) {
      if (mounted) setState(() => _posts = []);
    });
    api.get('/posts', {'authorId': u.uid, 'limit': 30, 'kind': 'update'}).then((d) {
      if (mounted) setState(() => _textUpdates = (d as List).map((e) => Post.fromJson(e as Map)).toList());
    }).catchError((_) {
      if (mounted) setState(() => _textUpdates = []);
    });
    api.get('/users/${u.uid}/updates').then((d) {
      if (mounted) setState(() => _updates = (d as List).map((e) => StoryItem.fromJson(e as Map)).toList());
    }).catchError((_) {
      if (mounted) setState(() => _updates = []);
    });
    api.get('/areas/user/${u.uid}').then((d) {
      if (mounted) setState(() => _areas = (d as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());
    }).catchError((_) {
      if (mounted) setState(() => _areas = []);
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

  bool _linkedItemDone = false;

  /// Opened from a shared item card: show the catalog with that item open.
  void _openLinkedItem(Profile u) {
    if (_linkedItemDone || widget.itemId == null) return;
    _linkedItemDone = true;
    final hit = _products?.where((x) => x.id == widget.itemId).firstOrNull;
    if (hit == null) {
      toast(context, t('This item is no longer listed.'));
      return;
    }
    setState(() => _tabSel = _Tab.products);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showItem(hit, u);
    });
  }

  Future<void> _message() async => openChat(context, Peer.fromProfile(_u!));

  Future<void> _edit() async {
    final u = _u;
    if (u == null) return;
    if (await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => EditProfileScreen(profile: u))) == true) {
      if (!mounted) return;
      await context.read<AuthProvider>().loadProfile();
      _load();
    }
  }

  /// New profile picture or cover (or remove the cover when [remove]).
  /// My own page: the photo / cover picker (a new picture, cropped; an earlier one; or a WEBWEB cover design).
  Future<void> _changeMedia(String kind) async {
    if (await showPicturePicker(context, kind == 'photo' ? 'avatar' : 'cover')) await _load();
  }


  void _openPicture() {
    final u = _u!;
    final live = (_updates ?? const <StoryItem>[]).where((s) => DateTime.now().difference(s.createdAt).inHours < 24).toList();
    if (u.hasUpdate && live.isNotEmpty) {
      _openUpdates(live);
    } else if ((u.photoUrl ?? '').isNotEmpty) {
      showDialog(
        context: context,
        barrierColor: kInk.withValues(alpha: .9),
        builder: (ctx) => GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: Stack(children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 384),
                  child: AspectRatio(aspectRatio: 1, child: ClipOval(child: NetImg(u.photoUrl!))),
                ),
              ),
            ),
            Positioned(
              right: 16,
              top: MediaQuery.of(ctx).padding.top + 16,
              child: const WIcon(WI.close, size: 28, color: Colors.white),
            ),
          ]),
        ),
      );
    }
  }

  Future<void> _openUpdates(List<StoryItem> items) async {
    final u = _u!;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StoryViewer(
          groups: [StoryGroup(uid: u.uid, name: u.name, company: u.company, userType: u.userType, verification: u.verification, handle: u.handle, photoUrl: u.photoUrl, items: items)],
          meUid: context.read<AuthProvider>().profile?.uid,
          onDelete: (id) async => _api.delete('/updates/$id'),
        ),
      ),
    );
    if (changed == true && _u != null) _loadTabs(_u!);
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final u = _u;
    if (u == null) {
      return SubPage(
        title: widget.handle == null ? t('Profile') : '@${widget.handle}',
        body: _error != null
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: p.muted))))
            : const PageLoader(),
      );
    }
    final isJob = u.isJobSeeker;
    final own = _own;
    final tabs = own && !isJob ? [_Tab.posts, _Tab.deals, _Tab.updates, _Tab.products] : [_Tab.products, _Tab.posts, _Tab.deals, _Tab.updates];
    final tab = _tabSel ?? (own && !isJob ? _Tab.posts : _Tab.products);
    final me = context.watch<AuthProvider>().profile;
    final completion = own ? me?.completion : null;

    return Scaffold(
      backgroundColor: p.canvas,
      body: LogoRefresh(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 32),
          children: [
            _cover(p, u, own),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _pictureRow(p, u, own),
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: displayName(u.userType, u.name, u.company)),
                    if (u.verification > 0 || u.premium || u.plan != null) WidgetSpan(alignment: PlaceholderAlignment.middle, child: Padding(padding: const EdgeInsets.only(left: 6), child: VerifiedBadge(level: u.verification, premium: u.premium, plan: u.plan, size: 20))),
                  ]),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.375),
                ),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '@${u.handle}', style: TextStyle(fontWeight: FontWeight.w700, color: p.link)),
                    TextSpan(text: ' · ${isJob ? u.company : u.name}'),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: p.muted, height: 1.375),
                ),
                if ((u.bio ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(u.bio!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, height: 1.43))),
                const SizedBox(height: 6),
                _tags(p, u, own),
                if (own && completion != null && completion.badges.isNotEmpty) _badges(p, completion.badges),
                if (own && completion != null && completion.percent < 100) _StrengthCard(completion: completion, onTap: _edit),
                const SizedBox(height: 8),
                own ? _ownActions(p) : _visitorActions(p, u),
              ]),
            ),
            const SizedBox(height: 16),
            _tabBar(p, tabs, tab, isJob, own),
            // swipe left / right anywhere below the tabs to move between them
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v.abs() < 250) return;
                final i = tabs.indexOf(tab) + (v < 0 ? 1 : -1);
                if (i >= 0 && i < tabs.length) _goTab(tabs, tab, tabs[i]);
              },
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, if (current != null) current]),
                transitionBuilder: (child, anim) {
                  final incoming = child.key == ValueKey(tab);
                  final from = Offset((incoming ? .25 : -.25) * _tabDir, 0);
                  return FadeTransition(
                    opacity: anim,
                    child: SlideTransition(position: Tween(begin: from, end: Offset.zero).animate(anim), child: child),
                  );
                },
                child: Padding(
                  key: ValueKey(tab),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _tabBody(tab, u, p),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- header ----------

  Widget _cover(Pal p, Profile u, bool own) {
    final top = MediaQuery.of(context).padding.top;
    final hasBanner = (u.bannerUrl ?? '').isNotEmpty;
    final themeCtl = context.watch<ThemeController>();
    final dark = p.dark;
    Widget roundBtn({required Widget child, required String label, required VoidCallback onTap}) => Semantics(
          button: true,
          label: label,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: hasBanner ? Colors.white.withValues(alpha: .75) : Colors.transparent, shape: BoxShape.circle),
              child: child,
            ),
          ),
        );
    Widget chip(WI icon, String label, VoidCallback? onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .8), borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              WIcon(icon, size: 14, color: kInk, strokeWidth: 2.1),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kInk)),
            ]),
          ),
        );
    // the cover is 3:1 (as it was cropped) below the status bar; behind the status bar, a blurred copy of it
    final band = MediaQuery.sizeOf(context).width / 3;
    return SizedBox(
      height: top + band,
      child: Stack(fit: StackFit.expand, children: [
        if (!hasBanner)
          CoverPattern(seed: u.handle.isEmpty ? u.name : u.handle)
        else ...[
          if (top > 0) ClipRect(child: ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14), child: NetImg(u.bannerUrl!, alignment: Alignment.topCenter))),
          Positioned(top: top, left: 0, right: 0, height: band, child: NetImg(u.bannerUrl!)),
        ],
        Positioned(
          top: top,
          left: 8,
          right: 12,
          height: 56,
          child: Row(children: [
            roundBtn(label: t('Back'), onTap: () => Navigator.maybePop(context), child: const WIcon(WI.back, size: 28, color: kInk)),
            const Spacer(),
            roundBtn(
              label: dark ? 'Switch to light mode' : 'Switch to dark mode',
              onTap: () => themeCtl.set(dark ? ThemeMode.light : ThemeMode.dark),
              child: Padding(padding: const EdgeInsets.all(2), child: WIcon(dark ? WI.sun : WI.moon, size: 20, color: kInk)),
            ),
            if (!own) ...[
              const SizedBox(width: 4),
              roundBtn(
                label: 'Report or block',
                onTap: () async {
                  if (await showSafetySheet(context, uid: u.uid, name: displayName(u.userType, u.name, u.company)) && mounted) Navigator.maybePop(context);
                },
                child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.more_vert, size: 22, color: kInk)),
              ),
            ],
          ]),
        ),
        if (own)
          Positioned(
            right: 12,
            bottom: 8,
            child: Row(children: [
              chip(WI.camera, t(hasBanner ? 'Change cover' : 'Add cover'), () => _changeMedia('banner')),
            ]),
          ),
      ]),
    );
  }

  Widget _pictureRow(Pal p, Profile u, bool own) {
    final name = displayName(u.userType, u.name, u.company);
    TextSpan stat(String? v, String label) => TextSpan(children: [
          TextSpan(text: v ?? '–', style: TextStyle(fontWeight: FontWeight.w700, color: p.text)),
          TextSpan(text: ' ${t(label)}'),
        ]);
    return Transform.translate(
      offset: const Offset(0, -28),
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: p.canvas, shape: BoxShape.circle),
              // the role on the picture's edge, coloured by presence; tapping it names it
              child: GestureDetector(
                onTap: _openPicture,
                child: Avatar(name: name, photoUrl: u.photoUrl, size: 56, ring: u.hasUpdate, type: u.userType, uid: u.uid, badge: 22, tip: t(labelOf(kUserTypes, u.userType))),
              ),
            ),
            if (own)
              Positioned(
                right: -4,
                top: -4,
                child: Semantics(
                  button: true,
                  label: t('Change profile picture'),
                  child: GestureDetector(
                    onTap: () => _changeMedia('photo'),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(color: p.ink, shape: BoxShape.circle, border: Border.all(color: p.canvas, width: 2)),
                      child: Center(child: WIcon(WI.camera, size: 15, color: p.onInk, strokeWidth: 2.1)),
                    ),
                  ),
                ),
              ),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text.rich(
                TextSpan(children: [
                  stat(u.statPosts?.toString(), 'Asks'),
                  const TextSpan(text: ' · '),
                  stat(u.statShared?.toString(), 'Connects'),
                  const TextSpan(text: ' · '),
                  stat('${u.contributions}', 'Contributions'),
                  // deals won: asks whose owner chose them (only once there is one)
                  if (u.statWon > 0) ...[const TextSpan(text: ' · 🏆 '), stat('${u.statWon}', u.statWon == 1 ? 'deal won' : 'deals won')],
                ]),
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12, height: 1.25, color: p.muted),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _tags(Pal p, Profile u, bool own) {
    Widget tag({WI? icon, required String text, Color? bg, Color? fg, VoidCallback? onTap, double iconSize = 14}) {
      final c = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg ?? p.chip, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[WIcon(icon, size: iconSize, color: fg ?? p.text, strokeWidth: 2.2), const SizedBox(width: 4)],
          Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg ?? p.text))),
        ]),
      );
      return onTap == null ? c : GestureDetector(onTap: onTap, child: c);
    }

    final gst = u.gstin;
    return Transform.translate(
      offset: const Offset(0, 0),
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        // WEBWEB Premium, or a paid plan below it, first (web PremiumChip): ink, with the tier's metal for crown and words
        if (u.premium || u.plan == 'pro' || u.plan == 'plus') PremiumChip(tier: u.premium ? 'premium' : u.plan!),
        // proof from how they reply: shown once there is enough behind it
        if ((u.statHelped ?? 0) > 0)
          tag(text: '🤝 ${u.location.isNotEmpty && u.location != 'Other' ? t('Helped {n} businesses in {area}', {'n': u.statHelped!, 'area': u.location}) : t('Helped {n} businesses', {'n': u.statHelped!})}'),
        if ((u.statReplyMins ?? 0) > 0) tag(text: '⚡ ${t('Usually replies in {t}', {'t': _replyTime(u.statReplyMins!)})}'),
        if (u.statReplyRate != null) tag(text: '✓ ${t('Answers {n}% of asks that fit', {'n': u.statReplyRate!})}'),
        if (u.location.isNotEmpty) tag(icon: WI.pin, text: u.location == 'Other' ? t('Other') : u.location),
        if (u.category.isNotEmpty) tag(text: t(labelOf(kProfileCategories, u.category))),
        // a GSTIN is public record: tap to check it on the GST portal
        if ((gst ?? '').isNotEmpty)
          tag(
            icon: WI.checkCircle,
            iconSize: 12,
            text: 'GSTIN $gst',
            bg: kGold.withValues(alpha: .15),
            fg: p.dark ? const Color(0xFFFFD84A) : const Color(0xFF7A5A00),
            onTap: () => launchUrl(Uri.parse('https://services.gst.gov.in/services/searchtp'), mode: LaunchMode.externalApplication),
          ),
        // UPI IDs: tap one for its QR and to pay in a UPI app
        ...upiChips(context, u, displayName(u.userType, u.name, u.company)),
        if (own && u.upi.isEmpty)
          GestureDetector(
            onTap: () async {
              if (await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => EditProfileScreen(profile: u, tab: 'upi'))) == true && mounted) {
                context.read<AuthProvider>().loadProfile();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(border: Border.all(color: p.border), borderRadius: BorderRadius.circular(20)),
              child: Text('+ ${t('Add UPI ID')}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted)),
            ),
          ),
      ]),
    );
  }

  Widget _badges(Pal p, List<String> badges) {
    final fg = p.dark ? const Color(0xFFFFD84A) : const Color(0xFF7A5A00);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SizedBox(
        height: 22,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: badges.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: kGold.withValues(alpha: .15), borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              WIcon(WI.checkCircle, size: 11, color: fg),
              const SizedBox(width: 4),
              Text(t(badges[i]), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
            ]),
          ),
        ),
      ),
    );
  }

  /// Own page: edit, share, and the QR card one tap away.
  Widget _ownActions(Pal p) => Row(children: [
        Expanded(child: _ActionBtn(label: t('Edit profile'), wi: WI.edit, gold: true, onTap: _edit)),
        const SizedBox(width: 8),
        Expanded(child: _ActionBtn(label: t('Share profile'), wi: WI.share, onTap: () => showShareProfileSheet(context, _u!, isSelf: true))),
        const SizedBox(width: 8),
        SizedBox(width: 44, child: _ActionBtn(wi: WI.qr, label: '', semantic: t('QR code'), onTap: () => showShareProfileSheet(context, _u!, isSelf: true, openQr: true))),
      ]);

  /// Someone else's page: talk, call, share.
  Widget _visitorActions(Pal p, Profile u) => Row(children: [
        Expanded(child: _ActionBtn(label: t('Talk'), wi: WI.talk, gold: true, onTap: _message)),
        const SizedBox(width: 8),
        Expanded(child: _ActionBtn(label: t('Call'), wi: WI.phone, onTap: () => placeCall(context, Peer.fromProfile(u), false))),
        const SizedBox(width: 8),
        SizedBox(width: 44, child: _ActionBtn(wi: WI.share, label: '', semantic: t('Share profile'), onTap: () => showShareProfileSheet(context, u, isSelf: false))),
      ]);

  // ---------- tabs ----------

  static WI _tabIcon(_Tab t) => switch (t) {
        _Tab.posts => WI.ask,
        _Tab.deals => WI.deals,
        _Tab.updates => WI.updates,
        _Tab.products => WI.box,
      };

  static String _tabLabel(_Tab t, bool job) => switch (t) {
        _Tab.posts => 'Asks',
        _Tab.deals => 'Connects',
        _Tab.updates => 'Updates',
        _Tab.products => job ? 'Resume' : 'Catalog',
      };

  Widget _tabBar(Pal p, List<_Tab> tabs, _Tab tab, bool isJob, bool own) => Container(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
        child: Row(children: [
          for (final x in tabs)
            Expanded(
              child: InkWell(
                onTap: () => _goTab(tabs, tab, x),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tab == x ? p.text : Colors.transparent, width: 2))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    WIcon(_tabIcon(x), size: 16, color: tab == x ? p.text : p.muted, still: true),
                    const SizedBox(width: 6),
                    Flexible(child: Text(t(_tabLabel(x, isJob)), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: tab == x ? p.text : p.muted))),
                  ]),
                ),
              ),
            ),
        ]),
      );

  void _goTab(List<_Tab> tabs, _Tab from, _Tab to) {
    if (from == to) return;
    HapticFeedback.selectionClick();
    setState(() {
      _tabDir = tabs.indexOf(to) > tabs.indexOf(from) ? 1 : -1;
      _tabSel = to;
    });
  }

  Widget _loading() => const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: LogoLoader()));

  Widget _tabBody(_Tab tab, Profile u, Pal p) {
    switch (tab) {
      case _Tab.posts:
        if (_posts == null) return _loading();
        if (_posts!.isEmpty) return EmptyState(title: t('No asks yet'));
        return Transform.translate(
          offset: const Offset(0, -16),
          child: Column(children: [for (final x in _posts!) PostCard(key: ValueKey(x.id), post: x, onChanged: () => _loadTabs(u))]),
        );
      case _Tab.deals:
        return _dealsBody(p);
      case _Tab.updates:
        if (_updates == null || _textUpdates == null) return _loading();
        if (_updates!.isEmpty && _textUpdates!.isEmpty) return EmptyState(title: t('No updates yet'));
        // every update as a tile, newest first: the 24-hour photo updates open the viewer, text updates their own page
        final tiles = <({DateTime at, String? imageUrl, String? text, VoidCallback onTap})>[
          for (final s in _updates!) (at: s.createdAt, imageUrl: s.imageUrl, text: s.text, onTap: () => _openUpdates(_updates!)),
          for (final x in _textUpdates!)
            (
              at: x.createdAt,
              imageUrl: x.images.isEmpty ? null : x.images.first,
              text: x.description,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailScreen(postId: x.id))),
            ),
        ]..sort((a, b) => b.at.compareTo(a.at));
        return GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: 3 / 4,
          children: [
            for (final s in tiles)
              GestureDetector(
                onTap: s.onTap,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(fit: StackFit.expand, children: [
                    s.imageUrl != null
                        ? NetImg(s.imageUrl!)
                        : Container(
                            decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF3A3A3A), kInk], begin: Alignment.topLeft, end: Alignment.bottomRight)),
                            padding: const EdgeInsets.all(8),
                            alignment: Alignment.center,
                            child: Text(s.text ?? '', textAlign: TextAlign.center, maxLines: 6, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                          ),
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(color: kInk.withValues(alpha: .7), borderRadius: BorderRadius.circular(4)),
                        child: Text(timeAgo(s.at), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                  ]),
                ),
              ),
          ],
        );
      case _Tab.products:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _areasSection(p, u),
          u.isJobSeeker ? _resume(u, p) : _catalog(u, p),
        ]);
    }
  }

  Widget _dealsBody(Pal p) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_own && _asks.isNotEmpty) ...[
        Text(t('Asked to share'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        for (final a in _asks)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: a.ownerName, style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: ' (${a.ownerCompany}) asked you to reveal ${_kindText[a.kind] ?? a.kind} for '),
                  WidgetSpan(
                    child: GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailScreen(postId: a.postId))),
                      child: Text(a.postTitle, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
                    ),
                  ),
                ]),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: GoldButton(label: t('Approve'), height: 32, onPressed: () => _answer(a, true))),
                const SizedBox(width: 8),
                Expanded(child: GoldButton(label: t('Decline'), height: 32, outlined: true, onPressed: () => _answer(a, false))),
              ]),
            ]),
          ),
        const SizedBox(height: 12),
      ],
      if (_deals == null)
        _loading()
      else if (_deals!.isEmpty)
        EmptyState(title: t('No connects yet'), hint: t('Contacts shared in closed loop show up here, without the contact itself.'))
      else
        _ConnectList(deals: _deals!, own: _own, name: _u == null ? '' : (_u!.userType == 'entrepreneur' && _u!.company.isNotEmpty ? _u!.company : _u!.name)),
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

  /// Serviceable areas (catalog) / preferred job locations (resume), as chips.
  Widget _areasSection(Pal p, Profile u) {
    final areas = _areas;
    if (areas == null) return const SizedBox.shrink();
    final biz = u.isEntrepreneur;
    if (areas.isEmpty) {
      if (!_own) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: DashedBox(
          radius: 8,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          onTap: _edit,
          child: Row(children: [
            WIcon(WI.pin, size: 16, color: p.link),
            const SizedBox(width: 8),
            Text(t(biz ? 'Add your serviceable areas' : 'Add your preferred job locations'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.link)),
          ]),
        ),
      );
    }
    String radius(num m) => m >= 3000000 ? t('Pan-India') : (m >= 1000 ? '${m % 1000 == 0 ? m ~/ 1000 : (m / 1000).toStringAsFixed(1)} km' : '$m m');
    final gold = p.dark ? const Color(0xFFFFD84A) : const Color(0xFF7A5A00);
    final open = _areaOpen == null ? null : areas.elementAtOrNull(_areaOpen!);
    // one line: the title and the areas as chips; a chip opens the map on that area, the open one closes it
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(spacing: 6, children: [
            WIcon(WI.pin, size: 14, color: p.muted),
            Text(t(biz ? 'Serviceable areas' : 'Preferred job locations'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted)),
            for (final (i, a) in areas.indexed)
              GestureDetector(
                onTap: () => setState(() => _areaOpen = _areaOpen == i ? null : i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: _areaOpen == i ? kGold.withValues(alpha: .25) : p.field, borderRadius: BorderRadius.circular(20)),
                  child: Text('${t('${a['label']}')} · ${radius((a['radiusM'] as num?) ?? 0)}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _areaOpen == i ? gold : null)),
                ),
              ),
          ]),
        ),
        if (open != null && open['lat'] is num && open['lng'] is num) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 220,
              child: AreaMap(
                lat: (open['lat'] as num).toDouble(),
                lng: (open['lng'] as num).toDouble(),
                radiusM: ((open['radiusM'] as num?) ?? 0).toDouble(),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _catalog(Profile u, Pal p) {
    final all = _products;
    if (all == null) return _loading();
    String catOf(Product x) => x.category ?? (x.kind == 'service' ? 'Services' : 'Other');
    final chips = {for (final x in all) catOf(x)}.toList()
      ..sort((a, b) => ((a == 'Services' || a == 'Other') ? 1 : 0).compareTo((b == 'Services' || b == 'Other') ? 1 : 0));
    final filtering = chips.length > 1;
    final items = all.where((x) => !filtering || _catFilter == 'all' || catOf(x) == _catFilter).toList();
    final showPlain = !filtering || _catFilter == 'all' || _catFilter == 'Services';
    final cols = MediaQuery.of(context).size.width >= 420 ? 3 : 2;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (filtering) ...[
        SizedBox(
          height: 36,
          child: OverflowBox(
            maxWidth: MediaQuery.of(context).size.width,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: chips.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final c = i == 0 ? 'all' : chips[i - 1];
                return ScopeChip(label: c == 'all' ? t('All') : c, selected: _catFilter == c, onTap: () => setState(() => _catFilter = c));
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
      // someone else's business: each item with the same controls as on Connect (react, refer, repost, reply, share, save)
      if (items.isNotEmpty && !_own && context.read<AuthProvider>().profile != null)
        LayoutBuilder(builder: (context, c) {
          // two per row on phones, three on wide screens (web: grid-cols-2 lg:grid-cols-3)
          final cols = c.maxWidth >= 560 ? 3 : 2;
          final gap = cols == 2 ? 8.0 : 12.0;
          final w = (c.maxWidth - gap * (cols - 1)) / cols;
          final owner = Peer(uid: u.uid, name: u.name, company: u.company, handle: u.handle, userType: u.userType, photoUrl: u.photoUrl, verification: u.verification);
          return Wrap(spacing: gap, runSpacing: gap, children: [
            for (final x in items)
              if (x is FeedProduct)
                SizedBox(
                  width: w,
                  child: Opacity(
                    opacity: x.available ? 1 : .6,
                    child: CatalogItemCard(
                      key: ValueKey('item-${x.id}'),
                      item: x,
                      owner: owner,
                      ownerName: displayName(u.userType, u.name, u.company),
                      onOpen: () => _showItem(x, u),
                    ),
                  ),
                ),
          ]);
        })
      else if (items.isNotEmpty)
        GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: .66,
          children: [for (final x in items) _CatalogTile(item: x, onTap: () => _showItem(x, u), onLongPress: () => showShareItemSheet(context, x, u))],
        ),
      if (showPlain && u.services.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text(t('Services'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final s in u.services)
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 1), child: WIcon(WI.checkCircle, size: 20, color: p.link)),
              const SizedBox(width: 8),
              Expanded(child: Text(s, style: const TextStyle(fontSize: 14))),
            ]),
          ),
      ],
      if (all.isEmpty && u.services.isEmpty) EmptyState(title: t('Nothing listed yet'), hint: _own ? t('Add products and services to your free website.') : null),
      if (_own) ...[
        const SizedBox(height: 16),
        GoldButton(
          label: t('Manage catalog'),
          outlined: true,
          height: 40,
          onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogScreen()));
            if (_u != null) _loadTabs(_u!);
          },
        ),
      ],
    ]);
  }

  /// Visitor taps an item: a sheet with the photo, details and Enquire (web ItemActionSheet, without the cart).
  void _showItem(Product x, Profile u) {
    final p = Pal.of(context);
    final business = displayName(u.userType, u.name, u.company);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.canvas,
      barrierColor: kInk.withValues(alpha: .6),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .9),
        child: ListView(shrinkWrap: true, padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).padding.bottom + 24), children: [
          Row(children: [
            Expanded(child: Text(x.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            Semantics(
              button: true,
              label: t('Share'),
              child: GestureDetector(
                onTap: () => showShareItemSheet(ctx, x, u),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: WIcon(WI.share, size: 22, color: p.text)),
              ),
            ),
            GestureDetector(onTap: () => Navigator.pop(ctx), child: WIcon(WI.close, size: 24, color: p.text)),
          ]),
          const SizedBox(height: 12),
          if (x.imageUrl != null)
            ClipRRect(borderRadius: BorderRadius.circular(8), child: AspectRatio(aspectRatio: 1, child: NetImg(x.imageUrl!))),
          const SizedBox(height: 12),
          Row(children: [
            WIcon(x.kind == 'service' ? WI.service : WI.box, size: 16, color: p.muted),
            const SizedBox(width: 6),
            Text(t(x.kind == 'service' ? 'Service' : 'Product'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted)),
            if (!x.available) Text(' · ${t('Unavailable')}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted)),
            const Spacer(),
            if ((x.price ?? '').isNotEmpty) Text(x.price!, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.link)),
          ]),
          if ((x.description ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(x.description!, style: const TextStyle(fontSize: 14, height: 1.43))),
          const SizedBox(height: 16),
          if (_own) ...[
            GoldButton(label: t(x.kind == 'service' ? 'Share service' : 'Share product'), wi: WI.share, onPressed: () => showShareItemSheet(ctx, x, u)),
            const SizedBox(height: 8),
            Text(t('Send it in a chat, or share its link on WhatsApp and other apps.'), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.muted)),
          ] else ...[
          GoldButton(
            label: t('Enquire'),
            wi: WI.talk,
            onPressed: () {
              Navigator.pop(ctx);
              openChat(context, Peer.fromProfile(u), attachment: {
                'type': 'item',
                'name': x.name.length > 80 ? x.name.substring(0, 80) : x.name,
                'kind': x.kind,
                if ((x.price ?? '').isNotEmpty) 'price': x.price,
                if (x.imageUrl != null) 'imageUrl': x.imageUrl,
              });
              _api.post('/products/${x.id}/enquire', {}).catchError((_) => null);
            },
          ),
          const SizedBox(height: 8),
          Text(t('Opens a chat with {name}', {'name': business}), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.muted)),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: () => showShareItemSheet(ctx, x, u),
            icon: WIcon(WI.share, size: 16, color: p.text),
            label: Text(t('Share with someone'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
          ),
          ],
        ]),
      ),
    );
  }

  Widget _resume(Profile u, Pal p) {
    final empty = u.skills.isEmpty && (u.experience ?? '').isEmpty && (u.education ?? '').isEmpty;
    Future<void> save(String field, String next) async {
      await context.read<AuthProvider>().updateProfile({field: next});
      await _load();
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (u.skills.isNotEmpty) ...[
        Text(t('Skills'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in u.skills)
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FindScreen(standalone: true, initialQuery: s, initialScope: 'people'))),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(20), border: Border.all(color: p.border.withValues(alpha: .7))),
                child: Text(s, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
        ]),
        const SizedBox(height: 20),
      ],
      ResumeList(title: t('Experience'), text: u.experience, icon: WI.business, kind: 'experience', editable: _own, onSave: (v) => save('experience', v)),
      const SizedBox(height: 20),
      ResumeList(title: t('Education'), text: u.education, icon: WI.school, kind: 'education', editable: _own, onSave: (v) => save('education', v)),
      if (!_own && empty) EmptyState(title: t('No resume details yet')),
      if (_own) ...[
        const SizedBox(height: 20),
        GoldButton(label: t('Edit skills'), outlined: true, height: 40, onPressed: _edit),
      ],
    ]);
  }
}

/// Profile action button (web Button, 40 px, 13 px text): gold for the main action, cream otherwise.
class _ActionBtn extends StatelessWidget {
  final String label;
  final String? semantic;
  final WI? wi;
  final bool gold;
  final VoidCallback? onTap;
  const _ActionBtn({required this.label, this.semantic, this.wi, this.gold = false, this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final fg = gold ? kInk : p.text;
    return Semantics(
      button: true,
      label: semantic ?? label,
      child: Opacity(
        opacity: onTap == null ? .5 : 1,
        child: Material(
          color: Colors.transparent,
          child: Ink(
            height: 40,
            decoration: BoxDecoration(
              gradient: gold ? kGoldGradient : null,
              color: gold ? null : p.chip,
              border: gold ? null : Border.all(color: p.border.withValues(alpha: .7)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (wi != null) WIcon(wi!, size: 16, color: fg, strokeWidth: 1.9, still: true),
                  if (wi != null && label.isNotEmpty) const SizedBox(width: 6),
                  // a long label (Hindi, Marathi…) wraps to a second line inside the button instead of being cut, as on the web
                  if (label.isNotEmpty)
                    Flexible(
                      child: Text(label,
                          maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, height: 1.15, fontWeight: FontWeight.w700, color: fg)),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Own profile: how complete the page is and the next best step (web StrengthCard).
class _StrengthCard extends StatelessWidget {
  final Completion completion;
  final VoidCallback onTap;
  const _StrengthCard({required this.completion, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final fg = p.dark ? const Color(0xFFFFD84A) : const Color(0xFF7A5A00);
    final next = completion.next;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(colors: [kGold.withValues(alpha: .2), kGold.withValues(alpha: .07), kGold.withValues(alpha: 0)]),
      ),
      child: Row(children: [
        Text('${completion.percent}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg, fontFeatures: const [FontFeature.tabularFigures()])),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 4,
              child: Stack(children: [
                Container(color: p.text.withValues(alpha: .1)),
                FractionallySizedBox(widthFactor: completion.percent / 100, child: Container(decoration: const BoxDecoration(gradient: kGoldGradient))),
              ]),
            ),
          ),
        ),
        if (next != null) ...[
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .5),
            child: GestureDetector(
              onTap: onTap,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '+ ${t(next.label)} '),
                  TextSpan(text: '+${next.weight}%', style: TextStyle(color: fg.withValues(alpha: .7))),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Catalog item on a profile (web: square photo with a Product / Service tag, name, price, two lines).
class _CatalogTile extends StatelessWidget {
  final Product item;
  final VoidCallback? onTap;
  /// long press, or the share button in the corner
  final VoidCallback? onLongPress;
  const _CatalogTile({required this.item, this.onTap, this.onLongPress});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final service = item.kind == 'service';
    final icon = service ? WI.service : WI.box;
    return Opacity(
      opacity: item.available ? 1 : .6,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                onLongPress!();
              },
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(fit: StackFit.expand, children: [
                if (item.imageUrl != null) NetImg(item.imageUrl!) else ColoredBox(color: p.chip, child: Center(child: WIcon(icon, size: 28, color: p.muted))),
                if (onLongPress != null)
                  Positioned(
                    right: 2,
                    top: 2,
                    child: Semantics(
                      button: true,
                      label: t('Share'),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onLongPress,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(color: p.ink.withValues(alpha: .55), shape: BoxShape.circle),
                            child: Center(child: WIcon(WI.share, size: 14, color: p.onInk, strokeWidth: 2.2)),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: p.ink.withValues(alpha: .55), borderRadius: BorderRadius.circular(10)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      WIcon(icon, size: 10, color: p.onInk, strokeWidth: 2.4),
                      const SizedBox(width: 4),
                      Text(t(service ? 'Service' : 'Product'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, height: 1, color: p.onInk)),
                    ]),
                  ),
                ),
                if (!item.available)
                  Positioned(
                    left: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: kInk.withValues(alpha: .8), borderRadius: BorderRadius.circular(10)),
                      child: Text(t('Unavailable'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.25)),
                if ((item.price ?? '').isNotEmpty) Text(item.price!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.25, color: p.link)),
                if ((item.description ?? '').isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 2), child: Text(item.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, height: 1.35, color: p.muted))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ======================= share sheet: profiles and catalog items (web share-profile-sheet.tsx) =======================

/// What a share sheet passes on: the link, the chat card and how the share is logged.
class ShareTarget {
  final String title; // sheet title
  final String url;
  final String subject; // for mail and other apps
  final String text; // shared with other apps (the url is appended)
  final Map<String, dynamic> attachment; // the card sent into a chat
  final String entity, ref; // share log: profile/handle or item/id
  /// own page: also offer the QR card
  final ({String name, String label, String handle})? qr;
  const ShareTarget({
    required this.title,
    required this.url,
    required this.subject,
    required this.text,
    required this.attachment,
    required this.entity,
    required this.ref,
    this.qr,
  });
}

/// Share a profile: send it in a chat, copy the link, hand it to another app, or (own page) the QR card.
Future<void> showShareProfileSheet(BuildContext context, Profile profile, {required bool isSelf, bool openQr = false}) {
  final title = displayName(profile.userType, profile.name, profile.company);
  final url = '$siteUrl/@${profile.handle}';
  return _showShareSheet(
    context,
    ShareTarget(
      title: t('Share profile'),
      url: url,
      subject: isSelf ? t('My WEBWEB AI page') : title,
      text: '',
      entity: 'profile',
      ref: profile.handle,
      attachment: {
        'type': 'profile',
        'handle': profile.handle,
        'name': title,
        'subtitle': [labelOf(kProfileCategories, profile.category), profile.location].where((e) => e.isNotEmpty).join(' · '),
        if (profile.photoUrl != null) 'photoURL': profile.photoUrl,
        'path': '/@${profile.handle}',
      },
      qr: isSelf ? (name: title, label: url.replaceFirst(RegExp(r'^https?://'), ''), handle: profile.handle) : null,
    ),
    openQr: openQr,
  );
}

/// Share one catalog item (own or someone else's): in a chat as a card, or its short link (/@handle/item/<slug>).
Future<void> showShareItemSheet(BuildContext context, Product item, Profile owner) =>
    showShareItemSheetFor(context, item, handle: owner.handle, business: displayName(owner.userType, owner.name, owner.company));

/// The same, from places that only know the owner's handle and display name (the Connect feed's catalog strip).
Future<void> showShareItemSheetFor(BuildContext context, Product item, {required String handle, required String business}) {
  final url = '$siteUrl${item.pathFor(handle)}';
  final name = item.name.length > 80 ? item.name.substring(0, 80) : item.name;
  return _showShareSheet(
    context,
    ShareTarget(
      title: t(item.kind == 'service' ? 'Share service' : 'Share product'),
      url: url,
      subject: '$name — $business',
      text: '$name${(item.price ?? '').isNotEmpty ? ' · ${item.price}' : ''} — $business',
      entity: 'item',
      ref: item.id,
      attachment: {
        'type': 'item',
        'shared': true,
        'name': name,
        'kind': item.kind,
        if ((item.price ?? '').isNotEmpty) 'price': item.price,
        if (item.imageUrl != null) 'imageUrl': item.imageUrl,
        'itemId': item.id,
        'handle': handle,
        'seller': business.length > 80 ? business.substring(0, 80) : business,
        'path': item.pathFor(handle),
      },
    ),
  );
}

Future<void> _showShareSheet(BuildContext context, ShareTarget target, {bool openQr = false}) {
  final p = Pal.of(context);
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.canvas,
    barrierColor: kInk.withValues(alpha: .6),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _ShareSheet(target: target, openQr: openQr),
  );
}

enum _ShareView { menu, chat, qr }

class _ShareSheet extends StatefulWidget {
  final ShareTarget target;
  final bool openQr;
  const _ShareSheet({required this.target, this.openQr = false});
  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  late _ShareView _view = widget.openQr && widget.target.qr != null ? _ShareView.qr : _ShareView.menu;
  List<ChatSummary>? _chats;
  final _q = TextEditingController();
  final _qrKey = GlobalKey();
  bool _qrBusy = false;
  String? _sending;
  final Set<String> _sent = {};

  ShareTarget get _t => widget.target;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _openChats() async {
    setState(() => _view = _ShareView.chat);
    final auth = context.read<AuthProvider>();
    try {
      final d = await auth.api.get('/chats') as List;
      if (mounted) setState(() => _chats = d.map((e) => ChatSummary.fromJson(e as Map, auth.profile?.uid ?? '')).toList());
    } catch (_) {
      if (mounted) setState(() => _chats = []);
    }
  }

  Future<void> _send(ChatSummary c) async {
    final api = context.read<AuthProvider>().api;
    setState(() => _sending = c.id);
    try {
      await api.post('/chats/${c.id}/messages', {'text': '', 'attachment': _t.attachment});
      logShare(api, _t.entity, _t.ref, channel: 'chat');
      if (mounted) setState(() => _sent.add(c.id));
    } catch (e) {
      if (mounted) toast(context, t('Could not send'), error: true);
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  /// The QR card as a PNG, to the phone's share sheet (save to Photos / Files, WhatsApp, print…).
  Future<void> _shareQr() async {
    final qr = _t.qr!;
    final api = context.read<AuthProvider>().api;
    setState(() => _qrBusy = true);
    try {
      final png = await qrCardPng(_qrKey);
      if (png == null) throw 'no image';
      final r = await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(Uint8List.fromList(png), mimeType: 'image/png', name: 'webweb-${qr.handle}-qr.png')],
        fileNameOverrides: ['webweb-${qr.handle}-qr.png'],
        text: _t.url,
        subject: _t.subject,
      ));
      if (r.status != ShareResultStatus.dismissed) logShare(api, _t.entity, _t.ref, channel: 'qr');
    } catch (_) {
      if (mounted) toast(context, t('Could not create the QR code'), error: true);
    } finally {
      if (mounted) setState(() => _qrBusy = false);
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _t.url));
    if (!mounted) return;
    logShare(context.read<AuthProvider>().api, _t.entity, _t.ref, channel: 'copy');
    Navigator.pop(context);
    toast(context, t('Link copied'));
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    Widget row(Widget icon, String title, String hint, VoidCallback onTap) => InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: p.chip, shape: BoxShape.circle), child: Center(child: icon)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted)),
                ]),
              ),
            ]),
          ),
        );
    final q = _q.text.trim().toLowerCase();
    final rows = (_chats ?? const <ChatSummary>[]).where((c) => q.isEmpty || '${c.peer.name} ${c.peer.company}'.toLowerCase().contains(q)).toList();
    final heading = switch (_view) {
      _ShareView.chat => t('Send in chat'),
      _ShareView.qr => t('QR code'),
      _ShareView.menu => _t.title,
    };
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .9),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            if (_view != _ShareView.menu)
              GestureDetector(onTap: () => setState(() => _view = _ShareView.menu), child: Padding(padding: const EdgeInsets.only(right: 8), child: WIcon(WI.back, size: 20, color: p.text))),
            Expanded(child: Text(heading, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            GestureDetector(onTap: () => Navigator.pop(context), child: WIcon(WI.close, size: 24, color: p.text)),
          ]),
          const SizedBox(height: 12),
          if (_view == _ShareView.menu) ...[
            row(WIcon(WI.talk, size: 20, color: p.text), t('Send in chat'), t('Pick a conversation'), _openChats),
            if (_t.qr != null) row(WIcon(WI.qr, size: 20, color: p.text), t('QR code'), t('Show, share or download'), () => setState(() => _view = _ShareView.qr)),
            row(WIcon(WI.clip, size: 20, color: p.text), t('Copy link'), _t.url.replaceFirst(RegExp(r'^https?://'), ''), _copy),
            row(WIcon(WI.share, size: 20, color: p.text), t('More apps'), t('WhatsApp, email and others'), () async {
              try {
                await shareAndLog(context.read<AuthProvider>().api, entity: _t.entity, ref: _t.ref, text: _t.text.isEmpty ? _t.url : '${_t.text}\n${_t.url}', subject: _t.subject);
              } catch (_) {}
            }),
          ] else if (_view == _ShareView.qr) ...[
            Flexible(
              child: SingleChildScrollView(
                child: Column(children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: RepaintBoundary(key: _qrKey, child: QrCard(url: _t.url, name: _t.qr!.name, label: _t.qr!.label)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: GoldButton(label: t('Share image'), wi: WI.share, height: 44, loading: _qrBusy, onPressed: _qrBusy ? null : _shareQr)),
                    const SizedBox(width: 8),
                    Expanded(child: GoldButton(label: t('Copy link'), wi: WI.clip, outlined: true, height: 44, onPressed: _copy)),
                  ]),
                  const SizedBox(height: 8),
                  Text(t('Print it for your shop, visiting card or packaging. Anyone can scan it to open your page.'), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.muted)),
                ]),
              ),
            ),
          ] else ...[
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(20)),
              child: Row(children: [
                WIcon(WI.search, size: 16, color: p.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _q,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: t('Search conversations'),
                      hintStyle: TextStyle(color: p.muted),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            if (_chats == null) const Padding(padding: EdgeInsets.all(24), child: Center(child: LogoLoader(size: 32))),
            if (_chats != null && rows.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Text(t('No conversations yet. Start one from a profile.'), textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: p.muted))),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final c in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Avatar(name: c.peer.name, photoUrl: c.peer.photoUrl, size: 40, type: c.peer.userType, badge: 16, uid: c.peer.uid),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Flexible(child: Text(c.peer.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                            if (c.peer.verification > 0 || c.peer.premium || c.peer.plan != null) ...[
                              const SizedBox(width: 4),
                              VerifiedBadge(level: c.peer.verification, premium: c.peer.premium, plan: c.peer.plan, size: 14),
                            ],
                          ]),
                          if (c.peer.company.isNotEmpty) Text(c.peer.company, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted)),
                        ]),
                      ),
                      GestureDetector(
                        onTap: _sending != null || _sent.contains(c.id) ? null : () => _send(c),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(gradient: _sent.contains(c.id) ? null : kGoldGradient, color: _sent.contains(c.id) ? p.chip : null, borderRadius: BorderRadius.circular(20)),
                          child: _sending == c.id
                              ? const Text('…', style: TextStyle(fontWeight: FontWeight.w700, color: kInk))
                              : _sent.contains(c.id)
                                  ? WIcon(WI.checkCircle, size: 16, color: p.text)
                                  : Row(mainAxisSize: MainAxisSize.min, children: [
                                      const WIcon(WI.send, size: 13, color: kInk),
                                      const SizedBox(width: 4),
                                      Text(t('Send'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kInk)),
                                    ]),
                        ),
                      ),
                    ]),
                  ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Saved asks (bookmarks), opened from the account menu.
class SavedPostsScreen extends StatefulWidget {
  const SavedPostsScreen({super.key});
  @override
  State<SavedPostsScreen> createState() => SavedPostsScreenState();
}

class SavedPostsScreenState extends State<SavedPostsScreen> {
  List<Post>? _posts;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await context.read<AuthProvider>().api.get('/posts/bookmarks');
      if (mounted) setState(() => _posts = (d as List).map((e) => Post.fromJson(e as Map)).toList());
    } catch (_) {
      if (mounted) setState(() => _posts = []);
    }
  }

  @override
  Widget build(BuildContext context) => SubPage(
        title: t('Saved asks'),
        body: _posts == null
            ? const Center(child: LogoLoader())
            : LogoRefresh(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).padding.bottom + 24),
                  children: [
                    if (_posts!.isEmpty) EmptyState(title: t('Nothing saved yet'), hint: t('Tap Save on an ask to keep it here.')),
                    for (final x in _posts!) PostCard(key: ValueKey(x.id), post: x),
                  ],
                ),
              ),
      );
}


/// A profile's Connects (web connect-list.tsx): the asks this member answered. A line says what the list is (and, to
/// the owner, that only the asker sees their contact), then one row per ask: who asked and what, how this member
/// answered (never the contact), the asker's feedback and how the ask ended. The whole row opens the ask.
class _ConnectList extends StatelessWidget {
  final List<Deal> deals;
  final bool own;
  final String name;
  const _ConnectList({required this.deals, required this.own, required this.name});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final won = deals.where((d) => d.won).length;
    final liked = deals.where((d) => d.rating == 1).length;
    Widget pill(String text, {Color? bg, Color? fg, FontWeight w = FontWeight.w600, Widget? lead}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: bg ?? p.chip, borderRadius: BorderRadius.circular(99)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (lead != null) ...[lead, const SizedBox(width: 3)],
            Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: w, color: fg ?? p.muted))),
          ]),
        );
    final goldText = p.dark ? kGold : const Color(0xFF7A5A00);
    final green = p.dark ? const Color(0xFF34D399) : const Color(0xFF059669);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(own ? t('Asks you answered. Only the asker sees your contact.') : t('Asks {name} answered. Contacts stay private between them and the asker.', {'name': name}),
          style: TextStyle(fontSize: 12, color: p.muted)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 4, children: [
        pill(t('{n} answered', {'n': deals.length}), fg: p.text),
        if (won > 0) pill('🏆 ${t('{n} won', {'n': won})}', bg: kGold.withValues(alpha: .25), fg: goldText),
        if (liked > 0) pill('👍 $liked', fg: p.text),
      ]),
      const SizedBox(height: 4),
      for (var i = 0; i < deals.length; i++)
        Builder(builder: (_) {
          final d = deals[i];
          final feedback = '${d.rating == 1 ? '👍 ' : d.rating == -1 ? '👎 ' : ''}${d.reaction == null ? '' : '${kReactionEmoji[d.reaction] ?? ''} '}';
          return InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailScreen(postId: d.postId))),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: i == 0 ? null : BoxDecoration(border: Border(top: BorderSide(color: p.border))),
              child: Row(children: [
                Avatar(name: d.askerName, photoUrl: d.ownerPhotoUrl, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // who asked, what kind of ask, when this member answered
                    Row(children: [
                      Flexible(child: Text(t("{name}'s ask", {'name': d.askerName}), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.text.withValues(alpha: .85)))),
                      if (d.ownerVerification > 0) ...[const SizedBox(width: 4), VerifiedBadge(level: d.ownerVerification, size: 12)],
                      if (d.category != null) ...[
                        Text('  ·  ', style: TextStyle(fontSize: 11, color: p.muted)),
                        WIcon(categoryIcon(d.category), size: 12, color: p.link, still: true),
                        const SizedBox(width: 3),
                        Flexible(child: Text(t(d.categoryText).toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: .4, color: p.link))),
                      ],
                      const Spacer(),
                      Text(timeAgo(d.createdAt), style: TextStyle(fontSize: 11, color: p.muted)),
                    ]),
                    const SizedBox(height: 2),
                    Text(d.postTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.3)),
                    const SizedBox(height: 6),
                    // how they answered, how the asker took it, how the ask ended
                    Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      if (d.kind == 'contact')
                        pill(t('Shared a contact privately'), bg: Colors.transparent, lead: WIcon(WI.lock, size: 12, color: p.muted))
                      else if (d.kind == 'media')
                        pill(t('Sent a photo'))
                      else if (d.canDo || (d.quote ?? '').isNotEmpty || d.readyWhen != null)
                        OfferChips(canDo: d.canDo, quote: d.quote, readyWhen: d.readyWhen)
                      else
                        pill(t('Replied')),
                      if (d.won)
                        pill('🏆 ${t(own ? 'You won this job' : 'Won this job')}', bg: kGold.withValues(alpha: .3), fg: goldText, w: FontWeight.w700)
                      else if (d.outcome != null)
                        pill(t('Closed'))
                      else
                        pill(t('Open'), bg: green.withValues(alpha: .12), fg: green),
                      if (feedback.isNotEmpty) pill('$feedback${t('from the asker')}'),
                    ]),
                  ]),
                ),
                const SizedBox(width: 6),
                Text('›', style: TextStyle(fontSize: 18, color: p.muted)),
              ]),
            ),
          );
        }),
    ]);
  }
}

/// "20 min", "3 hr", "2 days"
String _replyTime(int mins) {
  if (mins < 60) return t('{n} min', {'n': mins});
  final h = (mins / 60).round();
  return h < 48 ? t('{n} hr', {'n': h}) : t('{n} days', {'n': (h / 24).round()});
}

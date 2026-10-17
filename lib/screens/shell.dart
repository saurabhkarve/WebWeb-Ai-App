import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../i18n.dart';
import '../models.dart';
import '../notifications.dart';
import '../realtime.dart';
import '../safety.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/active_call_banner.dart';
import 'ask.dart';
import 'connect.dart';
import 'edit_profile.dart';
import 'find.dart';
import 'post_detail.dart';
import 'profile.dart';
import 'talk.dart';

/// Signed-in chrome, same as the web on phones (app-frame.tsx): the slim header (logo, bell, your
/// avatar with the account menu) and the floating island with Connect, Find, Talk and Ask.
/// The header hides while scrolling down and comes back on scroll up.
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int _i = 0;
  int _feedTick = 0; // reload the feed
  int _topTick = 0; // scroll the feed to the top
  int _unread = 0;
  int _askSpin = 0;
  bool _headerHidden = false;
  StreamSubscription? _sub;
  Timer? _poll;
  final _notes = NotificationsModel();

  static const _items = [(WI.connect, 'Connect'), (WI.search, 'Find'), (WI.talk, 'Talk'), (WI.askPlus, 'Ask')];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUnread();
    _notes.refresh(context.read<AuthProvider>());
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _notes.refresh(context.read<AuthProvider>()));
    _sub = context.read<RealtimeService>().events.listen((e) {
      if (e['type'] == 'msg' || e['type'] == 'read') _loadUnread();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      _loadUnread();
      _notes.refresh(context.read<AuthProvider>());
    }
  }

  Future<void> _loadUnread() async {
    try {
      final d = await context.read<AuthProvider>().api.get('/chats') as List;
      final n = d.where((c) => c['unread'] == true).length;
      if (mounted && n != _unread) setState(() => _unread = n);
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _poll?.cancel();
    _notes.dispose();
    super.dispose();
  }

  void _go(int k) {
    if (k == 3) _askSpin++;
    if (k == _i && k == 0) _topTick++; // tapping Connect again scrolls the feed to the top
    setState(() {
      _i = k;
      _headerHidden = false;
    });
  }

  /// Hide the header on scroll down (after 80 px), bring it back on scroll up (web: AppHeader).
  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical || n is! ScrollUpdateNotification) return false;
    final d = n.scrollDelta ?? 0;
    if (d.abs() < 4) return false;
    final hide = d > 0 && n.metrics.pixels > 80;
    if (hide != _headerHidden) setState(() => _headerHidden = hide);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final top = MediaQuery.of(context).padding.top;
    final header = _headerHidden ? 0.0 : 56.0;
    return Scaffold(
      body: Column(children: [
        const ActiveCallBanner(),
        Expanded(
          child: Stack(children: [
            // pages, padded below the header (the padding animates as the header slides away)
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: top + header),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                builder: (_, pad, child) => Padding(padding: EdgeInsets.only(top: pad), child: child),
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: IndexedStack(index: _i, children: [
                      ConnectScreen(refreshTick: _feedTick, topTick: _topTick, onGoAsk: () => _go(3)),
                      const FindScreen(),
                      if (_i == 2) const TalkScreen() else const SizedBox.shrink(), // reload conversations each time it opens
                      AskScreen(onPosted: () => setState(() {
                            _feedTick++;
                            _i = 0;
                          })),
                    ]),
                  ),
                ),
              ),
            ),
            // header (status bar band + 56 px bar), slides up while scrolling down
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedSlide(
                offset: Offset(0, _headerHidden ? -1 : 0),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: _AppHeader(
                  notes: _notes,
                  onHome: () => _go(0),
                ),
              ),
            ),
            // the status bar keeps the page colour while the header is away
            if (_headerHidden) Positioned(top: 0, left: 0, right: 0, height: top, child: ColoredBox(color: p.canvas)),
            // floating island
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: 12),
                child: Center(child: _island(p)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _island(Pal p) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: p.canvas.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: p.border.withValues(alpha: .7)),
        boxShadow: [BoxShadow(color: (p.dark ? Colors.black : const Color(0xFF1E1E1E)).withValues(alpha: p.dark ? .6 : .35), blurRadius: 30, spreadRadius: -6, offset: const Offset(0, 8))],
      ),
      child: AnimatedBuilder(
        animation: _notes,
        builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (var k = 0; k < _items.length; k++) ...[
            if (k > 0) const SizedBox(width: 4),
            _islandItem(p, k, badge: k == 0 ? _notes.unseen : (k == 2 ? _unread : 0)),
          ],
        ]),
      ),
    );
  }

  Widget _islandItem(Pal p, int k, {int badge = 0}) {
    final active = _i == k;
    final fg = active ? p.onInk : p.muted;
    return Semantics(
      button: true,
      selected: active,
      label: t(_items[k].$2),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _go(k),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 68,
          height: 56,
          decoration: BoxDecoration(color: active ? p.ink : Colors.transparent, borderRadius: BorderRadius.circular(24)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Stack(clipBehavior: Clip.none, children: [
              WIcon(_items[k].$1, size: 24, color: fg, strokeWidth: active ? 2.2 : 1.9, spinKey: k == 3 ? _askSpin : 0),
              if (badge > 0)
                Positioned(
                  right: -8,
                  top: -6,
                  child: Container(
                    height: 16,
                    constraints: const BoxConstraints(minWidth: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(8)),
                    child: Text(badge > 9 && k == 0 ? '9+' : '$badge', style: const TextStyle(color: kInk, fontSize: 10, fontWeight: FontWeight.w700, height: 1)),
                  ),
                ),
            ]),
            const SizedBox(height: 2),
            Text(t(_items[k].$2), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, height: 1, color: fg)),
          ]),
        ),
      ),
    );
  }
}

// ======================= header =======================

class _AppHeader extends StatelessWidget {
  final NotificationsModel notes;
  final VoidCallback onHome;
  const _AppHeader({required this.notes, required this.onHome});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final me = context.watch<AuthProvider>().profile;
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.only(top: top),
      decoration: BoxDecoration(
        color: p.chip,
        boxShadow: [
          BoxShadow(
            color: p.dark ? Colors.black.withValues(alpha: .6) : const Color(0xFF1E1E1E).withValues(alpha: .2),
            offset: Offset(0, p.dark ? 8 : 6),
            blurRadius: p.dark ? 16 : 14,
            spreadRadius: -8,
          ),
        ],
      ),
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Padding(padding: const EdgeInsets.only(left: 4), child: LogoInline(size: 36, markSize: 44, onTap: onHome)),
            const Spacer(),
            _Bell(notes: notes),
            const SizedBox(width: 8),
            Builder(
              builder: (ctx) => GestureDetector(
                onTap: () => _openAccountMenu(ctx),
                child: Semantics(
                  button: true,
                  label: t('Account menu'),
                  child: Avatar(name: me?.name ?? 'Me', photoUrl: me?.photoUrl, size: 32, ring: me?.hasUpdate ?? false, type: me?.userType, badge: 14),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Dropdown panels (account menu, notifications) open with the web's `menu-in`: fade + 6 px rise + 0.98 scale.
Future<void> _showPanel(BuildContext context, Widget Function(BuildContext) builder) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (ctx, _, __) => builder(ctx),
    transitionBuilder: (_, a, __, child) {
      final v = Curves.easeOut.transform(a.value);
      return Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 6 * (1 - v)), child: Transform.scale(scale: .98 + .02 * v, alignment: Alignment.topRight, child: child)),
      );
    },
  );
}

BoxDecoration _panelDecoration(Pal p, {double radius = 14}) => BoxDecoration(
      color: p.canvas,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: p.border.withValues(alpha: .6)),
      boxShadow: [
        BoxShadow(color: const Color(0xFF1E1E1E).withValues(alpha: .06), blurRadius: 2, offset: const Offset(0, 1)),
        BoxShadow(color: (p.dark ? Colors.black : const Color(0xFF1E1E1E)).withValues(alpha: p.dark ? .7 : .35), blurRadius: 40, spreadRadius: -12, offset: const Offset(0, 18)),
      ],
    );

void _openAccountMenu(BuildContext context) {
  final top = MediaQuery.of(context).padding.top + 56 + 8;
  _showPanel(context, (ctx) => Stack(children: [Positioned(top: top, right: 12, width: 256, child: const _AccountMenu())]));
}

/// The account menu from the web (account-menu.tsx): account card, View / Edit profile, Saved asks,
/// Dark mode switch, language pills, Log out.
class _AccountMenu extends StatelessWidget {
  const _AccountMenu();

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final auth = context.watch<AuthProvider>();
    final me = auth.profile;
    final themeCtl = context.watch<ThemeController>();
    final i18n = context.watch<I18n>();
    final dark = p.dark;
    if (me == null) return const SizedBox();
    void push(Widget page) {
      final nav = Navigator.of(context);
      nav.pop();
      nav.push(MaterialPageRoute(builder: (_) => page));
    }

    Widget iconBox(WI icon, {Color? bg, Color? fg}) => Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg ?? p.chip, borderRadius: BorderRadius.circular(10)),
          child: WIcon(icon, size: 16, color: fg ?? p.muted, strokeWidth: 1.8),
        );
    Widget item(WI icon, String label, VoidCallback onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [iconBox(icon), const SizedBox(width: 12), Text(t(label), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))]),
          ),
        );

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: _panelDecoration(p),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // account card
          InkWell(
            onTap: () => push(const ProfileScreen()),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: p.chip.withValues(alpha: .5), border: Border(bottom: BorderSide(color: p.border.withValues(alpha: .6)))),
              child: Row(children: [
                Avatar(name: me.name, photoUrl: me.photoUrl, size: 40, ring: me.hasUpdate, type: me.userType, badge: 16),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(me.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    Text('@${me.handle}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: p.muted)),
                    const SizedBox(height: 4),
                    Row(children: [
                      VerifiedBadge(level: me.verification, size: 12),
                      const SizedBox(width: 4),
                      Flexible(child: Text(t(kVerificationLabel[me.verification] ?? ''), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: p.muted))),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              item(WI.user, 'View profile', () => push(const ProfileScreen())),
              item(WI.edit, 'Edit profile', () => push(EditProfileScreen(profile: me))),
              item(WI.bookmark, 'Saved asks', () => push(const SavedPostsScreen())),
              // dark mode switch
              InkWell(
                onTap: () => themeCtl.set(dark ? ThemeMode.light : ThemeMode.dark),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(children: [
                    iconBox(dark ? WI.sun : WI.moon),
                    const SizedBox(width: 12),
                    Expanded(child: Text(t('Dark mode'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 32,
                      height: 18,
                      padding: const EdgeInsets.all(2),
                      alignment: dark ? Alignment.centerRight : Alignment.centerLeft,
                      decoration: BoxDecoration(color: dark ? kGold : p.border, borderRadius: BorderRadius.circular(9)),
                      child: Container(width: 14, height: 14, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 2)])),
                    ),
                  ]),
                ),
              ),
              // language
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(children: [
                  iconBox(WI.globe),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Wrap(spacing: 4, runSpacing: 4, children: [
                      for (final l in kLangs)
                        GestureDetector(
                          onTap: () {
                            if (i18n.lang == l.code) return;
                            Navigator.of(context).pop();
                            i18n.set(l.code);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: i18n.lang == l.code ? p.ink : p.chip, borderRadius: BorderRadius.circular(20)),
                            child: Text(l.native, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: i18n.lang == l.code ? p.onInk : p.text)),
                          ),
                        ),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
          Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border.withValues(alpha: .6)))),
            padding: const EdgeInsets.all(6),
            child: Column(children: [
              item(WI.user, 'Blocked people', () => push(const BlockedPeopleScreen())),
              InkWell(
                onTap: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  deleteAccount(nav.context);
                },
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(children: [
                    iconBox(WI.trash, bg: p.danger.withValues(alpha: .1), fg: p.danger),
                    const SizedBox(width: 12),
                    Text('Delete account', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: p.danger)),
                  ]),
                ),
              ),
            ]),
          ),
          Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border.withValues(alpha: .6)))),
            padding: const EdgeInsets.all(6),
            child: InkWell(
              onTap: () {
                Navigator.of(context).pop();
                auth.logout();
              },
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(children: [
                  iconBox(WI.logout, bg: p.danger.withValues(alpha: .1), fg: p.danger),
                  const SizedBox(width: 12),
                  Text(t('Log out'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: p.danger)),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ======================= notifications =======================

/// A response or referral on one of my asks (GET /notifications).
class AppNote {
  final String id, kind, postId, postTitle, postPath;
  final bool unseen;
  final DateTime createdAt;
  final Peer sharer;
  AppNote({required this.id, required this.kind, required this.postId, required this.postTitle, required this.postPath, required this.unseen, required this.createdAt, required this.sharer});
  factory AppNote.fromJson(Map j) => AppNote(
        id: '${j['id']}',
        kind: '${j['kind']}',
        postId: '${j['postId']}',
        postTitle: '${j['postTitle'] ?? ''}',
        postPath: '${j['postPath'] ?? ''}',
        unseen: j['unseen'] == true,
        createdAt: DateTime.fromMillisecondsSinceEpoch((j['createdAt'] as num?)?.toInt() ?? 0),
        sharer: Peer.fromJson((j['sharer'] as Map?) ?? const {}),
      );
}

class NotificationsModel extends ChangeNotifier {
  int unseen = 0;
  List<AppNote> items = [];
  bool loaded = false;

  Future<void> refresh(AuthProvider auth) async {
    try {
      final d = await auth.api.get('/notifications') as Map;
      unseen = (d['unseen'] as num?)?.toInt() ?? 0;
      items = ((d['items'] as List?) ?? const []).map((e) => AppNote.fromJson(e as Map)).toList();
      loaded = true;
      notifyListeners();
    } catch (_) {}
  }

  /// Badges clear at once, then the server confirms.
  Future<void> markSeen(AuthProvider auth) async {
    if (unseen == 0 && items.every((i) => !i.unseen)) return;
    unseen = 0;
    items = [for (final i in items) AppNote(id: i.id, kind: i.kind, postId: i.postId, postTitle: i.postTitle, postPath: i.postPath, unseen: false, createdAt: i.createdAt, sharer: i.sharer)];
    notifyListeners();
    try {
      await auth.api.post('/notifications/seen', {});
    } catch (_) {
      refresh(auth);
    }
  }
}

class _Bell extends StatelessWidget {
  final NotificationsModel notes;
  const _Bell({required this.notes});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return AnimatedBuilder(
      animation: notes,
      builder: (ctx, _) => Semantics(
        button: true,
        label: t('Notifications'),
        child: InkResponse(
          onTap: () {
            notes.refresh(ctx.read<AuthProvider>());
            final top = MediaQuery.of(ctx).padding.top + 60;
            _showPanel(ctx, (c) => Stack(children: [Positioned(top: top, left: 12, right: 12, child: _NotesPanel(notes: notes))]));
          },
          radius: 20,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Center(
              child: Stack(clipBehavior: Clip.none, children: [
                WIcon(WI.bell, size: 22, color: p.text),
                if (notes.unseen > 0)
                  Positioned(
                    right: -8,
                    top: -6,
                    child: Container(
                      height: 16,
                      constraints: const BoxConstraints(minWidth: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3)]),
                      child: Text(notes.unseen > 9 ? '9+' : '${notes.unseen}', style: const TextStyle(color: kInk, fontSize: 10, fontWeight: FontWeight.w700, height: 1)),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Notifications panel (web notification-bell.tsx): All / Unread / Read, "Mark all as read", a row to
/// turn on phone alerts when they are off, then "who did what on which ask".
class _NotesPanel extends StatefulWidget {
  final NotificationsModel notes;
  const _NotesPanel({required this.notes});
  @override
  State<_NotesPanel> createState() => _NotesPanelState();
}

class _NotesPanelState extends State<_NotesPanel> {
  String _filter = 'all';
  bool? _alertsOn;

  static const _verb = {'contact': 'shared a contact on', 'media': 'shared a photo on', 'info': 'shared a note on', 'referral': 'referred a contact on'};

  @override
  void initState() {
    super.initState();
    context.read<NotificationService>().alertsEnabled().then((v) {
      if (mounted) setState(() => _alertsOn = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final auth = context.read<AuthProvider>();
    return Material(
      color: Colors.transparent,
      child: AnimatedBuilder(
        animation: widget.notes,
        builder: (context, _) {
          final n = widget.notes;
          final shown = n.items.where((i) => _filter == 'all' || (_filter == 'unread' ? i.unseen : !i.unseen)).toList();
          return Container(
            decoration: _panelDecoration(p, radius: 16),
            clipBehavior: Clip.antiAlias,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
                child: Row(children: [
                  Expanded(child: Text(t('Notifications'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                  if (n.unseen > 0)
                    GestureDetector(
                      onTap: () => n.markSeen(auth),
                      child: Text(t('Mark all as read'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.link)),
                    ),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
                child: Row(children: [
                  for (final f in const ['all', 'unread', 'read']) ...[
                    GestureDetector(
                      onTap: () => setState(() => _filter = f),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(color: _filter == f ? p.ink : Colors.transparent, borderRadius: BorderRadius.circular(20)),
                        child: Text(
                          '${t(f == 'all' ? 'All' : f == 'unread' ? 'Unread' : 'Read')}${f == 'unread' && n.unseen > 0 ? ' ${n.unseen > 9 ? '9+' : n.unseen}' : ''}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _filter == f ? p.onInk : p.muted),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                ]),
              ),
              if (_alertsOn == false)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(color: p.chip.withValues(alpha: .6), border: Border(bottom: BorderSide(color: p.border))),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t('Get alerts on this device'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        Text(t('New messages, calls and responses, even when the app is closed.'), style: TextStyle(fontSize: 12, color: p.muted)),
                      ]),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () async {
                        final on = await context.read<NotificationService>().enableAlerts();
                        if (mounted) setState(() => _alertsOn = on);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(20)),
                        child: Text(t('Turn on'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kInk)),
                      ),
                    ),
                  ]),
                ),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .62),
                child: !n.loaded
                    ? const Padding(padding: EdgeInsets.all(24), child: Center(child: LogoLoader(size: 28)))
                    : n.items.isEmpty
                        ? _empty(p, t('No responses yet. When members share a contact on your Ask, it shows up here.'))
                        : shown.isEmpty
                            ? _empty(p, t(_filter == 'unread' ? "You're all caught up." : 'Nothing read yet.'))
                            : ListView.builder(
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                itemCount: shown.length,
                                itemBuilder: (_, i) {
                                  final x = shown[i];
                                  final who = x.sharer.shownName;
                                  return InkWell(
                                    onTap: () {
                                      n.markSeen(auth);
                                      final nav = Navigator.of(context);
                                      nav.pop();
                                      nav.push(MaterialPageRoute(builder: (_) => PostDetailScreen(postId: x.postId)));
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: x.unseen ? kGold.withValues(alpha: .1) : null,
                                        border: i == shown.length - 1 ? null : Border(bottom: BorderSide(color: p.border)),
                                      ),
                                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Avatar(name: who, photoUrl: x.sharer.photoUrl, size: 36, type: x.sharer.userType, badge: 14),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            Text.rich(
                                              TextSpan(children: [
                                                TextSpan(text: who, style: const TextStyle(fontWeight: FontWeight.w700)),
                                                TextSpan(text: ' ${t(_verb[x.kind] ?? 'responded on')} '),
                                                TextSpan(text: '“${x.postTitle}”', style: const TextStyle(fontWeight: FontWeight.w600)),
                                              ]),
                                              style: const TextStyle(fontSize: 14, height: 1.35),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(timeAgo(x.createdAt), style: TextStyle(fontSize: 12, color: p.muted)),
                                          ]),
                                        ),
                                        if (x.unseen) Container(margin: const EdgeInsets.only(top: 6, left: 6), width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFE6AC00), shape: BoxShape.circle)),
                                      ]),
                                    ),
                                  );
                                },
                              ),
              ),
            ]),
          );
        },
      ),
    );
  }

  Widget _empty(Pal p, String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: p.muted)),
      );
}

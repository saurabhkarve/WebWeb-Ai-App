import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth_provider.dart';
import '../config.dart';
import '../contact_sync.dart';
import '../i18n.dart';
import '../models.dart';
import '../notifications.dart';
import '../realtime.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/active_call_banner.dart';
import '../widgets/connection_pill.dart';
import '../widgets/notify_banner.dart';
import '../widgets/tour.dart';
import 'ask.dart';
import 'connect.dart';
import 'favourites.dart';
import 'edit_profile.dart';
import 'find.dart';
import 'leads.dart';
import 'p2.dart';
import 'phonebook.dart';
import 'post_detail.dart';
import 'profile.dart';
import 'service_contacts_sheet.dart';
import 'support_sheet.dart';
import 'talk.dart';
import 'your_asks.dart' show yourAsksRequest;

/// Signed-in chrome, same as the web on phones (app-frame.tsx): the slim header (logo, bell, your
/// avatar with the account menu) and the bar with the five places.
/// The header always stays in view (the web hides it on scroll only on small screens).
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int _i = 2; // Directory
  int _feedTick = 0; // reload the feed
  int _topTick = 0; // scroll the feed to the top
  StreamSubscription? _sub, _pushSub;
  Timer? _poll, _svcTimer;
  final _notes = NotificationsModel();

  // The Smart Phonebook: Home (the feed), Nearby (the local directory), Directory (the contacts, where the app opens:
  // the raised gold button in the middle), Talk (chats and calls), Notifications (responses and referrals on my asks).
  // Asks start from the Directory's search or a "Post an ask" card; Ask is a page of its own (index 5) without the bar. Recents (favourites,
  // calls and pages opened lately) is in the account menu. All five use the WebWeb icon set.
  // From 600 px wide (tablets, desktop) the bar becomes a rail down the left, and pages keep a
  // readable width; from 1200 px the rail shows its labels beside the icons.
  static const _items = [(WI.home, 'Home'), (WI.pin, 'Nearby'), (WI.directory, 'Directory'), (WI.talk, 'Talk'), (WI.bell, 'Notifications')];
  static const _tourKeys = ['nav-feed', 'nav-find', 'nav-contacts', 'nav-talk', 'nav-notes'];
  /// how far the Contacts button rises above the bar
  static const _rise = 20.0;
  static const _feed = 0, _dir = 2, _talk = 3, _notesTab = 4, _ask = 5;
  static const _barH = 64.0;
  int _beforeAsk = _feed;
  /// the Directory's search page is open: it has its own Publish bar, so the bar and Ask step aside
  bool _dirSearch = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unreadChats.addListener(_unreadChanged);
    _notes.addListener(_unreadChanged);
    _loadUnread();
    _notes.refresh(context.read<AuthProvider>());
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _notes.refresh(context.read<AuthProvider>()));
    _sub = context.read<RealtimeService>().events.listen((e) {
      if (e['type'] == 'msg' || e['type'] == 'read') _loadUnread();
      // a response or referral while the app is open: the bell's count updates at once, not at the next poll
      if (e['type'] == 'notify') _refreshAll();
    });
    _pushSub = NotificationService.activity.stream.listen((_) => _refreshAll());
    tourRequest.addListener(_replayTour);
    // service contacts: look quietly if the member turned it on; the one-time invitation from the third open
    _svcTimer = Timer(const Duration(seconds: 12), () async {
      if (!mounted) return;
      final api = context.read<AuthProvider>().api;
      if (await ContactSync.isOn(api).catchError((_) => true)) {
        ContactSync.run(api);
      } else if (await ContactSync.shouldInvite() && mounted && ModalRoute.of(context)?.isCurrent == true) {
        await ContactSync.markInvited();
        if (mounted) showServiceContactsSheet(context, invite: true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      _loadUnread();
      _notes.refresh(context.read<AuthProvider>());
      ContactSync.run(context.read<AuthProvider>().api); // once a day at most, and only when it is on
    }
  }

  void _refreshAll() {
    if (!mounted) return;
    _notes.refresh(context.read<AuthProvider>());
    _loadUnread();
  }

  Future<void> _loadUnread() async {
    final auth = context.read<AuthProvider>();
    await refreshUnreadChats(auth.api, auth.profile?.uid ?? '');
  }

  void _unreadChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unreadChats.removeListener(_unreadChanged);
    _notes.removeListener(_unreadChanged);
    _sub?.cancel();
    _pushSub?.cancel();
    _poll?.cancel();
    _svcTimer?.cancel();
    tourRequest.removeListener(_replayTour);
    _notes.dispose();
    super.dispose();
  }

  /// "Take the app tour" from the account menu: back to the top of Updates (the feed the tour points at), then the tour.
  void _replayTour() {
    if (!mounted) return;
    setState(() {
      _i = _feed;
      _topTick++;
    });
    Tours.start(context, kConnectTourId, kConnectTour);
  }

  void _go(int k) {
    if (k == _ask && _i != _ask) _beforeAsk = _i;
    if (k != _i) HapticFeedback.selectionClick();
    if (k == _i && k == _feed) _topTick++; // tapping Home again scrolls the feed to the top
    if (k == _notesTab) _notes.refresh(context.read<AuthProvider>());
    setState(() => _i = k);
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final top = MediaQuery.of(context).padding.top;
    const header = 56.0;
    final bottom = MediaQuery.of(context).padding.bottom;
    final bar = _i != _ask;
    final w = MediaQuery.sizeOf(context).width;
    final rail = w >= 600;
    final railW = rail ? (w >= 1200 ? 220.0 : 88.0) : 0.0;
    // as on the website (x.com): from 1280 px a column on the right, with a search, the ask prompt and shortcuts
    final right = w >= 1280;
    final rightW = right ? 320.0 : 0.0;
    // the bar steps aside while the keyboard is up, so what is typed has the room (the Directory's search)
    final bottomBar = bar && !rail && MediaQuery.viewInsetsOf(context).bottom == 0 && !(_i == _dir && _dirSearch);
    // without the bar on Ask, back returns to the tab it was opened from
    return PopScope(
      canPop: _i != _ask,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _i == _ask) _go(_beforeAsk);
      },
      child: Scaffold(
      // stretch + expand: the page area is always the full width. With a loose width, a Stack whose only unpositioned child
      // is the empty banner host (SizedBox.shrink) sized itself 0 wide, and every page in it was laid out 0 wide: a blank screen
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const ActiveCallBanner(),
        Expanded(
          child: Stack(fit: StackFit.expand, children: [
            // pages, below the header
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(top: top + header, bottom: bottomBar ? _barH + bottom : 0, left: railW, right: rightW),
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  removeBottom: bottomBar,
                  removeLeft: rail,
                  child: IndexedStack(index: _i, children: [
                    _fit(ConnectScreen(refreshTick: _feedTick, topTick: _topTick, onGoAsk: () => _go(_ask), active: _i == _feed), 680),
                    _fit(const FindScreen(), 900),
                    _fit(PhonebookHome(active: _i == _dir, onAsk: () => _go(_ask), onSeeAsks: () => _go(_feed), onPosted: () => setState(() => _feedTick++), onSearching: (on) => setState(() => _dirSearch = on)), right ? 680 : 1240),
                    // Talk loads afresh each time it opens
                    if (_i == _talk) _fit(const TalkScreen(), 900) else const SizedBox.shrink(),
                    _fit(_NotesPanel(notes: _notes, page: true, onAsk: () => _go(_ask)), 760),
                    _fit(
                        AskScreen(active: _i == _ask, onBack: () => _go(_beforeAsk), onPosted: () => setState(() {
                              _feedTick++;
                              _i = _feed;
                            })),
                        760),
                  ]),
                ),
              ),
            ),
            // header (status bar band + 56 px bar), always in view
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _AppHeader(onHome: () => _go(_dir)),
            ),
            // "Waiting for network…" / "Connecting…" under the header, WhatsApp-style
            Positioned(top: top + header + 8, left: 0, right: 0, child: const ConnectionPill()),
            // a message or a new ask while the app is open: a banner with Reply (and Refer) right on it
            const NotifyBannerHost(),
            // the bar along the bottom, Contacts raised in the middle; Ask has its own Publish bar instead
            if (bottomBar) Positioned(left: 0, right: 0, bottom: 0, height: _barH + bottom + _rise, child: _bar(p, bottom)),
            // tablets and desktop: the rail down the left, under the header
            if (rail) Positioned(left: 0, top: top + header, bottom: 0, width: railW, child: _rail(p, railW >= 200)),
            // wide screens: the column on the right, as on the website
            if (right) Positioned(right: 0, top: top + header, bottom: 0, width: rightW, child: _rightRail(p)),
          ]),
        ),
      ]),
      ),
    );
  }

  /// Wide screens (1280 px and up), as the website's right column: a search, the ask prompt and the shortcuts.
  Widget _rightRail(Pal p) {
    final me = context.watch<AuthProvider>().profile;
    BoxDecoration card() => BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Color(0x141E1E1E), blurRadius: 18, offset: Offset(0, 6))]);
    void sub(String title, Widget body) => Navigator.push(context, MaterialPageRoute(builder: (_) => SubPage(title: t(title), body: body)));
    final links = <(String, VoidCallback)>[
      if (me != null) ('Your public page', () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: me.handle)))),
      ('Your asks', () {
        yourAsksRequest.value = true;
        _go(_ask);
      }),
      ('Leads for you', () => sub('Leads for you', const LeadsScreen())),
      ('Today in your area', () => sub('Today in your area', const TodayScreen())),
      ('Alerts', () => sub('Alerts', const AlertsScreen())),
      ('Your week', () => sub('Your week', const WeekScreen())),
      ('Saved asks', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SavedPostsScreen()))),
      if (me != null) ('Edit profile', () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfileScreen(profile: me)))),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => _go(_dir),
          borderRadius: BorderRadius.circular(28),
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(28), boxShadow: const [BoxShadow(color: Color(0x141E1E1E), blurRadius: 18, offset: Offset(0, 6))]),
            child: Row(children: [
              WIcon(WI.search, size: 20, color: p.muted),
              const SizedBox(width: 10),
              Expanded(child: Text(t('Search people, jobs, asks'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: p.muted))),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: card(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [WIcon(WI.ask, size: 20, color: p.text), const SizedBox(width: 8), Text(t('Need something?'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))]),
            const SizedBox(height: 4),
            Text(t('Post an ask and reach members across Navi Mumbai.'), style: TextStyle(fontSize: 13.5, height: 1.35, color: p.muted)),
            const SizedBox(height: 14),
            InkWell(
              onTap: () => _go(_ask),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: p.dark ? const Color(0xFFF2F0E8) : kInk, borderRadius: BorderRadius.circular(20)),
                child: Text(t('Post an ask'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.dark ? kInk : Colors.white)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: card(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(padding: const EdgeInsets.fromLTRB(8, 4, 8, 4), child: Text(t('Shortcuts').toUpperCase(), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .6, color: p.muted))),
            for (final l in links)
              InkWell(
                onTap: l.$2,
                borderRadius: BorderRadius.circular(10),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10), child: Text(t(l.$1), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
              ),
          ]),
        ),
      ]),
    );
  }

  /// A page at a readable width on a wide screen, centred, and always told the width it really has (beside the rail
  /// it is narrower than the screen): cards and edge-to-edge rows size themselves from it.
  Widget _fit(Widget page, double max) => LayoutBuilder(builder: (context, c) {
        final mq = MediaQuery.of(context);
        final w = c.maxWidth < max ? c.maxWidth : max;
        if (w == mq.size.width) return page;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: w, height: c.maxHeight, child: MediaQuery(data: mq.copyWith(size: Size(w, mq.size.height)), child: page)),
        );
      });

  Widget _bar(Pal p, double bottom) => Stack(clipBehavior: Clip.none, children: [
        // the empty strip above the bar lets taps through to the page; only the raised button sits in it
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: _barH + bottom,
          child: Container(
            padding: EdgeInsets.only(bottom: bottom),
            decoration: BoxDecoration(color: p.canvas, border: Border(top: BorderSide(color: p.border.withValues(alpha: .7)))),
            child: Row(children: [
              for (var k = 0; k < _items.length; k++)
                Expanded(
                  child: KeyedSubtree(
                    key: k == _dir ? null : Tours.key(_tourKeys[k]),
                    child: k == _dir ? _dirLabel(p) : _barItem(p, k, badge: _badgeOf(k)),
                  ),
                ),
            ]),
          ),
        ),
        Positioned(top: 0, left: 0, right: 0, child: Center(child: KeyedSubtree(key: Tours.key(_tourKeys[_dir]), child: _dirButton(p, 60)))),
      ]);

  /// Directory, the heart of the app: always the gold round button, raised in the middle of the bar.
  Widget _dirButton(Pal p, double size) {
    final active = _i == _dir;
    return Semantics(
      button: true,
      selected: active,
      label: t(_items[_dir].$2),
      child: GestureDetector(
        onTap: () => _go(_dir),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: kGoldGradient,
            shape: BoxShape.circle,
            border: Border.all(color: p.canvas, width: 4),
            boxShadow: [BoxShadow(color: const Color(0xFFD6AA00).withValues(alpha: active ? .55 : .35), blurRadius: active ? 18 : 12, spreadRadius: -4, offset: const Offset(0, 6))],
          ),
          child: Center(child: WIcon(_items[_dir].$1, color: kInk, size: size * .46, strokeWidth: active ? 2.2 : 2)),
        ),
      ),
    );
  }

  /// the label under the raised button, in the bar
  Widget _dirLabel(Pal p) {
    final active = _i == _dir;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _go(_dir),
      child: ExcludeSemantics(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(t(_items[_dir].$2), maxLines: 1, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: active ? p.text : p.muted))),
          ),
        ),
      ),
    );
  }

  Widget _barItem(Pal p, int k, {int badge = 0}) {
    final active = _i == k;
    final tone = p.dark ? const Color(0xFFFFD84A) : const Color(0xFF7A5A00);
    final fg = active ? tone : p.muted;
    return Semantics(
      button: true,
      selected: active,
      label: t(_items[k].$2),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _go(k),
        child: ExcludeSemantics(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            // the Material "pill" behind the icon of the open tab
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 56,
              height: 30,
              decoration: BoxDecoration(color: active ? kGold.withValues(alpha: p.dark ? .25 : .22) : Colors.transparent, borderRadius: BorderRadius.circular(15)),
              child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
                WIcon(_items[k].$1, size: 23, color: fg, strokeWidth: active ? 2.2 : 1.9),
                if (badge > 0) Positioned(right: 8, top: 0, child: _badge(badge)),
              ]),
            ),
            const SizedBox(height: 4),
            FittedBox(fit: BoxFit.scaleDown, child: Text(t(_items[k].$2), maxLines: 1, style: TextStyle(fontSize: 11.5, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? p.text : p.muted))),
          ]),
        ),
      ),
    );
  }

  /// unread chats on Talk, unseen responses on Notifications
  int _badgeOf(int k) => k == _talk ? unreadChats.value : (k == _notesTab ? _notes.unseen : 0);

  Widget _badge(int n) => Container(
        height: 16,
        constraints: const BoxConstraints(minWidth: 16),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(8)),
        child: Text(n > 99 ? '99+' : '$n', style: const TextStyle(color: kInk, fontSize: 10, fontWeight: FontWeight.w700, height: 1)),
      );

  /// Tablets and desktop: the five places; Directory keeps its gold. [labels]: the wide rail,
  /// with each label beside its icon.
  Widget _rail(Pal p, bool labels) {
    final tone = p.dark ? const Color(0xFFFFD84A) : const Color(0xFF7A5A00);
    Widget item(int k) {
      final active = _i == k;
      final home = k == _dir;
      final badge = _badgeOf(k);
      final icon = Stack(clipBehavior: Clip.none, children: [
        WIcon(_items[k].$1, size: 24, color: home ? kInk : (active ? tone : p.muted), strokeWidth: active || home ? 2.2 : 1.9),
        if (badge > 0) Positioned(right: -10, top: -6, child: _badge(badge)),
      ]);
      final fill = home ? null : (active ? kGold.withValues(alpha: p.dark ? .25 : .22) : Colors.transparent);
      final label = Text(t(_items[k].$2), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: labels ? 14.5 : 11.5, fontWeight: active || home ? FontWeight.w700 : FontWeight.w500, color: active ? p.text : p.muted));
      return KeyedSubtree(
        key: Tours.key(_tourKeys[k]),
        child: Semantics(
          button: true,
          selected: active,
          label: t(_items[k].$2),
          child: InkWell(
            onTap: () => _go(k),
            borderRadius: BorderRadius.circular(28),
            child: ExcludeSemantics(
              child: labels
                  ? Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: fill,
                        gradient: home ? kGoldGradient : null,
                        borderRadius: BorderRadius.circular(26),
                        border: home && active ? Border.all(color: kInk.withValues(alpha: .5), width: 1.5) : null,
                      ),
                      child: Row(children: [icon, const SizedBox(width: 14), Expanded(child: home ? Text(t(_items[k].$2), maxLines: 1, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: kInk)) : label)]),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: home ? 52 : 56,
                          height: home ? 52 : 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: fill,
                            gradient: home ? kGoldGradient : null,
                            shape: home ? BoxShape.circle : BoxShape.rectangle,
                            borderRadius: home ? null : BorderRadius.circular(16),
                            boxShadow: home ? [BoxShadow(color: const Color(0xFFD6AA00).withValues(alpha: active ? .5 : .3), blurRadius: 14, spreadRadius: -4, offset: const Offset(0, 5))] : null,
                          ),
                          child: icon,
                        ),
                        const SizedBox(height: 4),
                        label,
                      ]),
                    ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(color: p.canvas, border: Border(right: BorderSide(color: p.border.withValues(alpha: .7)))),
      padding: EdgeInsets.fromLTRB(labels ? 16 : 8, 16, labels ? 16 : 8, 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: labels ? CrossAxisAlignment.stretch : CrossAxisAlignment.center, children: [
          for (var k = 0; k < _items.length; k++) Padding(padding: const EdgeInsets.only(bottom: 6), child: item(k)),
        ]),
      ),
    );
  }
}

// ======================= header =======================

class _AppHeader extends StatelessWidget {
  final VoidCallback onHome;
  const _AppHeader({required this.onHome});

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
            color: p.dark ? const Color(0xFF1E1E1E).withValues(alpha: .6) : const Color(0xFF1E1E1E).withValues(alpha: .2),
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
            // with the SMART PHONEBOOK slogan, as on the web; shrinks rather than crowd the avatar on the narrowest phones
            // (notifications are a tab of the bar now)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 4, right: 8),
                child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: LogoInline(size: 28, markSize: 36, tagline: true, onTap: onHome)),
              ),
            ),
            const SizedBox(width: 6),
            Builder(
              builder: (ctx) => GestureDetector(
                onTap: () => _openAccountMenu(ctx),
                child: Semantics(
                  button: true,
                  label: t('Account menu'),
                  child: Avatar(
                    key: Tours.key('account'),name: me?.name ?? 'Me', photoUrl: me?.photoUrl, size: 32, ring: me?.hasUpdate ?? false, framed: true, type: me?.userType, badge: 14),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

BoxDecoration _panelDecoration(Pal p, {double radius = 14}) => BoxDecoration(
      color: p.canvas,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: p.border.withValues(alpha: .6)),
      boxShadow: [
        BoxShadow(color: const Color(0xFF1E1E1E).withValues(alpha: .06), blurRadius: 2, offset: const Offset(0, 1)),
        BoxShadow(color: (p.dark ? const Color(0xFF1E1E1E) : const Color(0xFF1E1E1E)).withValues(alpha: p.dark ? .7 : .35), blurRadius: 40, spreadRadius: -12, offset: const Offset(0, 18)),
      ],
    );

void _openAccountMenu(BuildContext context) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0x8014120C),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) => const Align(alignment: Alignment.centerRight, child: _AccountMenu()),
    transitionBuilder: (_, a, __, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

/// The account menu from the web (account-menu.tsx) as a full-height drawer from the right: ⋯ (Log out) and
/// close at the top, account card, View / Edit profile, Saved asks, Help & Support (opens the website),
/// Account and privacy (a tab of Edit profile); language pills and the dark mode switch share the foot.
/// The business pages of this sign-in: tap one to switch to it, or add another.
class _PagesSwitcher extends StatefulWidget {
  const _PagesSwitcher();
  @override
  State<_PagesSwitcher> createState() => _PagesSwitcherState();
}

class _PagesSwitcherState extends State<_PagesSwitcher> {
  List<Map>? _pages;
  bool _busy = false;
  static const _max = 5;

  @override
  void initState() {
    super.initState();
    context.read<AuthProvider>().accounts().then((l) {
      if (mounted) setState(() => _pages = l);
    }).catchError((_) {});
  }

  Future<void> _go(String? uid) async {
    if (_busy) return;
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      await context.read<AuthProvider>().switchAccount(uid);
      nav.popUntil((r) => r.isFirst);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    if (pages == null) return const SizedBox.shrink();
    final p = Pal.of(context);
    final others = pages.where((a) => a['active'] != true).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final a in others)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _busy ? null : () => _go(a['uid'] as String),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(children: [
                Avatar(name: '${a['name'] ?? ''}', photoUrl: a['photoURL'] as String?, size: 32, type: a['userType'] as String?),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(('${a['company'] ?? ''}').isNotEmpty ? '${a['company']}' : (('${a['name'] ?? ''}').isNotEmpty ? '${a['name']}' : t('New business page')),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    Text(a['handle'] != null ? '@${a['handle']}' : t('Set up this page'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted)),
                  ]),
                ),
              ]),
            ),
          ),
        if (pages.length < _max)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _busy ? null : () => _go(null),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: p.border)),
                  child: Text('+', style: TextStyle(fontSize: 18, height: 1, color: p.muted)),
                ),
                const SizedBox(width: 12),
                Text(t('Add a business page'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _AccountMenu extends StatelessWidget {
  const _AccountMenu();

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final auth = context.watch<AuthProvider>();
    final me = auth.profile;
    final themeCtl = context.watch<ThemeController>();
    final i18n = context.watch<I18n>();
    final mq = MediaQuery.of(context);
    if (me == null) return const SizedBox();
    void push(Widget page) {
      final nav = Navigator.of(context);
      nav.pop();
      nav.push(MaterialPageRoute(builder: (_) => page));
    }

    // compact rows (32 icon box, 42 a row) so the whole menu fits on a phone without scrolling
    Widget iconBox(WI icon, {Color? bg, Color? fg}) => Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg ?? p.chip, borderRadius: BorderRadius.circular(9)),
          child: WIcon(icon, size: 17, color: fg ?? p.muted, strokeWidth: 1.8),
        );
    Widget row(WI icon, Widget label, VoidCallback? onTap, {Color? bg, Color? fg, Widget? trailing}) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: Row(children: [iconBox(icon, bg: bg, fg: fg), const SizedBox(width: 12), Expanded(child: label), if (trailing != null) trailing]),
          ),
        );
    Text label(String s, {Color? color}) => Text(s, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: color));
    Widget item(WI icon, String text, VoidCallback onTap) => row(icon, label(t(text)), onTap);
    final divider = Divider(height: 1, color: p.border.withValues(alpha: .6));

    // the drawer's ⋯ (Log out) and close sit on the account card: one section, no title bar above it
    final Widget actions = Row(mainAxisSize: MainAxisSize.min, children: [
      PopupMenuButton<String>(
        tooltip: t('More options'),
        icon: WIcon(WI.more, size: 22, color: p.text),
        color: p.canvas,
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: p.border.withValues(alpha: .6))),
        onSelected: (_) {
          Navigator.of(context).pop();
          auth.logout();
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'logout',
            child: Row(children: [
              WIcon(WI.logout, size: 20, color: p.danger, strokeWidth: 1.8),
              const SizedBox(width: 12),
              Text(t('Log out'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: p.danger)),
            ]),
          ),
        ],
      ),
      IconButton(tooltip: t('Close'), onPressed: () => Navigator.of(context).pop(), icon: WIcon(WI.close, size: 22, color: p.text)),
    ]);

    return Material(
      color: p.canvas,
      elevation: 16,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: (mq.size.width * .88).clamp(0, 380).toDouble(),
        height: mq.size.height,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(height: mq.padding.top),
          // account card: this page, then the other pages of the sign-in and Add, as one block
          Container(
            decoration: BoxDecoration(color: p.chip.withValues(alpha: .5), border: Border(top: BorderSide(color: p.border.withValues(alpha: .6)), bottom: BorderSide(color: p.border.withValues(alpha: .6)))),
            child: Stack(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: () => push(const ProfileScreen()),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 96, 12),
              child: Row(children: [
                Avatar(name: me.name, photoUrl: me.photoUrl, size: 48, ring: me.hasUpdate, type: me.userType, badge: 18, uid: me.uid),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(me.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('@${me.handle}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.muted)),
                    const SizedBox(height: 4),
                    Row(children: [
                      VerifiedBadge(level: me.verification, premium: me.premium, plan: me.plan, size: 14),
                      const SizedBox(width: 4),
                      Flexible(child: Text(t(kVerificationLabel[me.verification] ?? ''), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: p.muted))),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
          const _PagesSwitcher(),
              ]),
              Positioned(top: 2, right: 4, child: actions),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(6), children: [
              item(WI.edit, 'Edit profile', () => push(EditProfileScreen(profile: me))),
              item(WI.clock, 'Recents', () => push(SubPage(title: t('Recents'), body: const RecentsScreen()))),
              // leads, today, alerts and the week: one page of their own
              item(WI.sparkle, 'For your business', () => push(SubPage(title: t('For your business'), body: const _BusinessHub()))),
              item(WI.bookmark, 'Saved asks', () => push(const SavedPostsScreen())),
              // help articles, writing to us, the assistant and the tour: one sheet
              item(WI.help, 'Help & Support', () {
                Navigator.of(context).pop();
                _openHelp(context);
              }),
              const SizedBox(height: 4),
              divider,
              const SizedBox(height: 4),
              // two-step verification, blocked people, sign out everywhere, delete account: a tab of Edit profile
              item(WI.lock, 'Account and privacy', () => push(EditProfileScreen(profile: me, tab: 'account'))),
              if (ContactSync.supported) const _ServiceContactsRow(),
            ]),
          ),
          divider,
          Padding(
            padding: EdgeInsets.fromLTRB(8, 4, 8, 4 + mq.padding.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // language and theme in one row
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
                child: Row(children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      // the current language; tapping it lists all languages above it
                      child: PopupMenuButton<String>(
                        tooltip: t('Language'),
                        color: p.canvas,
                        position: PopupMenuPosition.over,
                        offset: const Offset(0, -8),
                        constraints: const BoxConstraints(minWidth: 200),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: p.border.withValues(alpha: .6))),
                        onSelected: (code) {
                          if (i18n.lang == code) return;
                          Navigator.of(context).pop();
                          i18n.set(code);
                        },
                        itemBuilder: (_) => [
                          for (final l in kLangs)
                            PopupMenuItem(
                              value: l.code,
                              child: Row(children: [
                                Text(l.native, style: TextStyle(fontSize: 15, fontWeight: i18n.lang == l.code ? FontWeight.w700 : FontWeight.w500, color: p.text)),
                                if (l.native != l.name) ...[
                                  const SizedBox(width: 8),
                                  Text(l.name, style: TextStyle(fontSize: 12, color: p.muted)),
                                ],
                                const Spacer(),
                                if (i18n.lang == l.code) const WIcon(WI.check, size: 18, color: kGold, strokeWidth: 2.4),
                              ]),
                            ),
                        ],
                        child: Container(
                          height: 40,
                          padding: const EdgeInsets.only(left: 12, right: 10),
                          decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(20)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            WIcon(WI.globe, size: 18, color: p.muted, strokeWidth: 1.8),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                kLangs.firstWhere((l) => l.code == i18n.lang, orElse: () => kLangs.first).native,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.text),
                              ),
                            ),
                            const SizedBox(width: 6),
                            WIcon(WI.chevronUp, size: 16, color: p.muted, strokeWidth: 2),
                          ]),
                        ),
                      ),
                    ),
                  ),
                  // theme: follow the device (the default), light or dark
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      for (final o in [(ThemeMode.system, WI.monitor, 'Device theme'), (ThemeMode.light, WI.sun, 'Light'), (ThemeMode.dark, WI.moon, 'Dark')])
                        Semantics(
                          button: true,
                          selected: themeCtl.mode == o.$1,
                          label: t(o.$3),
                          child: GestureDetector(
                            onTap: () => themeCtl.set(o.$1),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(color: themeCtl.mode == o.$1 ? p.card : Colors.transparent, shape: BoxShape.circle),
                              child: Center(child: WIcon(o.$2, size: 18, color: themeCtl.mode == o.$1 ? p.text : p.muted, strokeWidth: 1.8)),
                            ),
                          ),
                        ),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              const _AppVersion(),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// The account menu's "For your business": leads, today in your area, alerts and your week, one tap each.
class _BusinessHub extends StatelessWidget {
  const _BusinessHub();

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    Widget tile(WI icon, String title, Widget body) => ListTile(
          leading: Container(width: 36, height: 36, alignment: Alignment.center, decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(10)), child: WIcon(icon, size: 19, color: p.muted, strokeWidth: 1.8)),
          title: Text(t(title), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          trailing: WIcon(WI.chevronRight, size: 18, color: p.muted),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SubPage(title: t(title), body: body))),
        );
    return ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
      tile(WI.sparkle, 'Leads for you', const LeadsScreen()),
      tile(WI.sun, 'Today in your area', const TodayScreen()),
      tile(WI.bell, 'Alerts', const AlertsScreen()),
      tile(WI.deals, 'Your week', const WeekScreen()),
    ]);
  }
}

/// Help & Support from the account menu: the help articles (on the website, so they stay current without an app
/// update), the Help page's form in the app, the @webwebai assistant, and the app tour.
void _openHelp(BuildContext context) {
  final p = Pal.of(context);
  final auth = context.read<AuthProvider>();
  final lang = context.read<I18n>().lang;
  final nav = Navigator.of(context);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: p.canvas,
    builder: (ctx) {
      Widget row(WI icon, String label, VoidCallback onTap) => ListTile(
            leading: WIcon(icon, size: 21, color: p.muted, strokeWidth: 1.8),
            title: Text(t(label), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            onTap: () {
              Navigator.pop(ctx);
              onTap();
            },
          );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            row(WI.help, 'Help articles', () {
              final from = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
              launchUrl(Uri.parse('$siteUrl/help?lang=$lang&from=$from'), mode: LaunchMode.externalApplication);
            }),
            row(WI.talk, 'Write to us', () => showSupportSheet(nav.context)),
            // @webwebai: the assistant answers in a chat
            row(WI.sparkle, 'Ask WebWeb AI', () async {
              try {
                final u = Profile.fromJson(await auth.api.get('/users/handle/webwebai') as Map);
                final ctx = nav.context;
                if (ctx.mounted) openChat(ctx, Peer.fromProfile(u));
              } catch (_) {}
            }),
            row(WI.info, 'Take the app tour', () => tourRequest.value++),
          ]),
        ),
      );
    },
  );
}

/// "WebWeb AI · Version 0.1.9 (42)" at the foot of the account menu.
class _AppVersion extends StatelessWidget {
  const _AppVersion();
  static final _info = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return FutureBuilder<PackageInfo>(
      future: _info,
      builder: (_, s) {
        final i = s.data;
        return Text(
          i == null ? ' ' : '${t('WebWeb AI')} · ${t('Version {v}', {'v': i.version})}${i.buildNumber.isEmpty ? '' : ' (${i.buildNumber})'}',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: p.muted, fontFeatures: const [FontFeature.tabularFigures()]),
        );
      },
    );
  }
}

/// Account menu row: Service contacts on or off (see [ContactSync]). Turning on opens the explanation first.
class _ServiceContactsRow extends StatefulWidget {
  const _ServiceContactsRow();
  @override
  State<_ServiceContactsRow> createState() => _ServiceContactsRowState();
}

class _ServiceContactsRowState extends State<_ServiceContactsRow> {
  bool? _on;

  @override
  void initState() {
    super.initState();
    ContactSync.isOn(context.read<AuthProvider>().api).then((v) {
      if (mounted) setState(() => _on = v);
    }, onError: (_) {});
  }

  Future<void> _toggle() async {
    if (_on == null) return;
    final changed = _on! ? await turnOffServiceContacts(context) : await showServiceContactsSheet(context) == true;
    if (changed && mounted) setState(() => _on = !_on!);
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final on = _on == true;
    return InkWell(
      onTap: _toggle,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(10)),
            child: WIcon(WI.contactCard, size: 18, color: p.muted, strokeWidth: 1.8),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('Service contacts'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              Text(t('Share plumbers, electricians, cabs…'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted)),
            ]),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 44,
            height: 24,
            padding: const EdgeInsets.all(3),
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(color: on ? kGold : p.border, borderRadius: BorderRadius.circular(12)),
            child: Container(width: 18, height: 18, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x331E1E1E), blurRadius: 2)])),
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

/// Notifications panel (web notification-bell.tsx): All / Unread / Read, "Mark all as read", a row to
/// turn on phone alerts when they are off, then "who did what on which ask".
class _NotesPanel extends StatefulWidget {
  final NotificationsModel notes;
  /// true: the Notifications tab (fills the page, no pop on tap); false: a floating panel
  final bool page;
  /// the empty tab's "Post an ask"
  final VoidCallback? onAsk;
  const _NotesPanel({required this.notes, this.page = false, this.onAsk});
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
            decoration: widget.page ? BoxDecoration(color: p.canvas) : _panelDecoration(p, radius: 16),
            clipBehavior: Clip.antiAlias,
            child: Column(mainAxisSize: widget.page ? MainAxisSize.max : MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (widget.page) ..._pageHead(p, n, auth) else ...[
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
              ],
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
              _bound(
                context,
                child: !n.loaded
                    ? const Padding(padding: EdgeInsets.all(24), child: Center(child: LogoLoader(size: 28)))
                    : n.items.isEmpty
                        ? (widget.page ? _emptyPage(p) : _empty(p, t('No responses yet. When members share a contact on your Ask, it shows up here.')))
                        : shown.isEmpty
                            ? _empty(p, t(_filter == 'unread' ? "You're all caught up." : 'Nothing read yet.'))
                            : ListView.builder(
                                shrinkWrap: !widget.page,
                                padding: EdgeInsets.only(bottom: widget.page ? 100 : 0),
                                itemCount: shown.length,
                                itemBuilder: (_, i) {
                                  final x = shown[i];
                                  final who = x.sharer.shownName;
                                  return InkWell(
                                    onTap: () {
                                      n.markSeen(auth);
                                      final nav = Navigator.of(context);
                                      if (!widget.page) nav.pop();
                                      nav.push(MaterialPageRoute(builder: (_) => PostDetailScreen(postId: x.postId)));
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: x.unseen ? kGold.withValues(alpha: .1) : null,
                                        border: i == shown.length - 1 ? null : Border(bottom: BorderSide(color: p.border)),
                                      ),
                                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Avatar(name: who, photoUrl: x.sharer.photoUrl, size: 36, type: x.sharer.userType, badge: 14, uid: x.sharer.uid),
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

  /// the list: filling the rest of the page on the tab, a capped height in the floating panel
  Widget _bound(BuildContext context, {required Widget child}) =>
      widget.page ? Expanded(child: child) : ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .62), child: child);

  /// The tab's top, as Talk's: the title and how many are new, Mark all as read, then the filters as gold chips.
  List<Widget> _pageHead(Pal p, NotificationsModel n, AuthProvider auth) {
    Widget chip(String f, String label) {
      final on = _filter == f;
      return GestureDetector(
        onTap: () => setState(() => _filter = f),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(gradient: on ? kGoldGradient : null, color: on ? null : p.chip, borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(t(label), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: on ? kInk : p.muted)),
            if (f == 'unread' && n.unseen > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(color: kInk, borderRadius: BorderRadius.circular(10)),
                child: Text(n.unseen > 99 ? '99+' : '${n.unseen}', style: const TextStyle(fontSize: 11, height: 16 / 11, fontWeight: FontWeight.w700, color: kGold)),
              ),
            ],
          ]),
        ),
      );
    }

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('Notifications'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1)),
              const SizedBox(height: 4),
              Text(n.unseen > 0 ? '${n.unseen} ${t('unread')}' : t("You're all caught up"), style: TextStyle(fontSize: 14, color: p.muted)),
            ]),
          ),
          if (n.unseen > 0) TextButton(onPressed: () => n.markSeen(auth), child: Text(t('Mark all as read'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(children: [chip('all', 'All'), const SizedBox(width: 8), chip('unread', 'Unread'), const SizedBox(width: 8), chip('read', 'Read')]),
      ),
    ];
  }

  /// The empty tab: what will show here, and the way to get some
  Widget _emptyPage(Pal p) => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
        DashedBox(
          radius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(children: [
            Container(width: 64, height: 64, alignment: Alignment.center, decoration: BoxDecoration(color: p.tagBg, shape: BoxShape.circle), child: WIcon(WI.bell, size: 28, color: p.tagText)),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(t('No responses yet. When members share a contact on your Ask, it shows up here.'), textAlign: TextAlign.center, style: TextStyle(fontSize: 14.5, height: 1.4, color: p.muted)),
            ),
            if (widget.onAsk != null) ...[
              const SizedBox(height: 18),
              GoldButton(label: t('Post an ask'), wi: WI.askPlus, height: 44, onPressed: widget.onAsk),
            ],
          ]),
        ),
      ]);

  Widget _empty(Pal p, String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: p.muted)),
      );
}

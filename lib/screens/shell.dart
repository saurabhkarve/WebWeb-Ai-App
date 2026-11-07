import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth_provider.dart';
import '../device_perms.dart';
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
import 'connect.dart';
import 'edit_profile.dart';
import 'find.dart';
import 'intro_card.dart';
import 'leads.dart';
import 'p2.dart';
import 'phonebook.dart';
import 'post_detail.dart';
import 'profile.dart';
import 'service_contacts_sheet.dart';
import 'shared_contacts.dart';
import 'support_sheet.dart';
import 'talk.dart';

/// The WEBWEB logo's own disc gradient (the Find button and its rail item wear it).
const _logoGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFE84D), Color(0xFFFFB800)]);

/// Signed-in chrome, same as the web on phones (app-frame.tsx): the slim header (logo, bell, your
/// avatar with the account menu) and the bar with the five places.
/// The header always stays in view; it shrinks to a slimmer bar while a page is scrolled down.
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
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
  static const _items = [
    (WI.refer, 'Refer'),
    (WI.pin, 'Nearby'),
    (WI.directory, 'Find'),
    (WI.talk, 'Talk'),
    (WI.bell, 'Notifications')
  ];
  static const _tourKeys = [
    'nav-feed',
    'nav-find',
    'nav-contacts',
    'nav-talk',
    'nav-notes'
  ];

  /// how far the Contacts button rises above the bar
  static const _rise = 0.0;
  static const _feed = 0, _dir = 2, _talk = 3, _notesTab = 4;
  static const _barH = 64.0;

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
    _poll = Timer.periodic(const Duration(seconds: 30),
        (_) => _notes.refresh(context.read<AuthProvider>()));
    _sub = context.read<RealtimeService>().events.listen((e) {
      if (e['type'] == 'msg' || e['type'] == 'read') _loadUnread();
      // a response or referral while the app is open: the bell's count updates at once, not at the next poll
      if (e['type'] == 'notify') _refreshAll();
    });
    _pushSub = NotificationService.activity.stream.listen((_) => _refreshAll());
    // no tour runs any more: nothing dims the page
    // the phone's location and contacts count towards the profile's strength: read them now
    DevicePerms.i.refresh();
    // service contacts are on by default once contacts are allowed: a notice the first time (with the way to turn it off), then it looks quietly
    _svcTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) autoServiceContacts(context);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      _loadUnread();
      DevicePerms.i.refresh();
      _notes.refresh(context.read<AuthProvider>());
      ContactSync.run(context
          .read<AuthProvider>()
          .api); // once a day at most, and only when it is on
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
    _slideC.dispose();
    _slideX.dispose();
    _dockC.dispose();
    _dockT.dispose();
    WidgetsBinding.instance.removeObserver(this);
    unreadChats.removeListener(_unreadChanged);
    _notes.removeListener(_unreadChanged);
    _sub?.cancel();
    _pushSub?.cancel();
    _poll?.cancel();
    _svcTimer?.cancel();
    _notes.dispose();
    super.dispose();
  }

  // The page slides with the finger while swiping and slides in from the side it came from when the tab changes.
  final ValueNotifier<double> _slideX = ValueNotifier(0);
  late final AnimationController _slideC = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  double _slideFrom = 0;

  void _slideIn(double from) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _slideX.value = 0;
      return;
    }
    _slideFrom = from;
    _slideC.removeListener(_slideTick);
    _slideC.addListener(_slideTick);
    _slideC.forward(from: 0);
  }

  // The island's open place as a position (0 Refer, 1 Find, 2 Talk; -10 when none of them is open). It glides to the new place
  // on a tap and follows the finger while the page (or the island itself) is swiped.
  static const _order = [_feed, _dir, _talk];
  double _dockIdx(int k) => _order.contains(k) ? _order.indexOf(k).toDouble() : -10.0;
  late final ValueNotifier<double> _dockT = ValueNotifier(_dockIdx(_i));
  late final AnimationController _dockC = AnimationController(vsync: this, duration: const Duration(milliseconds: 280))..addStatusListener((st) {
      if (st == AnimationStatus.completed || st == AnimationStatus.dismissed) _dockLive = false;
    });
  bool _dockLive = false;
  double _dockFrom = 0, _dockTo = 0;

  void _dockGo(double to) {
    final from = _dockT.value;
    if (from < 0 || to < 0 || (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      _dockT.value = to;
      _dockLive = false;
      return;
    }
    _dockFrom = from;
    _dockTo = to;
    _dockLive = true;
    _dockC.removeListener(_dockTick);
    _dockC.addListener(_dockTick);
    _dockC.forward(from: 0);
  }

  void _dockTick() => _dockT.value = _dockFrom + (_dockTo - _dockFrom) * Curves.easeOutCubic.transform(_dockC.value);

  /// A swipe in progress, on the page or on the island: [frac] is how far it has gone towards the next place (+1) or the
  /// previous one (-1). The island's pill and the page both follow it.
  void _scrubStart() {
    _swipeDx = 0;
    _slideC.stop();
    _dockC.stop();
    _dockLive = true;
  }

  void _scrub(double frac) {
    final at = _dockIdx(_i);
    if (at < 0) return;
    final to = (at + frac).clamp(0.0, 2.0);
    _dockT.value = to;
    final edge = at + frac < 0 || at + frac > 2;
    _slideX.value = -frac * MediaQuery.sizeOf(context).width * (edge ? .06 : .3);
  }

  void _scrubEnd(double frac, double velocity) {
    final at = _dockIdx(_i);
    if (at < 0) return;
    final dir = frac > 0 ? 1 : -1;
    final to = at + dir;
    // a flick (a third of a place and quick) or a long slow drag (half a place) counts
    final far = frac.abs() >= .5;
    final flick = frac.abs() >= .2 && velocity.abs() >= 250 && (velocity < 0) == (dir > 0);
    if ((!far && !flick) || to < 0 || to > 2) {
      _slideIn(_slideX.value);
      _dockGo(at);
      return;
    }
    _slideX.value = 0;
    _go(_order[to.toInt()]);
  }

  void _slideTick() => _slideX.value = _slideFrom * (1 - Curves.easeOutCubic.transform(_slideC.value));

  // The pages already opened: the others are not built until their first visit (a faster start, less memory), and once
  // opened they stay alive in the stack as before.
  late final Set<int> _opened = {_i};
  Widget _lazy(int k, Widget Function() page) => _opened.contains(k) ? page() : const SizedBox.shrink();

  void _go(int k) {
    _opened.add(k);
    const order = [_feed, _dir, _talk];
    final a = order.indexOf(_i), b = order.indexOf(k);
    if (a >= 0 && b >= 0 && a != b && _slideX.value == 0) {
      _slideIn((b > a ? 1 : -1) * MediaQuery.sizeOf(context).width * .28);
    }
    _dockGo(_dockIdx(k));
    if (k != _i) HapticFeedback.selectionClick();
    if (k == _i && k == _feed) {
      _topTick++; // tapping Home again scrolls the feed to the top
    }
    if (k == _notesTab) _notes.refresh(context.read<AuthProvider>());
    // tapping Find while it is open puts the cursor in its search box
    if (k == _dir && _i == _dir) directoryFocus.value++;
    setState(() {
      _i = k;
      _barHidden = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final w = MediaQuery.sizeOf(context).width;
    // as the website (AppShell): from 768 px the page floats as a raised 600 px sheet on a backdrop, the rail beside it
    // (icons, then with labels from 1280 px, where the right column joins), no top bar (the logo is the rail's)
    final wide = w >= 768;
    final labels = w >= 1280;
    const sheetW = 600.0;
    final side = wide ? (w - sheetW) / 2 : 0.0;
    final top = wide ? 0.0 : MediaQuery.of(context).padding.top;
    // exactly the header's own height (51 + the 1 px rule): any more leaves a bare strip between it and the page
    final header = wide ? 0.0 : 52.0;
    final bottom = MediaQuery.of(context).padding.bottom;
    final rail = wide;
    final backdrop = p.dark
        ? const Color(0xFF0B0B0B)
        : const HSLColor.fromAHSL(1, 43, .26, .93).toColor();
    // the bar steps aside while the keyboard is up, so what is typed has the room (the Directory's search)
    final bottomBar = !rail &&
        MediaQuery.viewInsetsOf(context).bottom == 0 &&
        !(_i == _dir && _dirSearch);
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
      },
      child: Scaffold(
        backgroundColor: wide ? backdrop : null,
        // stretch + expand: the page area is always the full width. With a loose width, a Stack whose only unpositioned child
        // is the empty banner host (SizedBox.shrink) sized itself 0 wide, and every page in it was laid out 0 wide: a blank screen
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const ActiveCallBanner(),
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              // pages, below the header; on wide screens the raised sheet in the middle
              Positioned(
                left: wide ? side : 0,
                right: wide ? side : 0,
                top: 0,
                bottom: 0,
                child: wide
                    ? Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: p.canvas,
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black
                                    .withValues(alpha: p.dark ? .6 : .14),
                                blurRadius: 32,
                                spreadRadius: -14,
                                offset: const Offset(0, 12))
                          ],
                        ),
                        child: Stack(children: [
                          Positioned.fill(
                              child: _pages(context, top, header, bottomBar,
                                  bottom, wide, sheetW)),
                        ]),
                      )
                    : _pages(
                        context, top, header, bottomBar, bottom, wide, sheetW),
              ),
              // header (status bar band + 56 px bar), always in view
              if (!wide)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _AppHeader(onHome: () => _go(_dir), compact: _scrolled),
                ),
              // "Waiting for network…" / "Connecting…" under the header, WhatsApp-style
              Positioned(
                  top: top + header + 8,
                  left: 0,
                  right: 0,
                  child: const ConnectionPill()),
              // a message or a new ask while the app is open: a banner with Reply (and Refer) right on it
              const NotifyBannerHost(),
              // the bar along the bottom, Contacts raised in the middle; Ask has its own Publish bar instead
              if (bottomBar)
                Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: _barH + bottom + _rise,
                    child: Stack(children: [_bar(p, bottom)])),
              // tablets and desktop: the rail down the left, under the header
              if (rail)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: side,
                  child: Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                          width: (labels ? 264.0 : 84.0).clamp(0.0, side),
                          child: _rail(p, labels))),
                ),
              // from 1280 px the column on the right, as on the website
              if (labels)
                Positioned(
                    left: side + sheetW,
                    top: 0,
                    bottom: 0,
                    width: side.clamp(0.0, 320.0),
                    child: _rightRail(p)),
            ]),
          ),
        ]),
      ),
    );
  }

  // the island shrinks to a short pill (icons only) while a page is scrolled down and grows back as soon as it is scrolled up (or a tab changes)
  bool _barHidden = false;
  // A real run of scrolling (24 px) one way is needed to change, nothing counts for 400 ms after a change (the shrinking
  // itself moves things), and the rubber band at either end is ignored: together they stop it bouncing.
  double _scrollRun = 0;
  DateTime _scrollQuiet = DateTime.fromMillisecondsSinceEpoch(0);

  void _setBarHidden(bool v) {
    _scrollRun = 0;
    _scrollQuiet = DateTime.now().add(const Duration(milliseconds: 400));
    if (_barHidden != v) setState(() => _barHidden = v);
  }

  // the header has no shadow at the top of a page and gets one once the page is scrolled (as on the web)
  bool _scrolled = false;

  bool _onPageScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical || n is! ScrollUpdateNotification) return false;
    final sc = n.metrics.pixels > 4;
    if (sc != _scrolled) setState(() => _scrolled = sc);
    final m = n.metrics;
    if (DateTime.now().isBefore(_scrollQuiet)) return false;
    if (m.pixels < 0 || m.pixels > m.maxScrollExtent) return false; // rubber band
    if (m.pixels <= 40) {
      if (_barHidden) _setBarHidden(false);
      return false;
    }
    final dy = n.scrollDelta ?? 0;
    _scrollRun = (dy.sign == _scrollRun.sign || _scrollRun == 0) ? _scrollRun + dy : dy;
    if (!_barHidden && _scrollRun > 24 && m.pixels > 120) {
      _setBarHidden(true);
    } else if (_barHidden && _scrollRun < -24) {
      _setBarHidden(false);
    }
    return false;
  }

  double _swipeDx = 0;

  /// On phones a swipe left or right changes tab (Refer, Find, Talk). Anything inside that scrolls sideways (an ask's
  /// cards, the circles, the chips and category rows) takes the swipe first, because the nearest drag wins; only a swipe
  /// that starts on plain page comes here.
  Widget _swipeTabs(bool phone, Widget child) {
    final at = _order.indexOf(_i);
    // The wrapper is always there, only its gestures come and go: a tree that changed shape when the keyboard opened (the bar
    // steps aside) or when the Directory began searching rebuilt every page from scratch, and the search lost its cursor,
    // its text and its keyboard on the spot.
    final on = phone && at >= 0 && !_dirSearch;
    final w = MediaQuery.sizeOf(context).width;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: !on ? null : (_) => _scrubStart(),
      onHorizontalDragUpdate: !on ? null : (d) {
        _swipeDx += d.delta.dx;
        _scrub((-_swipeDx / (w * .5)).clamp(-1.0, 1.0));
      },
      onHorizontalDragEnd: !on ? null : (d) => _scrubEnd((-_swipeDx / (w * .5)).clamp(-1.0, 1.0), d.primaryVelocity ?? 0),
      onHorizontalDragCancel: !on ? null : () => _scrubEnd(0, 0),
      child: ValueListenableBuilder<double>(
        valueListenable: _slideX,
        builder: (_, x, c) => Opacity(
          opacity: (1 - x.abs() / (MediaQuery.sizeOf(context).width * 1.2)).clamp(.4, 1.0),
          child: Transform.translate(offset: Offset(x, 0), child: c),
        ),
        child: child,
      ),
    );
  }

  /// The five pages, kept alive in an IndexedStack. On the raised sheet (wide screens) every page is the sheet's 600 px.
  Widget _pages(BuildContext context, double top, double header, bool bottomBar,
      double bottom, bool wide, double sheetW) {
    double m(double phone) => wide ? sheetW : phone;
    final pad = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.only(top: top + header),
      // the page runs to the bottom of the screen, behind the floating island; its lists pad their own ends by
      // islandSpace() so the last item can be scrolled clear of it
      child: NotificationListener<ScrollNotification>(
          onNotification: _onPageScroll,
          child: _swipeTabs(
          bottomBar,
          MediaQuery(
        data: MediaQuery.of(context).copyWith(
            padding: pad.copyWith(top: 0, bottom: bottomBar ? 0 : pad.bottom)),
        child: IndexedStack(index: _i, children: [
          _lazy(_feed, () => _fit(
              ConnectScreen(
                  refreshTick: _feedTick,
                  topTick: _topTick,
                  active: _i == _feed),
              m(680))),
          _lazy(1, () => _fit(const FindScreen(), m(900))),
          _lazy(_dir, () => _fit(
              PhonebookHome(
                  active: _i == _dir,
                  onAsk: () => _go(_feed),
                  onSeeAsks: () => _go(_feed),
                  onPosted: () => setState(() => _feedTick++),
                  onSearching: (on) => setState(() => _dirSearch = on)),
              m(1240))),
          // Talk loads afresh each time it opens
          if (_i == _talk)
            _fit(const TalkScreen(), m(900))
          else
            const SizedBox.shrink(),
          _lazy(_notesTab, () => _fit(_NotesPanel(notes: _notes, page: true, onAsk: () => _go(_feed)),
              m(760))),
        ]),
      ))),
    );
  }

  /// Wide screens (1280 px and up), as the website's right column: a search, the ask prompt and the shortcuts.
  Widget _rightRail(Pal p) {
    final me = context.watch<AuthProvider>().profile;
    BoxDecoration card() => BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x141E1E1E),
                  blurRadius: 18,
                  offset: Offset(0, 6))
            ]);
    void sub(String title, Widget body) => Navigator.push(context,
        WideRoute(builder: (_) => SubPage(title: t(title), body: body)));
    final links = <(String, VoidCallback)>[
      if (me != null)
        (
          'Your public page',
          () => Navigator.push(context,
              WideRoute(builder: (_) => ProfileScreen(handle: me.handle)))
        ),
      if (me != null && me.isEntrepreneur) ...[
        ('Leads for you', () => sub('Leads for you', const LeadsScreen())),
        ('Today in your area', () => sub('Today in your area', const TodayScreen())),
      ],
      if (me != null) ('30-second intro card', () => Navigator.push(context, WideRoute(builder: (_) => const IntroCardScreen()))),
      if (me != null)
        (
          'Edit profile',
          () => Navigator.push(context,
              WideRoute(builder: (_) => EditProfileScreen(profile: me)))
        ),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 14, 0, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // the Directory's search, always: the AI badge, the four SkyQ colours, the microphone and where to look
        DirectoryRailSearch(onOpen: () => _go(_dir)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: card(),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              WIcon(WI.ask, size: 20, color: p.text),
              const SizedBox(width: 8),
              Text(t('Need something?'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700))
            ]),
            const SizedBox(height: 4),
            Text(t('Post an ask and reach members across Navi Mumbai.'),
                style: TextStyle(fontSize: 13.5, height: 1.35, color: p.muted)),
            const SizedBox(height: 14),
            InkWell(
              onTap: () => _go(_feed),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    gradient: kGoldGradient,
                    borderRadius: BorderRadius.circular(20)),
                child: Text(t('Post an ask'),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: kInk)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: card(),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: Text(t('Shortcuts').toUpperCase(),
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .6,
                        color: p.muted))),
            for (final l in links)
              InkWell(
                onTap: l.$2,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    child: Text(t(l.$1),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700))),
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
          child: SizedBox(
              width: w,
              height: c.maxHeight,
              child: MediaQuery(
                  data: mq.copyWith(size: Size(w, mq.size.height)),
                  child: page)),
        );
      });

  /// The island: a floating dock of three places. The open place is a gold pill with its icon and name; the others are
  /// icons. Its size never changes with scrolling.
  Widget _bar(Pal p, double bottom) {
    final bb = bottom > 8 ? bottom - 4 : 8.0;
    return Positioned.fill(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, bb),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Container(
              height: _barH,
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: p.canvas.withValues(alpha: p.dark ? .96 : .97),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: p.dark ? Colors.white.withValues(alpha: .1) : Colors.black.withValues(alpha: .06)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: p.dark ? .5 : .16), blurRadius: 26, spreadRadius: -6, offset: const Offset(0, 10))],
              ),
              // swiping along the island changes the page too, the open pill following the finger
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: (_) => _scrubStart(),
                onHorizontalDragUpdate: (d) {
                  _swipeDx += d.delta.dx;
                  _scrub((-_swipeDx / 100).clamp(-1.0, 1.0));
                },
                onHorizontalDragEnd: (d) => _scrubEnd((-_swipeDx / 100).clamp(-1.0, 1.0), d.primaryVelocity ?? 0),
                onHorizontalDragCancel: () => _scrubEnd(0, 0),
                child: ValueListenableBuilder<double>(
                  valueListenable: _dockT,
                  builder: (_, live, __) {
                    final t = _dockLive ? live : _dockIdx(_i);
                    return Row(children: [
                      for (final k in _order)
                        Expanded(
                          // the open place is 5 parts wide, the others 3, and the width glides between them
                          flex: (3000 + 2000 * (1 - (t - _order.indexOf(k)).abs()).clamp(0.0, 1.0)).round(),
                          child: KeyedSubtree(key: Tours.key(_tourKeys[k]), child: _dockItem(p, k, (t - _order.indexOf(k)).abs() < .5, badge: _badgeOf(k))),
                        ),
                    ]);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dockItem(Pal p, int k, bool active, {int badge = 0}) {
    final dir = k == _dir;
    // none of the three places is open (a post, a profile, Notifications...): Find glows softly, as the way back
    final soft = dir && !active && ![_feed, _dir, _talk].contains(_i);
    final label = t(_items[k].$2);
    final ink = p.dark ? const Color(0xFFFFD84A) : const Color(0xFF3D3500);
    final iconColor = active ? ink : (soft ? (p.dark ? const Color(0xFFFFD84A) : const Color(0xFF7A5A00)) : p.muted);
    final icon = WIcon(_items[k].$1, size: 24, color: iconColor, strokeWidth: active ? 2.2 : 1.8);
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // on the Find page a tap puts the cursor back in the search
        onTap: () => _i == k && dir ? directoryFocus.value++ : _go(k),
        child: ExcludeSemantics(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: soft ? const Color(0xFFFFC700).withValues(alpha: p.dark ? .1 : .15) : null,
              gradient: active ? (p.dark ? const LinearGradient(colors: [Color(0xFF34322B), Color(0xFF1E1E1E)], begin: Alignment.topCenter, end: Alignment.bottomCenter) : _logoGradient) : null,
              borderRadius: BorderRadius.circular(26),
              border: active && p.dark ? Border.all(color: const Color(0xFFFFC700).withValues(alpha: .6)) : (soft ? Border.all(color: const Color(0xFFFFC700).withValues(alpha: .35)) : null),
              boxShadow: active && !p.dark
                  ? [BoxShadow(color: const Color(0xFFE0A800).withValues(alpha: .35), blurRadius: 12, spreadRadius: -3, offset: const Offset(0, 4))]
                  : (soft ? [BoxShadow(color: const Color(0xFFFFC700).withValues(alpha: .3), blurRadius: 16, spreadRadius: -2)] : null),
            ),
            child: Center(
              child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    icon,
                    if (active) ...[
                      const SizedBox(width: 7),
                      Text(label, maxLines: 1, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: ink)),
                      const SizedBox(width: 4),
                    ],
                  ]),
                ),
                if (badge > 0 && !active) Positioned(right: -12, top: -10, child: _badge(badge)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  /// unread chats on Talk, unseen responses on Notifications
  int _badgeOf(int k) =>
      k == _talk ? unreadChats.value : (k == _notesTab ? _notes.unseen : 0);

  Widget _badge(int n) => Container(
        height: 16,
        constraints: const BoxConstraints(minWidth: 16),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
            gradient: kGoldGradient, borderRadius: BorderRadius.circular(8)),
        child: Text(n > 99 ? '99+' : '$n',
            style: const TextStyle(
                color: kInk,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                height: 1)),
      );

  /// Tablets and desktop, as the website's side dock: the logo on top, the three places (Directory keeps its gold), and
  /// the account at the foot. [labels]: from 1280 px each label beside its icon.
  Widget _rail(Pal p, bool labels) {
    final tone = p.dark ? const Color(0xFFFFD84A) : const Color(0xFF7A5A00);
    final me = context.watch<AuthProvider>().profile;
    Widget item(int k) {
      final active = _i == k;
      final home = k == _dir;
      final badge = _badgeOf(k);
      final icon = Stack(clipBehavior: Clip.none, children: [
        WIcon(_items[k].$1,
            size: 22,
            color: home ? const Color(0xFF2E2A00) : (active ? tone : p.text),
            strokeWidth: home ? 2.1 : (active ? 2 : 1.5)),
        if (badge > 0) Positioned(right: -10, top: -6, child: _badge(badge)),
      ]);
      final style = TextStyle(
          fontSize: labels ? 15 : 10.5,
          fontWeight: active || home ? FontWeight.w600 : FontWeight.w400,
          color: home ? kInk : (active ? tone : p.text),
          height: 1);
      return KeyedSubtree(
        key: Tours.key(_tourKeys[k]),
        child: Semantics(
          button: true,
          selected: active,
          label: t(_items[k].$2),
          child: InkWell(
            onTap: () => _go(k),
            borderRadius: BorderRadius.circular(labels ? 26 : 16),
            child: ExcludeSemantics(
              child: labels
                  ? Container(
                      height: 50,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: home
                            ? null
                            : (active ? p.canvas : Colors.transparent),
                        gradient: home ? _logoGradient : null,
                        borderRadius: BorderRadius.circular(26),
                        border: active
                            ? Border.all(
                                color:
                                    home ? kInk.withValues(alpha: .5) : kGold,
                                width: 1.5)
                            : null,
                      ),
                      child: Row(children: [
                        icon,
                        const SizedBox(width: 16),
                        Expanded(
                            child: Text(t(_items[k].$2),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: style))
                      ]),
                    )
                  : Container(
                      width: 64,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: home
                            ? null
                            : (active
                                ? kGold.withValues(alpha: p.dark ? .25 : .22)
                                : Colors.transparent),
                        gradient: home ? _logoGradient : null,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        icon,
                        const SizedBox(height: 5),
                        Text(t(_items[k].$2),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: style)
                      ]),
                    ),
            ),
          ),
        ),
      );
    }

    final account = me == null
        ? const SizedBox.shrink()
        : Builder(
            builder: (ctx) => InkWell(
              onTap: () => _openAccountMenu(ctx),
              borderRadius: BorderRadius.circular(labels ? 28 : 16),
              child: Padding(
                padding: labels
                    ? const EdgeInsets.fromLTRB(10, 8, 12, 8)
                    : const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                child: labels
                    ? Row(children: [
                        Avatar(
                            name: me.name,
                            photoUrl: me.photoUrl,
                            size: 40,
                            ring: me.hasUpdate,
                            framed: true,
                            progress: context.watch<AuthProvider>().completion?.percent,
                            type: me.userType,
                            badge: 16),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(me.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        height: 1.2)),
                                Text('@${me.handle}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: p.muted,
                                        height: 1.3)),
                              ]),
                        ),
                        Text('···', style: TextStyle(color: p.muted)),
                      ])
                    : Column(mainAxisSize: MainAxisSize.min, children: [
                        Avatar(
                            name: me.name,
                            photoUrl: me.photoUrl,
                            size: 40,
                            ring: me.hasUpdate,
                            framed: true,
                            progress: context.watch<AuthProvider>().completion?.percent,
                            type: me.userType,
                            badge: 16),
                        const SizedBox(height: 4),
                        Text('@${me.handle}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 9.5, color: p.muted, height: 1)),
                      ]),
              ),
            ),
          );

    return Padding(
      padding: EdgeInsets.fromLTRB(labels ? 8 : 10, 12, labels ? 16 : 10, 12),
      child: Column(
          crossAxisAlignment:
              labels ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
          children: [
            // the logo, as the web dock's: the whole lockup with its slogan, or just the mark on the narrow dock
            Padding(
              padding:
                  EdgeInsets.fromLTRB(labels ? 10 : 0, 0, 0, labels ? 20 : 16),
              child: labels
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: LogoInline(
                          size: 30,
                          markSize: 44,
                          tagline: true,
                          onTap: () => _go(_dir)))
                  : GestureDetector(
                      onTap: () => _go(_dir),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        // the mark with a soft halo behind it, WEBWEB and the AI pill under it, a fine gold line below: the website's narrow dock
                        Stack(
                            alignment: Alignment.center,
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                            color: const Color(0xFFFFC700)
                                                .withValues(alpha: .35),
                                            blurRadius: 22,
                                            spreadRadius: 6)
                                      ])),
                              const LogoMark(size: 46),
                            ]),
                        const SizedBox(height: 8),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('WEB',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  height: 1,
                                  color: p.text)),
                          ShaderMask(
                            blendMode: BlendMode.srcIn,
                            shaderCallback: (r) => (p.dark
                                    ? const LinearGradient(colors: [
                                        Color(0xFFFFD84A),
                                        Color(0xFFE0AD00)
                                      ])
                                    : const LinearGradient(colors: [
                                        Color(0xFFA89A2C),
                                        Color(0xFFC9AE24),
                                        Color(0xFFE8C722)
                                      ]))
                                .createShader(r),
                            child: const Text('WEB',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    height: 1,
                                    color: Colors.white)),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        const AiPill(font: 8),
                        const SizedBox(height: 8),
                        Container(
                            width: 32,
                            height: 1,
                            decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [
                              Colors.transparent,
                              const Color(0xFFFFC700).withValues(alpha: .7),
                              Colors.transparent
                            ]))),
                      ]),
                    ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: labels
                        ? CrossAxisAlignment.stretch
                        : CrossAxisAlignment.center,
                    children: [
                      // Find first, in gold, then Refer and Talk (on the phone it stays in the middle of the bar)
                      for (final k in [_dir, _feed, _talk])
                        Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: item(k)),
                    ]),
              ),
            ),
            account,
          ]),
    );
  }
}

// ======================= header =======================

class _AppHeader extends StatelessWidget {
  final VoidCallback onHome;
  // the page is scrolled: the header gets its shadow (it never changes size)
  final bool compact;
  const _AppHeader({required this.onHome, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final me = context.watch<AuthProvider>().profile;
    final top = MediaQuery.of(context).padding.top;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: compact ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, c, _) => _bar(context, p, me, top, c),
    );
  }

  Widget _bar(BuildContext context, Pal p, dynamic me, double top, double c) {
    return Container(
      padding: EdgeInsets.only(top: top),
      // the page's own colour with a soft shadow and a thin gold rule at the foot, so the header belongs to the page
      // instead of sitting on it as a grey bar
      decoration: BoxDecoration(
        color: p.canvas,
        // no shadow under the header: nothing grey falls on the page
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: 51,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            // with the SMART PHONEBOOK slogan, as on the web; shrinks rather than crowd the avatar on the narrowest phones
            // (notifications are a tab of the bar now)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 4, right: 8),
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: LogoInline(
                        size: 30, markSize: 40, tagline: true, onTap: onHome)),
              ),
            ),
            Builder(
              builder: (ctx) => GestureDetector(
                onTap: () => _openAccountMenu(ctx),
                child: Semantics(
                  button: true,
                  label: t('Account menu'),
                  child: Avatar(
                      key: Tours.key('account'),
                      name: me?.name ?? 'Me',
                      photoUrl: me?.photoUrl,
                      size: 32,
                      ring: me?.hasUpdate ?? false,
                      framed: true,
                      progress: context.watch<AuthProvider>().completion?.percent,
                      type: me?.userType,
                      badge: 14),
                ),
              ),
            ),
          ]),
        ),
      ),
      Container(
        height: 1,
        decoration: BoxDecoration(gradient: LinearGradient(colors: [kGold.withValues(alpha: 0), kGold.withValues(alpha: .55), kGold.withValues(alpha: 0)])),
      ),
      ]),
    );
  }
}

BoxDecoration _panelDecoration(Pal p, {double radius = 14}) => BoxDecoration(
      color: p.canvas,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: p.border.withValues(alpha: .6)),
      boxShadow: [
        BoxShadow(
            color: const Color(0xFF1E1E1E).withValues(alpha: .06),
            blurRadius: 2,
            offset: const Offset(0, 1)),
        BoxShadow(
            color: (p.dark ? const Color(0xFF1E1E1E) : const Color(0xFF1E1E1E))
                .withValues(alpha: p.dark ? .7 : .35),
            blurRadius: 40,
            spreadRadius: -12,
            offset: const Offset(0, 18)),
      ],
    );

void _openAccountMenu(BuildContext context) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0x8014120C),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) =>
        const Align(alignment: Alignment.centerRight, child: _AccountMenu()),
    transitionBuilder: (_, a, __, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
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
      final auth = context.read<AuthProvider>();
      await auth.switchAccount(uid, from: auth.userId);
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
                Avatar(
                    name: '${a['name'] ?? ''}',
                    photoUrl: a['photoURL'] as String?,
                    size: 32,
                    type: a['userType'] as String?),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            ('${a['company'] ?? ''}').isNotEmpty
                                ? '${a['company']}'
                                : (('${a['name'] ?? ''}').isNotEmpty
                                    ? '${a['name']}'
                                    : t('New business page')),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w500)),
                        Text(
                            a['handle'] != null
                                ? '@${a['handle']}'
                                : t('Set up this page'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: p.muted)),
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
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: p.border)),
                  child: Text('+',
                      style:
                          TextStyle(fontSize: 18, height: 1, color: p.muted)),
                ),
                const SizedBox(width: 12),
                Text(t('Add a business page'),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
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
      nav.push(WideRoute(builder: (_) => page));
    }

    // compact rows (32 icon box, 42 a row) so the whole menu fits on a phone without scrolling
    Widget iconBox(WI icon, {Color? bg, Color? fg}) => Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: bg ?? p.chip, borderRadius: BorderRadius.circular(9)),
          child: WIcon(icon, size: 17, color: fg ?? p.muted, strokeWidth: 1.8),
        );
    Widget row(WI icon, Widget label, VoidCallback? onTap,
            {Color? bg, Color? fg, Widget? trailing}) =>
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(children: [
              iconBox(icon, bg: bg, fg: fg),
              const SizedBox(width: 12),
              Expanded(child: label),
              if (trailing != null) trailing
            ]),
          ),
        );
    Text label(String s, {Color? color}) => Text(s,
        style:
            TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: color));
    Widget item(WI icon, String text, VoidCallback onTap) =>
        row(icon, label(t(text)), onTap);
    final divider = Divider(height: 1, color: p.border.withValues(alpha: .6));

    // the drawer's ⋯ (Log out) and close sit on the account card: one section, no title bar above it
    final Widget actions = Row(mainAxisSize: MainAxisSize.min, children: [
      PopupMenuButton<String>(
        tooltip: t('More options'),
        icon: WIcon(WI.more, size: 22, color: p.text),
        color: p.canvas,
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: p.border.withValues(alpha: .6))),
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
              Text(t('Log out'),
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: p.danger)),
            ]),
          ),
        ],
      ),
      IconButton(
          tooltip: t('Close'),
          onPressed: () => Navigator.of(context).pop(),
          icon: WIcon(WI.close, size: 22, color: p.text)),
    ]);

    return Material(
      color: p.canvas,
      elevation: 16,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: (mq.size.width * .88).clamp(0, 380).toDouble(),
        height: mq.size.height,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(height: mq.padding.top),
          // account card: this page, then the other pages of the sign-in and Add, as one block
          Container(
            decoration: BoxDecoration(
                color: p.chip.withValues(alpha: .5),
                border: Border(
                    top: BorderSide(color: p.border.withValues(alpha: .6)),
                    bottom: BorderSide(color: p.border.withValues(alpha: .6)))),
            child: Stack(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                InkWell(
                  onTap: () => push(const ProfileScreen()),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 96, 12),
                    child: Row(children: [
                      Avatar(
                          name: me.name,
                          photoUrl: me.photoUrl,
                          size: 48,
                          ring: me.hasUpdate,
                          type: me.userType,
                          badge: 18,
                          uid: me.uid),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(me.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text('@${me.handle}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      TextStyle(fontSize: 13, color: p.muted)),
                              const SizedBox(height: 4),
                              Row(children: [
                                VerifiedBadge(
                                    level: me.verification,
                                    premium: me.premium,
                                    plan: me.plan,
                                    size: 14),
                                const SizedBox(width: 4),
                                Flexible(
                                    child: Text(
                                        t(kVerificationLabel[me.verification] ??
                                            ''),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: p.muted))),
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
              item(WI.edit, 'Edit profile',
                  () => push(EditProfileScreen(profile: me))),
              item(WI.contactCard, '30-second intro card',
                  () => push(const IntroCardScreen())),
              // for businesses only: a consumer is not shown them
              if (me.isEntrepreneur) ...[
                item(WI.sparkle, 'Leads for you',
                    () => push(SubPage(title: t('Leads for you'), body: const LeadsScreen()))),
                item(WI.sun, 'Today in your area',
                    () => push(SubPage(title: t('Today in your area'), body: const TodayScreen()))),
              ],
              // help articles, writing to us, the assistant and the tour: one sheet
              item(WI.help, 'Help & Support', () {
                Navigator.of(context).pop();
                _openHelp(context);
              }),
              const SizedBox(height: 4),
              divider,
              const SizedBox(height: 4),
              // two-step verification, blocked people, sign out everywhere, delete account: a tab of Edit profile
              item(WI.lock, 'Account and privacy',
                  () => push(EditProfileScreen(profile: me, tab: 'account'))),
              if (ContactSync.supported) const _ServiceContactsRow(),
            ]),
          ),
          divider,
          Padding(
            padding: EdgeInsets.fromLTRB(8, 4, 8, 4 + mq.padding.bottom),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                    color: p.border.withValues(alpha: .6))),
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
                                    Text(l.native,
                                        style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: i18n.lang == l.code
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color: p.text)),
                                    if (l.native != l.name) ...[
                                      const SizedBox(width: 8),
                                      Text(l.name,
                                          style: TextStyle(
                                              fontSize: 12, color: p.muted)),
                                    ],
                                    const Spacer(),
                                    if (i18n.lang == l.code)
                                      const WIcon(WI.check,
                                          size: 18,
                                          color: kGold,
                                          strokeWidth: 2.4),
                                  ]),
                                ),
                            ],
                            child: Container(
                              height: 40,
                              padding:
                                  const EdgeInsets.only(left: 12, right: 10),
                              decoration: BoxDecoration(
                                  color: p.chip,
                                  borderRadius: BorderRadius.circular(20)),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    WIcon(WI.globe,
                                        size: 18,
                                        color: p.muted,
                                        strokeWidth: 1.8),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        kLangs
                                            .firstWhere(
                                                (l) => l.code == i18n.lang,
                                                orElse: () => kLangs.first)
                                            .native,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: p.text),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    WIcon(WI.chevronUp,
                                        size: 16,
                                        color: p.muted,
                                        strokeWidth: 2),
                                  ]),
                            ),
                          ),
                        ),
                      ),
                      // theme: follow the device (the default), light or dark
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                            color: p.chip,
                            borderRadius: BorderRadius.circular(20)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          for (final o in [
                            (ThemeMode.system, WI.monitor, 'Device theme'),
                            (ThemeMode.light, WI.sun, 'Light'),
                            (ThemeMode.dark, WI.moon, 'Dark')
                          ])
                            Semantics(
                              button: true,
                              selected: themeCtl.mode == o.$1,
                              label: t(o.$3),
                              child: GestureDetector(
                                onTap: () => themeCtl.set(o.$1),
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                      color: themeCtl.mode == o.$1
                                          ? p.card
                                          : Colors.transparent,
                                      shape: BoxShape.circle),
                                  child: Center(
                                      child: WIcon(o.$2,
                                          size: 18,
                                          color: themeCtl.mode == o.$1
                                              ? p.text
                                              : p.muted,
                                          strokeWidth: 1.8)),
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
            title: Text(t(label),
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
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
              final from = defaultTargetPlatform == TargetPlatform.iOS
                  ? 'ios'
                  : 'android';
              launchUrl(Uri.parse('$siteUrl/help?lang=$lang&from=$from'),
                  mode: LaunchMode.externalApplication);
            }),
            row(WI.talk, 'Write to us', () => showSupportSheet(nav.context)),
            // @webwebai: the assistant answers in a chat
            row(WI.sparkle, 'Ask WebWeb AI', () async {
              try {
                final u = Profile.fromJson(
                    await auth.api.get('/users/handle/webwebai') as Map);
                final ctx = nav.context;
                if (ctx.mounted) openChat(ctx, Peer.fromProfile(u));
              } catch (_) {}
            }),
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
          i == null
              ? ' '
              : '${t('WebWeb AI')} · ${t('Version {v}', {
                      'v': i.version
                    })}${i.buildNumber.isEmpty ? '' : ' (${i.buildNumber})'}',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 12,
              color: p.muted,
              fontFeatures: const [FontFeature.tabularFigures()]),
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
    final changed = _on!
        ? await turnOffServiceContacts(context)
        : await showServiceContactsSheet(context) == true;
    if (changed && mounted) setState(() => _on = !_on!);
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final on = _on == true;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _toggleRow(p, on),
      // also while it is off: contacts already shared stay until the member removes them one by one
      ...[
        InkWell(
          onTap: () => Navigator.of(context)
              .push(WideRoute(builder: (_) => const SharedContactsScreen())),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(56, 4, 12, 9),
            child: Row(children: [
              Expanded(
                  child: Text(t('Contacts you share'),
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: p.link))),
              Icon(Icons.chevron_right, size: 18, color: p.muted),
            ]),
          ),
        ),
      ],
    ]);
  }

  Widget _toggleRow(Pal p, bool on) {
    return InkWell(
      onTap: _toggle,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: p.chip, borderRadius: BorderRadius.circular(10)),
            child: WIcon(WI.contactCard,
                size: 18, color: p.muted, strokeWidth: 1.8),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('Service contacts'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500)),
              Text(t('Share plumbers, electricians, cabs…'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.muted)),
            ]),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 44,
            height: 24,
            padding: const EdgeInsets.all(3),
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(
                color: on ? kGold : p.border,
                borderRadius: BorderRadius.circular(12)),
            child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Color(0x331E1E1E), blurRadius: 2)
                    ])),
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
  AppNote(
      {required this.id,
      required this.kind,
      required this.postId,
      required this.postTitle,
      required this.postPath,
      required this.unseen,
      required this.createdAt,
      required this.sharer});
  factory AppNote.fromJson(Map j) => AppNote(
        id: '${j['id']}',
        kind: '${j['kind']}',
        postId: '${j['postId']}',
        postTitle: '${j['postTitle'] ?? ''}',
        postPath: '${j['postPath'] ?? ''}',
        unseen: j['unseen'] == true,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (j['createdAt'] as num?)?.toInt() ?? 0),
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
      items = ((d['items'] as List?) ?? const [])
          .map((e) => AppNote.fromJson(e as Map))
          .toList();
      loaded = true;
      notifyListeners();
    } catch (_) {}
  }

  /// Badges clear at once, then the server confirms.
  Future<void> markSeen(AuthProvider auth) async {
    if (unseen == 0 && items.every((i) => !i.unseen)) return;
    unseen = 0;
    items = [
      for (final i in items)
        AppNote(
            id: i.id,
            kind: i.kind,
            postId: i.postId,
            postTitle: i.postTitle,
            postPath: i.postPath,
            unseen: false,
            createdAt: i.createdAt,
            sharer: i.sharer)
    ];
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

  static const _verb = {
    'contact': 'shared a contact on',
    'media': 'shared a photo on',
    'info': 'shared a note on',
    'referral': 'referred a contact on'
  };

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
          final shown = n.items
              .where((i) =>
                  _filter == 'all' ||
                  (_filter == 'unread' ? i.unseen : !i.unseen))
              .toList();
          return Container(
            decoration: widget.page
                ? BoxDecoration(color: p.canvas)
                : _panelDecoration(p, radius: 16),
            clipBehavior: Clip.antiAlias,
            child: Column(
                mainAxisSize: widget.page ? MainAxisSize.max : MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.page)
                    ..._pageHead(p, n, auth)
                  else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: p.border))),
                      child: Row(children: [
                        Expanded(
                            child: Text(t('Notifications'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15))),
                        if (n.unseen > 0)
                          GestureDetector(
                            onTap: () => n.markSeen(auth),
                            child: Text(t('Mark all as read'),
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: p.link)),
                          ),
                      ]),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: p.border))),
                      child: Row(children: [
                        for (final f in const ['all', 'unread', 'read']) ...[
                          GestureDetector(
                            onTap: () => setState(() => _filter = f),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                  color:
                                      _filter == f ? p.ink : Colors.transparent,
                                  borderRadius: BorderRadius.circular(20)),
                              child: Text(
                                '${t(f == 'all' ? 'All' : f == 'unread' ? 'Unread' : 'Read')}${f == 'unread' && n.unseen > 0 ? ' ${n.unseen > 9 ? '9+' : n.unseen}' : ''}',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _filter == f ? p.onInk : p.muted),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                          color: p.chip.withValues(alpha: .6),
                          border: Border(bottom: BorderSide(color: p.border))),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t('Get alerts on this device'),
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700)),
                                Text(t('New messages, calls and responses, even when the app is closed.'),
                                    style: TextStyle(
                                        fontSize: 12, color: p.muted)),
                              ]),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () async {
                            final on = await context
                                .read<NotificationService>()
                                .enableAlerts();
                            if (mounted) setState(() => _alertsOn = on);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                                gradient: kGoldGradient,
                                borderRadius: BorderRadius.circular(20)),
                            child: Text(t('Turn on'),
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: kInk)),
                          ),
                        ),
                      ]),
                    ),
                  _bound(
                    context,
                    child: !n.loaded
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: LogoLoader(size: 28)))
                        : n.items.isEmpty
                            ? (widget.page
                                ? _emptyPage(p)
                                : _empty(
                                    p,
                                    t(
                                        'No responses yet. When members share a contact on your Ask, it shows up here.')))
                            : shown.isEmpty
                                ? _empty(
                                    p,
                                    t(_filter == 'unread'
                                        ? "You're all caught up."
                                        : 'Nothing read yet.'))
                                : ListView.builder(
                                    shrinkWrap: !widget.page,
                                    padding: EdgeInsets.only(
                                        bottom: widget.page ? islandSpace(context) : 0),
                                    itemCount: shown.length,
                                    itemBuilder: (_, i) {
                                      final x = shown[i];
                                      final who = x.sharer.shownName;
                                      return InkWell(
                                        onTap: () {
                                          n.markSeen(auth);
                                          final nav = Navigator.of(context);
                                          if (!widget.page) nav.pop();
                                          nav.push(WideRoute(
                                              builder: (_) => PostDetailScreen(
                                                  postId: x.postId)));
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 12),
                                          decoration: BoxDecoration(
                                            color: x.unseen
                                                ? kGold.withValues(alpha: .1)
                                                : null,
                                            border: i == shown.length - 1
                                                ? null
                                                : Border(
                                                    bottom: BorderSide(
                                                        color: p.border)),
                                          ),
                                          child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Avatar(
                                                    name: who,
                                                    photoUrl: x.sharer.photoUrl,
                                                    size: 36,
                                                    type: x.sharer.userType,
                                                    badge: 14,
                                                    uid: x.sharer.uid),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text.rich(
                                                          TextSpan(children: [
                                                            TextSpan(
                                                                text: who,
                                                                style: const TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700)),
                                                            TextSpan(
                                                                text:
                                                                    ' ${t(_verb[x.kind] ?? 'responded on')} '),
                                                            TextSpan(
                                                                text:
                                                                    '“${x.postTitle}”',
                                                                style: const TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600)),
                                                          ]),
                                                          style:
                                                              const TextStyle(
                                                                  fontSize: 14,
                                                                  height: 1.35),
                                                        ),
                                                        const SizedBox(
                                                            height: 2),
                                                        Text(
                                                            timeAgo(
                                                                x.createdAt),
                                                            style: TextStyle(
                                                                fontSize: 12,
                                                                color:
                                                                    p.muted)),
                                                      ]),
                                                ),
                                                if (x.unseen)
                                                  Container(
                                                      margin:
                                                          const EdgeInsets.only(
                                                              top: 6, left: 6),
                                                      width: 8,
                                                      height: 8,
                                                      decoration:
                                                          const BoxDecoration(
                                                              color: Color(
                                                                  0xFFE6AC00),
                                                              shape: BoxShape
                                                                  .circle)),
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
  Widget _bound(BuildContext context, {required Widget child}) => widget.page
      ? Expanded(child: child)
      : ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * .62),
          child: child);

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
          decoration: BoxDecoration(
              gradient: on ? kGoldGradient : null,
              color: on ? null : p.chip,
              borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(t(label),
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: on ? kInk : p.muted)),
            if (f == 'unread' && n.unseen > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                    color: kInk, borderRadius: BorderRadius.circular(10)),
                child: Text(n.unseen > 99 ? '99+' : '${n.unseen}',
                    style: const TextStyle(
                        fontSize: 11,
                        height: 16 / 11,
                        fontWeight: FontWeight.w700,
                        color: kGold)),
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
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('Notifications'),
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w700, height: 1)),
              const SizedBox(height: 4),
              Text(
                  n.unseen > 0
                      ? '${n.unseen} ${t('unread')}'
                      : t("You're all caught up"),
                  style: TextStyle(fontSize: 14, color: p.muted)),
            ]),
          ),
          if (n.unseen > 0)
            TextButton(
                onPressed: () => n.markSeen(auth),
                child: Text(t('Mark all as read'),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700))),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(children: [
          chip('all', 'All'),
          const SizedBox(width: 8),
          chip('unread', 'Unread'),
          const SizedBox(width: 8),
          chip('read', 'Read')
        ]),
      ),
    ];
  }

  /// The empty tab: what will show here, and the way to get some
  Widget _emptyPage(Pal p) =>
      ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, islandSpace(context)), children: [
        DashedBox(
          radius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(children: [
            Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration:
                    BoxDecoration(color: p.tagBg, shape: BoxShape.circle),
                child: WIcon(WI.bell, size: 28, color: p.tagText)),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                  t('No responses yet. When members share a contact on your Ask, it shows up here.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14.5, height: 1.4, color: p.muted)),
            ),
            if (widget.onAsk != null) ...[
              const SizedBox(height: 18),
              GoldButton(
                  label: t('Post an ask'),
                  wi: WI.askPlus,
                  height: 44,
                  onPressed: widget.onAsk),
            ],
          ]),
        ),
      ]);

  Widget _empty(Pal p, String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: p.muted)),
      );
}

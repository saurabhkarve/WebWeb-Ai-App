import 'dart:ui' show ImageFilter;
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

/// Signed-in chrome, same as the web on phones (app-frame.tsx): the slim header (logo, bell, your
/// avatar with the account menu) and the floating island with Connect, Find, Talk and Ask.
/// The header always stays in view (the web hides it on scroll only on small screens).
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int _i = 0;
  int _feedTick = 0; // reload the feed
  int _topTick = 0; // scroll the feed to the top
  int _askSpin = 0;
  StreamSubscription? _sub, _pushSub;
  Timer? _poll, _svcTimer;
  final _notes = NotificationsModel();

  // Home -> Find -> Ask (create, in the middle of the island) -> Notifications -> Talk, as on the web phone menu
  static const _items = [(WI.home, 'Home'), (WI.search, 'Find'), (WI.connect, 'Ask'), (WI.bell, 'Notifications'), (WI.talk, 'Talk')];
  static const _ask = 2, _notesTab = 3, _talk = 4;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unreadChats.addListener(_unreadChanged);
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
    _sub?.cancel();
    _pushSub?.cancel();
    _poll?.cancel();
    _svcTimer?.cancel();
    tourRequest.removeListener(_replayTour);
    _notes.dispose();
    super.dispose();
  }

  /// "Take the app tour" from the account menu: back to the top of Connect, then the tour.
  void _replayTour() {
    if (!mounted) return;
    setState(() {
      _i = 0;
      _topTick++;
    });
    Tours.start(context, kConnectTourId, kConnectTour);
  }

  void _go(int k) {
    if (k == _ask) _askSpin++;
    if (k == _notesTab) _notes.refresh(context.read<AuthProvider>());
    if (k == _i && k == 0) _topTick++; // tapping Home again scrolls the feed to the top
    setState(() => _i = k);
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final top = MediaQuery.of(context).padding.top;
    const header = 56.0;
    // without the island on Ask, back returns to Home
    return PopScope(
      canPop: _i != _ask,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _i == _ask) _go(0);
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
                padding: EdgeInsets.only(top: top + header),
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: IndexedStack(index: _i, children: [
                    ConnectScreen(refreshTick: _feedTick, topTick: _topTick, onGoAsk: () => _go(_ask)),
                    const FindScreen(),
                    AskScreen(active: _i == _ask, onBack: () => _go(0), onPosted: () => setState(() {
                          _feedTick++;
                          _i = 0;
                        })),
                    _NotesPanel(notes: _notes, page: true),
                    if (_i == _talk) const TalkScreen() else const SizedBox.shrink(), // reload conversations each time it opens
                  ]),
                ),
              ),
            ),
            // header (status bar band + 56 px bar), always in view
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _AppHeader(
                notes: _notes,
                onHome: () => _go(0),
              ),
            ),
            // "Waiting for network…" / "Connecting…" under the header, WhatsApp-style
            Positioned(top: top + header + 8, left: 0, right: 0, child: const ConnectionPill()),
            // a message or a new ask while the app is open: a banner with Reply (and Refer) right on it
            const NotifyBannerHost(),
            // floating island; on Ask it steps aside so the ask's Publish bar has the bottom edge
            if (_i != _ask) Positioned(
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
      ),
    );
  }

  Widget _island(Pal p) {
    // see-through, with the page softly blurred behind it; the blur is a layer of its own so the Ask circle can stand out of the bar
    final radius = BorderRadius.circular(28);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [BoxShadow(color: (p.dark ? const Color(0xFF1E1E1E) : const Color(0xFF1E1E1E)).withValues(alpha: p.dark ? .6 : .3), blurRadius: 32, spreadRadius: -8, offset: const Offset(0, 10))],
      ),
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: DecoratedBox(
                decoration: BoxDecoration(color: p.canvas.withValues(alpha: .85), borderRadius: radius, border: Border.all(color: p.border.withValues(alpha: .5))),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(6),
          child: AnimatedBuilder(
            animation: _notes,
            builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
              for (var k = 0; k < _items.length; k++) ...[
                if (k > 0) SizedBox(width: k == _ask || k == _ask + 1 ? 8 : 4),
                k == 0
                    ? _islandItem(p, k)
                    : KeyedSubtree(
                        key: Tours.key(const ['', 'nav-find', 'nav-ask', 'nav-notes', 'nav-talk'][k]),
                        child: _islandItem(p, k, badge: k == _notesTab ? _notes.unseen : k == _talk ? unreadChats.value : 0)),
              ],
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _islandItem(Pal p, int k, {int badge = 0}) {
    final active = _i == k;
    // Ask is the one action: a gold circle set in a notch that stands out of the bar at the top and the bottom
    final isAsk = k == _ask;
    final tone = p.dark ? const Color(0xFFFFD84A) : const Color(0xFF7A5A00);
    final fg = isAsk ? kInk : active ? tone : p.muted;
    final content = Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Stack(clipBehavior: Clip.none, children: [
        WIcon(_items[k].$1, size: isAsk ? 24 : 21, color: fg, strokeWidth: active || isAsk ? 2.2 : 1.9, spinKey: isAsk ? _askSpin : 0),
        if (badge > 0)
          Positioned(
            right: -8,
            top: -6,
            child: Container(
              height: 16,
              constraints: const BoxConstraints(minWidth: 16),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(color: Color(0x331E1E1E), blurRadius: 3)]),
              child: Text(badge > 9 && k == _notesTab ? '9+' : '$badge', style: const TextStyle(color: kInk, fontSize: 10, fontWeight: FontWeight.w700, height: 1)),
            ),
          ),
      ]),
      const SizedBox(height: 2),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: FittedBox(fit: BoxFit.scaleDown, child: Text(t(_items[k].$2), maxLines: 1, style: TextStyle(fontSize: 10, fontWeight: isAsk ? FontWeight.w700 : FontWeight.w500, height: 1, color: fg))),
      ),
    ]);
    final tile = isAsk
        ? Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: kGoldGradient,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFC9B93A).withValues(alpha: .5)),
              boxShadow: [
                BoxShadow(color: p.canvas.withValues(alpha: .9), spreadRadius: 5),
                BoxShadow(color: const Color(0xFFD6AA00).withValues(alpha: .5), blurRadius: 20, spreadRadius: -4, offset: const Offset(0, 10)),
              ],
            ),
            child: content,
          )
        : AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 56,
            height: 46,
            decoration: BoxDecoration(
              color: active ? kGold.withValues(alpha: p.dark ? .25 : .2) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: active ? Border.all(color: kGold.withValues(alpha: .7), width: .8) : null,
            ),
            child: content,
          );
    return Semantics(
      button: true,
      selected: active,
      label: t(_items[k].$2),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _go(k),
        // the Ask circle is taller than the bar: the bar's height stays that of the other tiles
        child: isAsk ? SizedBox(width: 64, height: 46, child: OverflowBox(maxHeight: 64, child: tile)) : tile,
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
            // with the BUSINESS NETWORK slogan, as on the web; shrinks rather than crowd the bell on the narrowest phones
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 4, right: 8),
                child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: LogoInline(size: 28, markSize: 36, tagline: true, onTap: onHome)),
              ),
            ),
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
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(24)),
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
              item(WI.contactCard, 'Phonebook', () => push(SubPage(title: t('Phonebook'), body: const PhonebookScreen()))),
              item(WI.sparkle, 'Leads for you', () => push(SubPage(title: t('Leads for you'), body: const LeadsScreen()))),
              item(WI.sun, 'Today in your area', () => push(SubPage(title: t('Today in your area'), body: const TodayScreen()))),
              item(WI.bell, 'Alerts', () => push(SubPage(title: t('Alerts'), body: const AlertsScreen()))),
              item(WI.deals, 'Your week', () => push(SubPage(title: t('Your week'), body: const WeekScreen()))),
              item(WI.bookmark, 'Saved asks', () => push(const SavedPostsScreen())),
              // help lives on the website so articles stay current without an app update
              item(WI.help, 'Help & Support', () {
                Navigator.of(context).pop();
                final from = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
                launchUrl(Uri.parse('$siteUrl/help?lang=${i18n.lang}&from=$from'), mode: LaunchMode.externalApplication);
              }),
              item(WI.sparkle, 'Take the app tour', () {
                Navigator.of(context).pop();
                tourRequest.value++;
              }),
              // @webwebai: the assistant answers in a chat
              item(WI.sparkle, 'Ask WebWeb AI', () async {
                final nav = Navigator.of(context);
                final api = auth.api;
                nav.pop();
                try {
                  final u = Profile.fromJson(await api.get('/users/handle/webwebai') as Map);
                  final ctx = nav.context;
                  if (ctx.mounted) openChat(ctx, Peer.fromProfile(u));
                } catch (_) {}
              }),
              // the Help page's form, in the app and signed in
              item(WI.talk, 'Write to us', () {
                Navigator.of(context).pop();
                showSupportSheet(context);
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
  const _NotesPanel({required this.notes, this.page = false});
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
              _bound(
                context,
                child: !n.loaded
                    ? const Padding(padding: EdgeInsets.all(24), child: Center(child: LogoLoader(size: 28)))
                    : n.items.isEmpty
                        ? _empty(p, t('No responses yet. When members share a contact on your Ask, it shows up here.'))
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

  Widget _empty(Pal p, String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: p.muted)),
      );
}

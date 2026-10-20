import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../auth_provider.dart';
import '../call_manager.dart';
import '../i18n.dart';
import '../permissions.dart';
import '../location.dart';
import '../models.dart';
import '../notifications.dart';
import '../outbox.dart';
import '../realtime.dart';
import '../safety.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/active_call_banner.dart';
import '../widgets/connection_pill.dart';
import '../widgets/image_grid.dart';
import '../widgets/upi.dart';
import 'contact_picker.dart';
import 'post_detail.dart';
import 'profile.dart';

/// Opens (or creates) the 1:1 chat with [peer]. [attachment] (an ask / update being replied to, an
/// item enquiry) waits above the composer and goes out with the next message, like the web.
Future<void> openChat(BuildContext context, Peer peer, {Map<String, dynamic>? attachment}) async {
  final api = context.read<AuthProvider>().api;
  try {
    final id = (await api.post('/chats', {'userId': peer.uid}) as Map)['id'] as String;
    if (context.mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatThread(chatId: id, peer: peer, pending: attachment)));
  } catch (e) {
    if (context.mounted) toast(context, '$e', error: true);
  }
}

Future<bool> confirmDeleteChat(BuildContext context, String name) async {
  final p = Pal.of(context);
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('Delete chat?'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      content: Text(t('Your chat with {name} will be removed from your account. {name} will still have their copy.', {'name': name}), style: TextStyle(fontSize: 14, color: p.muted)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Cancel'), style: TextStyle(color: p.text, fontWeight: FontWeight.w700))),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Delete'), style: TextStyle(color: p.danger, fontWeight: FontWeight.w700))),
      ],
    ),
  );
  return r == true;
}

Future<void> placeCall(BuildContext context, Peer peer, bool video) async {
  try {
    await context.read<CallManager>().startCall({'uid': peer.uid, 'name': peer.name, 'handle': peer.handle, 'company': peer.company, 'photoURL': peer.photoUrl}, video);
  } catch (e) {
    if (context.mounted) toast(context, '$e', error: true);
  }
}

// ---------- formatting helpers (web: en-IN, 12 hour, lower case) ----------
const _months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
String _clock(DateTime d) => '${d.hour % 12 == 0 ? 12 : d.hour % 12}:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'am' : 'pm'}';
String _dayTime(DateTime d) => '${d.day} ${_months[d.month - 1]}, ${_clock(d)}';
bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String _dayLabel(DateTime d) {
  final now = DateTime.now();
  if (_sameDay(d, now)) return t('Today');
  if (_sameDay(d, now.subtract(const Duration(days: 1)))) return t('Yesterday');
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

String _duration(int s) => s >= 3600 ? '${s ~/ 3600}h ${(s % 3600) ~/ 60}m' : s >= 60 ? '${s ~/ 60}m ${s % 60}s' : '${s}s';

/// "Voice call · 2m 3s", "Missed video call", ...
String callLabel(CallLog c, String meUid) {
  final mine = c.callerUid == meUid;
  final kind = c.video ? 'video call' : 'voice call';
  switch (c.status) {
    case 'completed':
      return '${c.video ? 'Video' : 'Voice'} call · ${_duration(c.durationS)}';
    case 'missed':
      return mine ? 'No answer ($kind)' : 'Missed $kind';
    case 'declined':
      return mine ? 'Declined ($kind)' : 'You declined ($kind)';
    default:
      return mine ? 'Cancelled $kind' : 'Missed $kind';
  }
}

/// One-line description of a message, used in reply quotes (web quoteText).
String quoteText(String text, String kind) {
  if (text.isNotEmpty) return text;
  return switch (kind) {
    'contact' => '👤 Contact',
    'location' => '📍 Location',
    'document' => '📎 Document',
    'profile' => '👤 Profile',
    'post' => '↩ About a post',
    'item' => '🛍 Item enquiry',
    'cart' => '🛒 Cart',
    'upi' => '₹ UPI payment',
    'image' => '📷 Photo',
    _ => '',
  };
}

/// Sent (one grey tick), delivered (two grey), read (two blue).
class Ticks extends StatelessWidget {
  final Msg m;
  const Ticks(this.m, {super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    if (m.pending) return WIcon(WI.clock, size: 13, color: p.muted);
    final read = m.readAt != null;
    return WIcon(read || m.deliveredAt != null ? WI.tickDouble : WI.tick, size: 16, color: read ? const Color(0xFF0EA5E9) : p.muted, strokeWidth: 1.8);
  }
}

/// Dashed empty state with a gold disc icon (web chat Empty).
class _Empty extends StatelessWidget {
  final WI icon;
  final String title, hint;
  const _Empty(this.icon, this.title, this.hint);
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: DashedBox(
        radius: 8,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: SizedBox(
          width: double.infinity,
          child: Column(children: [
            Container(width: 56, height: 56, alignment: Alignment.center, decoration: BoxDecoration(color: p.tagBg, shape: BoxShape.circle), child: WIcon(icon, size: 26, color: p.tagText)),
            const SizedBox(height: 12),
            Text(t(title), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 320), child: Text(t(hint), textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: p.muted))),
          ]),
        ),
      ),
    );
  }
}

// ============================ Talk tab ============================

class TalkScreen extends StatefulWidget {
  const TalkScreen({super.key});
  @override
  State<TalkScreen> createState() => _TalkScreenState();
}

class _TalkScreenState extends State<TalkScreen> {
  List<ChatSummary>? _chats;
  List<CallLog> _calls = [];
  List<Profile> _people = [];
  String _tab = 'chats';
  final _q = TextEditingController();
  StreamSubscription? _sub;
  Timer? _debounce, _peopleDebounce, _poll;

  Api get _api => context.read<AuthProvider>().api;
  String get _me => context.read<AuthProvider>().profile?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _load();
    _loadPeople();
    _sub = context.read<RealtimeService>().events.listen((e) {
      if (const {'msg', 'read', 'delivered', 'call_log'}.contains(e['type'])) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 250), _load);
      }
    });
    // light refresh like the web (and the safety net when the socket is down)
    _poll = Timer.periodic(const Duration(seconds: 6), (_) => _load());
  }

  Future<void> _load() async {
    try {
      final c = await _api.get('/chats') as List;
      final k = await _api.get('/app/calls') as List;
      final blocked = await loadBlocked(_api);
      if (!mounted) return;
      setState(() {
        _chats = c.map((e) => ChatSummary.fromJson(e as Map, _me)).where((x) => !blocked.contains(x.peer.uid)).toList();
        _calls = k.map((e) => CallLog.fromJson(e as Map)).toList();
      });
    } catch (_) {
      if (mounted) setState(() => _chats ??= []);
    }
  }

  /// People matching the search box (newest members when empty), so a new chat can be started.
  Future<void> _loadPeople() async {
    try {
      final d = await _api.get('/app/people', {'q': _q.text.trim()}) as List;
      if (mounted) setState(() => _people = d.map((e) => Profile.fromJson(e as Map)).toList());
    } catch (_) {}
  }

  void _onSearch(String _) {
    setState(() {});
    _peopleDebounce?.cancel();
    _peopleDebounce = Timer(const Duration(milliseconds: 300), _loadPeople);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    _peopleDebounce?.cancel();
    _poll?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<bool> _deleteChat(ChatSummary c) async {
    final yes = await confirmDeleteChat(context, c.peer.name);
    if (!yes || !mounted) return false;
    try {
      await _api.delete('/app/chats/${c.id}');
      if (mounted) {
        setState(() => _chats?.removeWhere((x) => x.id == c.id));
        toast(context, t('Chat deleted'));
      }
      return true;
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
      return false;
    }
  }

  Future<void> _open(ChatSummary c) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatThread(chatId: c.id, peer: c.peer)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final all = _chats;
    final q = _q.text.trim().toLowerCase();
    final unreadCount = (all ?? const []).where((c) => c.unread).length;
    final chats = (all ?? const <ChatSummary>[]).where((c) {
      if (_tab == 'unread' && !c.unread) return false;
      if (q.isEmpty) return true;
      return '${c.peer.name} ${c.peer.company} ${c.lastMessage ?? ''}'.toLowerCase().contains(q);
    }).toList();
    final chatted = (all ?? const <ChatSummary>[]).map((c) => c.peer.uid).toSet();
    final morePeople = _people.where((u) => !chatted.contains(u.uid)).toList();
    final n = all?.length ?? 0;

    Widget tabChip(String id, String label) {
      final on = _tab == id;
      return GestureDetector(
        onTap: () => setState(() => _tab = id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: on ? kGoldGradient : null,
            color: on ? null : p.chip,
            borderRadius: BorderRadius.circular(20),
            boxShadow: on ? const [BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1))] : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(t(label), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: on ? kInk : p.muted)),
            if (id == 'unread' && unreadCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(color: kInk, borderRadius: BorderRadius.circular(10)),
                child: Text('$unreadCount', style: const TextStyle(fontSize: 11, height: 16 / 11, fontWeight: FontWeight.w700, color: kGold)),
              ),
            ],
          ]),
        ),
      );
    }

    return LogoRefresh(
      onRefresh: () async {
        await _load();
        await _loadPeople();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 16, 16, islandSpace(context)),
        children: [
          Text(t('Talk'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1)),
          const SizedBox(height: 4),
          Text(
            all == null
                ? t('Your conversations')
                : '$n ${t(n == 1 ? 'conversation' : 'conversations')}${unreadCount > 0 ? ' · $unreadCount ${t('unread')}' : ''}',
            style: TextStyle(fontSize: 14, color: p.muted),
          ),
          const SizedBox(height: 12),
          if (_tab != 'calls') ...[
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(30)),
              child: Row(children: [
                WIcon(WI.search, size: 18, color: p.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _q,
                    onChanged: _onSearch,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: t('Search people or messages'),
                      hintStyle: TextStyle(color: p.muted, fontSize: 14),
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
            const SizedBox(height: 12),
          ],
          SizedBox(
            height: 36,
            child: OverflowBox(
              maxWidth: MediaQuery.of(context).size.width,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                tabChip('chats', 'All chats'),
                const SizedBox(width: 8),
                tabChip('unread', 'Unread'),
                const SizedBox(width: 8),
                tabChip('calls', 'Calls'),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          if (_tab == 'calls') ...[
            if (_calls.isEmpty) const _Empty(WI.phone, 'No calls yet', 'Open a chat and tap the call or video icon.'),
            for (final c in _calls) ...[_callTile(c, p), const SizedBox(height: 4)],
          ] else if (all == null)
            const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: LogoLoader()))
          else ...[
            if (chats.isEmpty && _tab == 'chats' && q.isEmpty && morePeople.isEmpty) const _Empty(WI.talk, 'No messages yet', 'Open a public page or a post and tap Message.'),
            if (chats.isEmpty && (_tab == 'unread' || q.isNotEmpty) && (_tab == 'unread' || morePeople.isEmpty))
              _Empty(WI.search, _tab == 'unread' && q.isEmpty ? "You're all caught up" : 'No matches', _tab == 'unread' && q.isEmpty ? 'No unread conversations.' : 'Try a different name or word.'),
            for (final c in chats) ...[_chatTile(c, p), const SizedBox(height: 4)],
            if (_tab == 'chats' && morePeople.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 6),
                child: Text(t(q.isEmpty ? 'Start a new chat' : 'People'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.muted)),
              ),
              for (final u in morePeople) ...[_personTile(u, p), const SizedBox(height: 4)],
            ],
          ],
        ],
      ),
    );
  }

  Widget _row(Pal p, {required Widget avatar, required Widget top, required Widget bottom, bool highlight = false, VoidCallback? onTap, VoidCallback? onLongPress, Widget? trailing}) {
    return Material(
      color: highlight ? kGold.withValues(alpha: .1) : p.chip.withValues(alpha: .4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: highlight ? kGold.withValues(alpha: .6) : Colors.transparent)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(children: [
            avatar,
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [top, const SizedBox(height: 2), bottom])),
            if (trailing != null) trailing,
          ]),
        ),
      ),
    );
  }

  Widget _avatar(Peer u) {
    final on = context.watch<RealtimeService>().isOnline(u.uid);
    return Stack(clipBehavior: Clip.none, children: [
      Avatar(name: u.name, photoUrl: u.photoUrl, size: 40, type: u.userType, badge: 16, uid: u.uid),
      if (on)
        Positioned(
          left: -1,
          bottom: -1,
          child: Container(width: 12, height: 12, decoration: BoxDecoration(color: kGreen, shape: BoxShape.circle, border: Border.all(color: Pal.of(context).canvas, width: 2))),
        ),
    ]);
  }

  Widget _nameLine(Pal p, Peer u) => Text.rich(
        TextSpan(children: [
          TextSpan(text: u.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (u.company.isNotEmpty) TextSpan(text: ' · ${u.company}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: p.muted)),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15, height: 1.25),
      );

  Widget _chatTile(ChatSummary c, Pal p) => Dismissible(
        key: ValueKey('chat-${c.id}'),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) => _deleteChat(c),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(color: p.danger, borderRadius: BorderRadius.circular(8)),
          child: const WIcon(WI.trash, color: Colors.white),
        ),
        child: _row(
          p,
          highlight: c.unread,
          onTap: () => _open(c),
          onLongPress: () => _deleteChat(c),
          avatar: _avatar(c.peer),
          top: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: _nameLine(p, c.peer)),
            if (c.lastMessageAt != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(timeAgo(c.lastMessageAt!), style: TextStyle(fontSize: 12, fontWeight: c.unread ? FontWeight.w700 : FontWeight.w500, color: c.unread ? p.text : p.muted)),
              ),
          ]),
          bottom: Row(children: [
            Expanded(
              child: Text(c.lastMessage ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, height: 1.25, fontWeight: c.unread ? FontWeight.w700 : FontWeight.w500, color: c.unread ? p.text : p.muted)),
            ),
            if (c.unread) ...[const SizedBox(width: 8), Container(width: 10, height: 10, decoration: const BoxDecoration(gradient: kGoldGradient, shape: BoxShape.circle))],
          ]),
        ),
      );

  Widget _personTile(Profile u, Pal p) {
    final peer = Peer.fromProfile(u);
    Future<void> chat() async {
      await openChat(context, peer);
      _load();
    }

    return _row(
      p,
      onTap: chat,
      avatar: _avatar(peer),
      top: _nameLine(p, peer),
      bottom: Text('@${u.handle}${u.location.isEmpty ? '' : ' · ${u.location}'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, height: 1.25, color: p.muted)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        _roundIcon(p, WI.phone, t('Call'), () => placeCall(context, peer, false)),
        _roundIcon(p, WI.talk, t('Message'), chat),
      ]),
    );
  }

  Widget _roundIcon(Pal p, WI icon, String label, VoidCallback onTap) => Semantics(
        button: true,
        label: label,
        child: InkResponse(onTap: onTap, radius: 20, child: SizedBox(width: 40, height: 40, child: Center(child: WIcon(icon, size: 22, color: p.text)))),
      );

  Widget _callTile(CallLog c, Pal p) {
    final peer = c.peer;
    if (peer == null) return const SizedBox.shrink();
    final outgoing = c.callerUid == _me;
    final missed = !outgoing && c.status != 'completed';
    final color = missed ? p.danger : p.muted;
    return _row(
      p,
      onTap: () => openChat(context, peer),
      avatar: _avatar(peer),
      top: Row(children: [
        Expanded(child: Text(peer.shownName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, height: 1.25, fontWeight: FontWeight.w700, color: missed ? p.danger : p.text))),
        Text(timeAgo(c.createdAt), style: TextStyle(fontSize: 12, color: p.muted)),
      ]),
      bottom: Row(children: [
        WIcon(outgoing ? WI.callOut : (missed ? WI.callMissed : WI.callIn), size: 15, color: missed ? p.danger : kGreen),
        const SizedBox(width: 4),
        Flexible(child: Text(t(callLabel(c, _me)), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, height: 1.25, color: color))),
      ]),
      trailing: Padding(padding: const EdgeInsets.only(left: 4), child: _roundIcon(p, c.video ? WI.video : WI.phone, t('Call'), () => placeCall(context, peer, c.video))),
    );
  }
}

// ============================ Chat thread (web chat/[chatId]) ============================

/// A row in the thread: a message or a call-log entry.
class _Item {
  final Msg? msg;
  final CallLog? call;
  _Item.msg(Msg m) : msg = m, call = null;
  _Item.call(CallLog c) : call = c, msg = null;
  DateTime get at => msg?.createdAt ?? call!.createdAt;
}

const _chatReactions = ['👍', '❤️', '🙏', '😂', '😮'];

class ChatThread extends StatefulWidget {
  final String chatId;
  final Peer peer;
  /// sent along with the next message (reply to an ask / update, item enquiry)
  final Map<String, dynamic>? pending;
  const ChatThread({super.key, required this.chatId, required this.peer, this.pending});
  @override
  State<ChatThread> createState() => _ChatThreadState();
}

class _ChatThreadState extends State<ChatThread> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<Msg> _msgs = [];
  List<CallLog> _calls = [];
  bool _loaded = false;
  bool _typing = false;
  bool _iAmTyping = false;
  int? _selected; // message showing the reaction bar
  Msg? _replyTo;
  late Map<String, dynamic>? _pending = widget.pending;
  Timer? _typingOff, _iTypingOff, _poll;
  StreamSubscription? _sub, _outboxSub;
  late final RealtimeService _rt = context.read<RealtimeService>();
  late final String _me = context.read<AuthProvider>().profile?.uid ?? '';
  Api get _api => context.read<AuthProvider>().api;
  Peer get _peer => widget.peer;

  @override
  void initState() {
    super.initState();
    NotificationService.activeChat = widget.chatId;
    _load();
    _sub = _rt.events.listen(_onEvent);
    _outboxSub = Outbox.results.listen(_onOutbox);
    // reactions are polled (like the web); messages too when the socket is down
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_rt.connected) _loadNew();
      _loadReactions();
      _syncReceipts();
    });
  }

  /// Receipts that arrived before the send request returned the message's real id.
  final Map<int, String> _early = {};

  /// Ticks of my sent messages from the server, for any delivered / read event this phone missed
  /// (socket down, app in the background). Only while something of mine is not read yet.
  Future<void> _syncReceipts() async {
    if (!_msgs.any((m) => m.senderUid == _me && !m.pending && m.readAt == null)) return;
    try {
      final r = Map<String, dynamic>.from(await _api.get('/chats/${widget.chatId}/receipts') as Map);
      if (!mounted) return;
      DateTime? at(dynamic v) => v == null ? null : DateTime.fromMillisecondsSinceEpoch((v as num).toInt());
      var changed = false;
      for (final m in _msgs) {
        final x = r['${m.id}'];
        if (x is! Map) continue;
        final d = at(x['deliveredAt']), rd = at(x['readAt']);
        if (m.deliveredAt == null && d != null) {
          m.deliveredAt = d;
          changed = true;
        }
        if (m.readAt == null && rd != null) {
          m.readAt = rd;
          changed = true;
        }
      }
      if (changed) setState(() {});
    } catch (_) {}
  }

  int get _lastId => _msgs.where((m) => !m.pending).fold(0, (a, m) => m.id > a ? m.id : a);

  /// Messages still in the outbox for this chat, shown with a clock until they go out.
  Future<List<Msg>> _queued() async => [
        for (final it in await Outbox.pending(widget.chatId))
          Msg(
            id: -it.createdAt.microsecondsSinceEpoch,
            senderUid: _me,
            text: it.text,
            imageUrl: it.imageUrl,
            attachment: it.attachment,
            replyTo: it.replyQuote == null ? null : MsgQuote.fromJson(it.replyQuote!),
            createdAt: it.createdAt,
            pending: true,
            tmpId: it.tmp,
          ),
      ];

  Future<void> _load() async {
    // what the phone kept from last time shows at once (and is all there is offline), then the server's answer
    if (!_loaded) {
      try {
        final cached = await _api.cached('/chats/${widget.chatId}/messages');
        if (cached is List && mounted && !_loaded) {
          final q = await _queued();
          setState(() {
            _msgs = [...cached.map((e) => Msg.fromJson(e as Map)), ...q];
            _loaded = true;
          });
          _toBottom(jump: true);
        }
      } catch (_) {}
    }
    try {
      final d = (await _api.get('/chats/${widget.chatId}/messages') as List).map((e) => Msg.fromJson(e as Map)).toList();
      final q = await _queued();
      if (!mounted) return;
      setState(() {
        _msgs = [...d, ...q.where((m) => !_sent.containsKey(m.tmpId))];
        _loaded = true;
      });
      _toBottom(jump: true);
      _loadReactions();
    } catch (_) {
      final q = await _queued();
      if (mounted) {
        setState(() {
          if (!_loaded) _msgs = q;
          _loaded = true;
        });
      }
    }
    try {
      final k = (await _api.get('/app/calls', {'peer': _peer.uid}) as List).map((e) => CallLog.fromJson(e as Map)).toList();
      if (mounted) setState(() => _calls = k);
    } catch (_) {}
  }

  /// tmp id -> message id, for queued messages the outbox has delivered
  final Map<String, int> _sent = {};

  void _onOutbox(OutboxResult r) {
    if (r.chatId != widget.chatId || !mounted) return;
    if (r.message != null) {
      final sent = Msg.fromJson(r.message!);
      _sent[r.tmp] = sent.id;
      final early = _early.remove(sent.id);
      if (early != null) _applyReceipt(sent, early);
      setState(() {
        final hasReal = _msgs.any((m) => m.id == sent.id);
        _msgs = [
          for (final m in _msgs)
            if (m.tmpId == r.tmp) ...[if (!hasReal) sent] else m,
        ];
      });
    } else {
      setState(() => _msgs = _msgs.where((m) => m.tmpId != r.tmp).toList());
      toast(context, t('Message not sent: {why}', {'why': r.error ?? ''}), error: true);
    }
  }

  Future<void> _loadReactions() async {
    try {
      final r = Map<String, dynamic>.from(await _api.get('/chats/${widget.chatId}/reactions') as Map);
      if (!mounted) return;
      setState(() {
        for (final m in _msgs) {
          m.reactions = ((r['${m.id}'] as List?) ?? const []).map((e) => MsgReaction.fromJson(e as Map)).toList();
        }
      });
    } catch (_) {}
  }

  /// Messages newer than what we have (polling fallback).
  Future<void> _loadNew() async {
    try {
      final d = (await _api.get('/chats/${widget.chatId}/messages', {'after': _lastId}) as List).map((e) => Msg.fromJson(e as Map)).toList();
      if (!mounted || d.isEmpty) return;
      setState(() => _msgs = [..._msgs, ...d.where((m) => !_msgs.any((x) => x.id == m.id))]);
      _toBottom();
    } catch (_) {}
  }

  void _markRead() => _rt.send({'type': 'read', 'chatId': widget.chatId});

  void _toBottom({bool jump = false}) => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final end = _scroll.position.maxScrollExtent;
        jump ? _scroll.jumpTo(end) : _scroll.animateTo(end, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      });

  void _onEvent(Json e) {
    switch (e['type']) {
      case 'msg':
        if (e['chatId'] != widget.chatId) return;
        final m = Msg.fromJson(e['message'] as Map);
        if (_msgs.any((x) => x.id == m.id)) return;
        setState(() => _msgs = [..._msgs, m]);
        if (m.senderUid != _me) _markRead();
        _toBottom();
        break;
      case 'hello':
        // reconnected: catch up on ticks that changed while the socket was down
        _syncReceipts();
        break;
      case 'delivered':
      case 'read':
        if (e['chatId'] != widget.chatId) return;
        final ids = ((e['ids'] as List?) ?? []).map((x) => (x as num).toInt()).toSet();
        setState(() {
          for (final m in _msgs) {
            if (ids.remove(m.id)) _applyReceipt(m, e['type'] as String);
          }
        });
        // not on screen yet: the send request has not returned this message's id
        for (final id in ids) {
          if (_early[id] != 'read') _early[id] = e['type'] as String;
        }
        break;
      case 'typing':
        if (e['from'] != _peer.uid) return;
        _typingOff?.cancel();
        setState(() => _typing = e['on'] == true);
        if (_typing) _typingOff = Timer(const Duration(seconds: 4), () => mounted ? setState(() => _typing = false) : null);
        break;
      case 'call_log':
        final log = CallLog.fromJson(e['log'] as Map);
        if (log.callerUid != _peer.uid && log.calleeUid != _peer.uid) return;
        if (_calls.any((c) => c.id == log.id)) return;
        setState(() => _calls = [..._calls, log]);
        _toBottom();
        break;
    }
  }

  void _applyReceipt(Msg m, String kind) {
    m.deliveredAt ??= DateTime.now();
    if (kind == 'read') m.readAt ??= DateTime.now();
  }

  /// Sends the composer text (with the waiting attachment), or a photo / attachment from the sheet.
  Future<void> _send({String? text, String? imageUrl, Map<String, dynamic>? attachment}) async {
    final fromComposer = text == null && imageUrl == null && attachment == null;
    final body = text ?? _input.text.trim();
    final att = attachment ?? (fromComposer ? _pending : null);
    if (body.isEmpty && imageUrl == null && att == null) return;
    final reply = _replyTo;
    final tmp = 'm${_me.hashCode.toRadixString(36)}${DateTime.now().microsecondsSinceEpoch}';
    final pending = Msg(
      id: -DateTime.now().microsecondsSinceEpoch, senderUid: _me, text: body, imageUrl: imageUrl, attachment: att,
      replyTo: reply == null ? null : MsgQuote(id: '${reply.id}', senderUid: reply.senderUid, text: reply.text, kind: reply.kind),
      createdAt: DateTime.now(), pending: true, tmpId: tmp,
    );
    if (fromComposer) _input.clear();
    _setTyping(false);
    setState(() {
      _msgs = [..._msgs, pending];
      _replyTo = null;
      if (fromComposer) _pending = null;
    });
    _toBottom();
    // through the outbox: sent now when online, otherwise kept (clock) and sent by itself once the network
    // is back, even if the app is closed in between
    await Outbox.add(OutboxItem(
      tmp: tmp,
      chatId: widget.chatId,
      text: body,
      imageUrl: imageUrl,
      attachment: att,
      replyToId: reply?.id,
      replyQuote: reply == null ? null : {'id': '${reply.id}', 'senderUid': reply.senderUid, 'text': reply.text, 'kind': reply.kind},
      createdAt: pending.createdAt,
    ));
  }

  Future<void> _react(Msg m, String emoji) async {
    final mineNow = m.reactions.where((r) => r.mine).map((r) => r.emoji).firstOrNull;
    final next = mineNow == emoji ? null : emoji;
    setState(() {
      _selected = null;
      final kept = [for (final r in m.reactions) r.mine ? MsgReaction(r.emoji, r.count - 1, false) : r].where((r) => r.count > 0).toList();
      if (next == null) {
        m.reactions = kept;
      } else {
        final hit = kept.indexWhere((r) => r.emoji == next);
        m.reactions = hit >= 0 ? [for (var i = 0; i < kept.length; i++) i == hit ? MsgReaction(next, kept[i].count + 1, true) : kept[i]] : [...kept, MsgReaction(next, 1, true)];
      }
    });
    try {
      await _api.put('/chats/${widget.chatId}/messages/${m.id}/reaction', {'emoji': next});
    } catch (_) {
      _loadReactions();
    }
  }

  void _setTyping(bool on) {
    if (on != _iAmTyping) {
      _iAmTyping = on;
      _rt.send({'type': 'typing', 'to': _peer.uid, 'chatId': widget.chatId, 'on': on});
    }
    _iTypingOff?.cancel();
    if (on) _iTypingOff = Timer(const Duration(seconds: 2), () => _setTyping(false));
  }

  Future<void> _deleteChat() async {
    final yes = await confirmDeleteChat(context, _peer.name);
    if (!yes || !mounted) return;
    try {
      await _api.delete('/app/chats/${widget.chatId}');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  void dispose() {
    if (NotificationService.activeChat == widget.chatId) NotificationService.activeChat = null;
    _setTyping(false);
    _sub?.cancel();
    _outboxSub?.cancel();
    _typingOff?.cancel();
    _iTypingOff?.cancel();
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<_Item> get _timeline => [..._msgs.map(_Item.msg), ..._calls.map(_Item.call)]..sort((a, b) => a.at.compareTo(b.at));

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final on = context.watch<RealtimeService>().isOnline(_peer.uid);
    final items = _timeline;
    final top = MediaQuery.of(context).padding.top;
    final canSend = _input.text.trim().isNotEmpty || _pending != null;
    return Scaffold(
      backgroundColor: p.canvas,
      body: Column(children: [
        // header: back, picture + name (open the profile), call buttons
        Container(
          padding: EdgeInsets.fromLTRB(8, top + 8, 8, 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
          child: Row(children: [
            Semantics(
              button: true,
              label: t('Back'),
              child: InkResponse(onTap: () => Navigator.maybePop(context), radius: 20, child: Padding(padding: const EdgeInsets.all(4), child: WIcon(WI.back, size: 28, color: p.text))),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _peer.handle.isEmpty ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: _peer.handle))),
                child: Row(children: [
                  Avatar(name: _peer.name, photoUrl: _peer.photoUrl, size: 36, type: _peer.userType, badge: 16, uid: _peer.uid),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_peer.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.25)),
                      Builder(builder: (context) {
                        // offline: say so where "online" would be (WhatsApp shows "Waiting for network")
                        final status = connectionStatus(context.watch<RealtimeService>());
                        final live = status == null && (_typing || on);
                        return Text(
                          status ?? (_typing ? t('typing…') : (on ? t('online') : _peer.company)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, height: 1.25, color: live ? kGreen : p.muted, fontWeight: live ? FontWeight.w600 : FontWeight.w500),
                        );
                      }),
                    ]),
                  ),
                ]),
              ),
            ),
            _headerBtn(p, WI.video, t('Video call'), () => placeCall(context, _peer, true)),
            _headerBtn(p, WI.phone, t('Call'), () => placeCall(context, _peer, false)),
            PopupMenuButton<String>(
              tooltip: t('More'),
              icon: WIcon(WI.more, size: 24, color: p.text),
              onSelected: (v) async {
                if (v == 'delete') {
                  _deleteChat();
                } else if (v == 'safety') {
                  if (await showSafetySheet(context, uid: _peer.uid, name: _peer.name) && mounted) Navigator.pop(context);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'safety',
                  child: Row(children: [Icon(Icons.flag_outlined, size: 18, color: p.text), const SizedBox(width: 10), const Text('Report or block', style: TextStyle(fontWeight: FontWeight.w600))]),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [WIcon(WI.trash, size: 18, color: p.danger), const SizedBox(width: 10), Text(t('Delete chat'), style: TextStyle(color: p.danger, fontWeight: FontWeight.w600))]),
                ),
              ],
            ),
          ]),
        ),
        const ActiveCallBanner(),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              FocusScope.of(context).unfocus();
              if (_selected != null) setState(() => _selected = null);
            },
            child: !_loaded
                ? const Center(child: LogoLoader())
                : items.isEmpty
                    ? Center(child: Text(t('Say hello 👋'), style: TextStyle(color: p.muted, fontWeight: FontWeight.w600)))
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final it = items[i];
                          final showDay = i == 0 || !_sameDay(items[i - 1].at, it.at);
                          return Column(children: [
                            if (showDay) _dayPill(_dayLabel(it.at), p),
                            it.call != null ? _callRow(it.call!, p) : Padding(padding: const EdgeInsets.only(bottom: 8), child: _message(it.msg!, p)),
                          ]);
                        },
                      ),
          ),
        ),
        if (_pending != null) _pendingBox(p),
        if (_replyTo != null) _replyBox(p),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
              decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(30), border: Border.all(color: p.border)),
              child: Row(children: [
                Semantics(
                  button: true,
                  label: t('Attach'),
                  child: GestureDetector(
                    onTap: _openAttach,
                    child: Container(width: 32, height: 32, decoration: BoxDecoration(color: p.chip, shape: BoxShape.circle), child: Center(child: WIcon(WI.plus, size: 20, color: p.text, strokeWidth: 2.2))),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _input,
                    // an item or post tagged on the way in: the box is ready for the message about it
                    autofocus: widget.pending != null,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (v) {
                      _setTyping(v.isNotEmpty);
                      setState(() {});
                    },
                    style: const TextStyle(fontSize: 16),
                    decoration: InputDecoration(
                      hintText: _pending != null ? t('Write your message…') : t('Message...'),
                      hintStyle: TextStyle(color: p.muted),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  label: t('Send'),
                  child: GestureDetector(
                    onTap: canSend ? () => _send() : null,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: canSend ? 1 : .4,
                      child: Container(width: 40, height: 40, decoration: const BoxDecoration(gradient: kGoldGradient, shape: BoxShape.circle), child: const Center(child: WIcon(WI.send, size: 20, color: kInk, strokeWidth: 2.2))),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _headerBtn(Pal p, WI icon, String label, VoidCallback onTap) => Semantics(
        button: true,
        label: label,
        child: InkResponse(onTap: onTap, radius: 20, child: Padding(padding: const EdgeInsets.all(8), child: WIcon(icon, size: 24, color: p.text))),
      );

  Widget _dayPill(String s, Pal p) => Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(20)),
          child: Text(s, style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      );

  Widget _callRow(CallLog c, Pal p) {
    final mine = c.callerUid == _me;
    final missed = !mine && c.status != 'completed';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          WIcon(c.video ? WI.video : WI.phone, size: 16, color: missed ? p.danger : kGreen),
          const SizedBox(width: 8),
          Text('${t(callLabel(c, _me))}  ·  ${_clock(c.createdAt)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: missed ? p.danger : p.text)),
        ]),
      ),
    );
  }

  Widget _smallBtn(Pal p, WI icon, String label, VoidCallback onTap) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: SizedBox(width: 28, height: 28, child: Center(child: Opacity(opacity: .7, child: WIcon(icon, size: 18, color: p.muted)))),
        ),
      );

  Widget _message(Msg m, Pal p) {
    final mine = m.senderUid == _me;
    final open = _selected == m.id;
    final maxW = MediaQuery.of(context).size.width * .75 - 32;
    final pad = m.imageUrl != null ? const EdgeInsets.all(4) : (m.attachment != null ? const EdgeInsets.all(6) : const EdgeInsets.symmetric(horizontal: 16, vertical: 8));
    final fg = mine ? p.onBubble : p.text;
    final bubble = GestureDetector(
      onTap: mine ? null : () => setState(() => _selected = open ? null : m.id),
      onLongPress: () {
        if (m.text.isNotEmpty) {
          Clipboard.setData(ClipboardData(text: m.text));
          toast(context, t('Copied'));
        }
      },
      child: Container(
        constraints: BoxConstraints(maxWidth: maxW),
        padding: pad,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: mine ? p.bubble : p.chip, borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (m.replyTo != null)
            Container(
              margin: EdgeInsets.fromLTRB(m.imageUrl != null || m.attachment != null ? 4 : 0, m.imageUrl != null || m.attachment != null ? 4 : 0, m.imageUrl != null || m.attachment != null ? 4 : 0, 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: mine ? fg.withValues(alpha: .1) : p.canvas.withValues(alpha: .7),
                borderRadius: BorderRadius.circular(8),
                border: Border(left: BorderSide(color: fg.withValues(alpha: .4), width: 4)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.replyTo!.senderUid == _me ? t('You') : _peer.name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
                Text(quoteText(m.replyTo!.text, m.replyTo!.kind), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: fg.withValues(alpha: .8))),
              ]),
            ),
          if (m.imageUrl != null)
            GestureDetector(
              onTap: () => openImageViewer(context, [m.imageUrl!], 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(constraints: BoxConstraints(maxHeight: 256, maxWidth: maxW), child: NetImg(m.imageUrl!, width: maxW)),
              ),
            ),
          if (m.attachment != null) _attachment(m.attachment!, mine, p),
          if (m.text.isNotEmpty)
            Padding(
              padding: m.imageUrl != null ? const EdgeInsets.symmetric(horizontal: 12, vertical: 4) : (m.attachment != null ? const EdgeInsets.fromLTRB(6, 6, 6, 2) : EdgeInsets.zero),
              child: Text(m.text, style: TextStyle(fontSize: 15, color: fg, height: 1.4)),
            ),
        ]),
      ),
    );

    final row = Row(mainAxisSize: MainAxisSize.min, textDirection: mine ? TextDirection.rtl : TextDirection.ltr, children: [
      Flexible(child: bubble),
      const SizedBox(width: 4),
      _smallBtn(p, WI.reply, t('Reply'), () => setState(() {
            _replyTo = m;
            _selected = null;
          })),
      if (mine)
        _smallBtn(p, WI.info, t('Message info'), () => _showInfo(m))
      else
        _smallBtn(p, WI.smile, t('React'), () => setState(() => _selected = open ? null : m.id)),
    ]);

    final mineReaction = m.reactions.where((r) => r.mine).map((r) => r.emoji).firstOrNull;
    return _SwipeToReply(
      onReply: () => setState(() => _replyTo = m),
      child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
        if (open && !mine)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: p.canvas,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: p.border),
              boxShadow: const [BoxShadow(color: Color(0x1A1E1E1E), blurRadius: 12, offset: Offset(0, 4))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final e in _chatReactions)
                GestureDetector(
                  onTap: () => _react(m, e),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: mineReaction == e ? p.chip : Colors.transparent, borderRadius: BorderRadius.circular(20)),
                    child: Text(e, style: const TextStyle(fontSize: 20, height: 1.2)),
                  ),
                ),
            ]),
          ),
        row,
        if (m.reactions.isNotEmpty)
          Transform.translate(
            offset: const Offset(0, -8),
            child: Padding(
              padding: EdgeInsets.only(left: mine ? 0 : 12, right: mine ? 12 : 0),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (final r in m.reactions)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: p.canvas,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: r.mine ? p.text.withValues(alpha: .5) : p.border),
                      boxShadow: const [BoxShadow(color: Color(0x0F1E1E1E), blurRadius: 4, offset: Offset(0, 1))],
                    ),
                    child: Text(r.count > 1 ? '${r.emoji} ${r.count}' : r.emoji, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.2)),
                  ),
              ]),
            ),
          ),
        Padding(
          padding: EdgeInsets.only(left: 12, right: 12, top: m.reactions.isNotEmpty ? 0 : 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_clock(m.createdAt), style: TextStyle(fontSize: 11, color: p.muted)),
            if (mine) ...[const SizedBox(width: 4), Ticks(m)],
          ]),
        ),
      ]),
    );
  }

  /// Contact / location / document / post / profile / item / cart attachments (web AttachmentView).
  Widget _attachment(Map<String, dynamic> a, bool mine, Pal p) {
    final fg = mine ? p.onBubble : p.text;
    final boxColor = mine ? fg.withValues(alpha: .1) : p.canvas;
    TextStyle label() => TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg.withValues(alpha: .7), letterSpacing: 0);
    Widget box({required Widget child, VoidCallback? onTap, bool goldEdge = false, EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10)}) => GestureDetector(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 224),
            padding: padding,
            decoration: BoxDecoration(
              color: boxColor,
              borderRadius: BorderRadius.circular(8),
              border: goldEdge ? const Border(left: BorderSide(color: kGold, width: 4)) : null,
            ),
            child: child,
          ),
        );
    switch (a['type']) {
      case 'upi':
        return UpiCard(a: a, mine: mine, fg: fg, bg: boxColor);
      case 'post':
        return box(
          goldEdge: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailScreen(postId: '${a['postId']}'))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('${t(a['kind'] == 'ask' ? 'Reply to ask' : 'Reply to update').toUpperCase()}${a['by'] != null ? ' · ${a['by']}' : ''}', style: label().copyWith(fontSize: 11)),
                const SizedBox(height: 2),
                Text('${a['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg, height: 1.35)),
                if (a['snippet'] != null) Text('${a['snippet']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: fg.withValues(alpha: .75))),
              ]),
            ),
            if (a['imageUrl'] != null) ...[const SizedBox(width: 10), ClipRRect(borderRadius: BorderRadius.circular(6), child: NetImg('${a['imageUrl']}', width: 56, height: 56))],
          ]),
        );
      case 'profile':
        return box(
          goldEdge: true,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: '${a['handle']}'))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Avatar(name: '${a['name']}', photoUrl: a['photoURL'] as String?, size: 44),
            const SizedBox(width: 12),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(t('Shared a page').toUpperCase(), style: label()),
                Text('${a['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
                Text('@${a['handle']}${a['subtitle'] != null ? ' · ${a['subtitle']}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: fg.withValues(alpha: .75))),
              ]),
            ),
          ]),
        );
      case 'item':
        final icon = a['kind'] == 'service' ? WI.service : WI.box;
        // passed on by the sender (not an enquiry): opens the item on the seller's page
        final shared = a['shared'] == true && '${a['handle'] ?? ''}'.isNotEmpty;
        // shared or enquired about, it reads like the message a reply quotes: a gold edge, the words under it
        return box(
          goldEdge: true,
          onTap: shared
              ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: '${a['handle']}', itemId: a['itemId'] as String?)))
              : null,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: a['imageUrl'] != null
                  ? NetImg('${a['imageUrl']}', width: 48, height: 48)
                  : Container(width: 48, height: 48, color: Colors.black.withValues(alpha: .1), child: Center(child: WIcon(icon, size: 24, color: fg))),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(t(shared ? (a['kind'] == 'service' ? 'Shared a service' : 'Shared a product') : (a['kind'] == 'service' ? 'Service enquiry' : 'Product enquiry')).toUpperCase(), style: label()),
                Text('${a['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
                if (a['price'] != null || (shared && a['seller'] != null))
                  Text(
                    [if (a['price'] != null) '${a['price']}', if (shared && a['seller'] != null) '${a['seller']}'].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg.withValues(alpha: .8)),
                  ),
              ]),
            ),
          ]),
        );
      case 'cart':
        final items = ((a['items'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        final n = items.fold<int>(0, (s, i) => s + ((i['qty'] as num?)?.toInt() ?? 1));
        return box(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              WIcon(WI.cart, size: 16, color: fg),
              const SizedBox(width: 6),
              Text('${t('Cart').toUpperCase()} · $n ${t(n == 1 ? 'item' : 'items')}', style: label().copyWith(color: fg.withValues(alpha: .8))),
            ]),
            const SizedBox(height: 6),
            for (final i in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Text('${i['qty']}×', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
                  const SizedBox(width: 8),
                  Flexible(child: Text('${i['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg))),
                  if (i['price'] != null) ...[const SizedBox(width: 8), Text('${i['price']}', style: TextStyle(fontSize: 12, color: fg.withValues(alpha: .8)))],
                ]),
              ),
          ]),
        );
      case 'document':
        final size = (a['size'] as num?)?.toDouble() ?? 0;
        final mb = size / 1024 / 1024;
        return box(
          onTap: () => launchUrl(Uri.parse(mediaUrl('${a['url']}')), mode: LaunchMode.externalApplication),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            WIcon(WI.file, size: 28, color: fg),
            const SizedBox(width: 12),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('${a['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
                Text(mb >= 1 ? '${mb.toStringAsFixed(1)} MB' : '${math.max(1, (size / 1024).round())} KB', style: TextStyle(fontSize: 12, color: fg.withValues(alpha: .7))),
              ]),
            ),
          ]),
        );
      case 'location':
        final lat = (a['lat'] as num).toDouble(), lng = (a['lng'] as num).toDouble();
        return GestureDetector(
          onTap: () => launchUrl(Uri.parse('https://www.google.com/maps?q=$lat,$lng'), mode: LaunchMode.externalApplication),
          child: Container(
            width: 224,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: p.canvas, borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              MapPreview(lat: lat, lng: lng),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  WIcon(WI.pin, size: 20, color: p.text),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${a['label'] ?? t('Shared location')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      Text(t('Tap to open in Maps'), style: TextStyle(fontSize: 12, color: p.text.withValues(alpha: .7))),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
        );
      default: // contact
        return box(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            WIcon(WI.phone, size: 28, color: fg),
            const SizedBox(width: 12),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('${a['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
                GestureDetector(
                  onTap: () => launchUrl(Uri(scheme: 'tel', path: '+91${a['phone']}')),
                  child: Text('+91 ${a['phone']}', style: TextStyle(fontSize: 14, color: fg, decoration: TextDecoration.underline, decorationColor: fg)),
                ),
              ]),
            ),
          ]),
        );
    }
  }

  Widget _pendingBox(Pal p) {
    final a = _pending!;
    final isPost = a['type'] == 'post';
    final items = ((a['items'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final title = isPost
        ? '${t(a['kind'] == 'ask' ? 'Replying to ask' : 'Replying to update')}${a['by'] != null ? ' · ${a['by']}' : ''}'
        : a['type'] == 'cart'
            ? t('Sending your cart · {n} items', {'n': items.fold<int>(0, (s, i) => s + ((i['qty'] as num?)?.toInt() ?? 1))})
            : t('Replying about {name}', {'name': '${a['name']}'});
    final sub = isPost ? '${a['title']}' : (a['type'] == 'cart' ? items.map((i) => '${i['qty']}× ${i['name']}').join(', ') : (a['price'] as String?));
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: WIcon(isPost ? WI.reply : WI.cart, size: 16, color: p.text)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            if (sub != null && sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.text.withValues(alpha: .8))),
            const SizedBox(height: 2),
            Text(t('Write a message and send it along.'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
        GestureDetector(onTap: () => setState(() => _pending = null), child: WIcon(WI.close, size: 16, color: p.text)),
      ]),
    );
  }

  Widget _replyBox(Pal p) {
    final r = _replyTo!;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        WIcon(WI.reply, size: 16, color: p.text),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('Replying to {name}', {'name': r.senderUid == _me ? t('yourself') : _peer.name}), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            Text(quoteText(r.text, r.kind), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.text.withValues(alpha: .8))),
          ]),
        ),
        GestureDetector(onTap: () => setState(() => _replyTo = null), child: WIcon(WI.close, size: 16, color: p.text)),
      ]),
    );
  }

  void _showInfo(Msg m) {
    final p = Pal.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: p.canvas,
      barrierColor: kInk.withValues(alpha: .6),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        Widget row(String label, DateTime? at, {bool last = false}) => Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: last ? null : BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
              child: Row(children: [
                Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                Text(at == null ? '—' : _dayTime(at), style: TextStyle(fontSize: 14, color: p.muted)),
              ]),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(t('Message info'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                GestureDetector(onTap: () => Navigator.pop(ctx), child: WIcon(WI.close, size: 24, color: p.text)),
              ]),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(8)),
                child: Text(quoteText(m.text, m.kind).isEmpty ? t('Message') : quoteText(m.text, m.kind), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
              ),
              const SizedBox(height: 8),
              row(t('Sent'), m.createdAt),
              row(t('Delivered to {name}', {'name': _peer.name}), m.deliveredAt),
              row(t('Read by {name}', {'name': _peer.name}), m.readAt, last: true),
            ]),
          ),
        );
      },
    );
  }

  // ---------- attach sheet (web attach-sheet.tsx) ----------
  void _openAttach() {
    final p = Pal.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.canvas,
      barrierColor: kInk.withValues(alpha: .6),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _AttachSheet(
        peerName: _peer.name,
        onSend: ({String? imageUrl, Map<String, dynamic>? attachment}) => _send(text: '', imageUrl: imageUrl, attachment: attachment),
      ),
    );
  }
}

/// Drag a message to the right to reply. Vertical scrolling is left alone.
class _SwipeToReply extends StatefulWidget {
  final VoidCallback onReply;
  final Widget child;
  const _SwipeToReply({required this.onReply, required this.child});
  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  static const _max = 72.0, _trigger = 56.0;
  double _dx = 0;
  bool _armed = false;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final k = math.min(1.0, _dx / _trigger);
    return GestureDetector(
      onHorizontalDragUpdate: (d) => setState(() {
        _dx = (_dx + d.delta.dx).clamp(0, _max);
        if (!_armed && _dx >= _trigger) {
          _armed = true;
          HapticFeedback.lightImpact();
        } else if (_dx < _trigger) {
          _armed = false;
        }
      }),
      onHorizontalDragEnd: (_) {
        if (_dx >= _trigger) widget.onReply();
        setState(() {
          _dx = 0;
          _armed = false;
        });
      },
      onHorizontalDragCancel: () => setState(() => _dx = 0),
      child: Stack(children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: Center(
            child: Opacity(
              opacity: k,
              child: Transform.scale(
                scale: .6 + k * .4,
                child: Container(width: 32, height: 32, decoration: BoxDecoration(color: p.chip, shape: BoxShape.circle), child: Center(child: WIcon(WI.reply, size: 16, color: p.text))),
              ),
            ),
          ),
        ),
        AnimatedContainer(
          duration: Duration(milliseconds: _dx == 0 ? 200 : 0),
          transform: Matrix4.translationValues(_dx, 0, 0),
          child: SizedBox(width: double.infinity, child: widget.child),
        ),
      ]),
    );
  }
}

typedef _SendAttachment = Future<void> Function({String? imageUrl, Map<String, dynamic>? attachment});

class _AttachSheet extends StatefulWidget {
  final String peerName;
  final _SendAttachment onSend;
  const _AttachSheet({required this.peerName, required this.onSend});
  @override
  State<_AttachSheet> createState() => _AttachSheetState();
}

class _AttachSheetState extends State<_AttachSheet> {
  String _mode = 'menu';
  String? _busy, _error;
  final _name = TextEditingController();
  final _phone = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _run(String label, Future<void> Function() fn) async {
    setState(() {
      _busy = label;
      _error = null;
    });
    try {
      await fn();
      if (mounted) Navigator.pop(context);
    } on PermissionNotGiven {
      // the pop-up already explained it; nothing more to say
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.isEmpty ? t('Could not send.') : '$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _media() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Pal.of(context).canvas,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const WIcon(WI.camera), title: Text(t('Camera')), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const WIcon(WI.imageAdd), title: Text(t('Gallery')), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (src == null || !mounted) return;
    if (src == ImageSource.camera && !await Permissions.ensure(context, Need.camera, reason: t('To take a photo and send it in this chat.'))) return;
    if (!mounted) return;
    final f = await ImagePicker().pickImage(source: src, imageQuality: 75, maxWidth: 1280);
    if (f == null || !mounted) return;
    final api = context.read<AuthProvider>().api;
    await _run('photo', () async => widget.onSend(imageUrl: await api.uploadImage(await f.readAsBytes(), f.name)));
  }

  Future<void> _document() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv']);
    if (f == null || !mounted) return;
    final api = context.read<AuthProvider>().api;
    await _run('document', () async {
      final bytes = await f.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) throw ApiException(t('File must be under 10 MB.'));
      final ext = (f.extension ?? '').toLowerCase();
      final mime = switch (ext) {
        'pdf' => 'application/pdf',
        'doc' => 'application/msword',
        'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xls' => 'application/vnd.ms-excel',
        'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'ppt' => 'application/vnd.ms-powerpoint',
        'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'csv' => 'text/csv',
        _ => 'text/plain',
      };
      final d = await api.upload('/media/file', bytes, f.name, mime);
      await widget.onSend(attachment: {'type': 'document', 'url': d['url'], 'name': d['name'] ?? f.name, 'size': d['size'] ?? bytes.length});
    });
  }

  Future<void> _location() => _run('location', () async {
        final h = await currentLocation(context, reason: t('To share your current location in this chat.'), source: 'chat');
        await widget.onSend(attachment: {'type': 'location', 'lat': h.lat, 'lng': h.lng, if (h.node.isNotEmpty) 'label': 'Near ${h.node}'});
      });

  Future<void> _pickContact() async {
    final picked = await Navigator.push<List<PickedContact>>(context, MaterialPageRoute(builder: (_) => ContactPicker(askerName: widget.peerName, forChat: true, maxSelect: 1)));
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() {
      _name.text = picked.first.name;
      final d = picked.first.phone.replaceAll(RegExp(r'\D'), '');
      _phone.text = d.length > 10 ? d.substring(d.length - 10) : d;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final auth = context.read<AuthProvider>();
    Widget tile(WI icon, String label, String busyKey, String busyLabel, VoidCallback onTap) => Material(
          color: p.chip,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _busy != null ? null : onTap,
            child: Opacity(
              opacity: _busy != null && _busy != busyKey ? .5 : 1,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  WIcon(icon, size: 28, color: p.text),
                  const SizedBox(height: 8),
                  Text(_busy == busyKey ? t(busyLabel) : t(label), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(t(_mode == 'menu' ? 'Share' : _mode == 'upi' ? 'Get paid by UPI' : 'Share a contact'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          GestureDetector(onTap: () => Navigator.pop(context), child: WIcon(WI.close, size: 24, color: p.text)),
        ]),
        const SizedBox(height: 12),
        if (_mode == 'menu')
          Column(children: [
            Row(children: [
              Expanded(child: tile(WI.camera, 'Media', 'photo', 'Sending…', _media)),
              const SizedBox(width: 12),
              Expanded(child: tile(WI.file, 'Document', 'document', 'Sending…', _document)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: tile(WI.pin, 'Location', 'location', 'Locating…', _location)),
              const SizedBox(width: 12),
              Expanded(child: tile(WI.refer, 'Contact', 'contact', 'Sending…', () => setState(() => _mode = 'contact'))),
            ]),
            const SizedBox(height: 12),
            tile(WI.rupee, 'UPI payment', 'upi', 'Sending…', () => setState(() => _mode = 'upi')),
          ])
        else if (_mode == 'upi')
          UpiRequestForm(
            onBack: () => setState(() => _mode = 'menu'),
            onSend: (att) => _run('upi', () => widget.onSend(attachment: att)),
          )
        else ...[
          if (auth.phone.length == 10 && auth.profile != null) ...[
            GoldButton(
              label: t('Share my contact'),
              wi: WI.phone,
              outlined: true,
              height: 44,
              onPressed: _busy != null ? null : () => _run('contact', () => widget.onSend(attachment: {'type': 'contact', 'name': auth.profile!.name, 'phone': auth.phone})),
            ),
            const SizedBox(height: 12),
          ],
          GoldButton(label: t('Pick from phonebook'), outlined: true, height: 44, onPressed: _pickContact),
          const SizedBox(height: 12),
          AppField(controller: _name, hint: t('Name'), onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          AppField(
            controller: _phone,
            hint: t('10-digit mobile number'),
            keyboard: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Row(children: [
            GoldButton(label: t('Back'), outlined: true, height: 44, onPressed: () => setState(() => _mode = 'menu')),
            const SizedBox(width: 8),
            Expanded(
              child: GoldButton(
                label: t('Send contact'),
                height: 44,
                loading: _busy == 'contact',
                onPressed: _name.text.trim().isEmpty || _phone.text.length < 10 || _busy != null
                    ? null
                    : () => _run('contact', () => widget.onSend(attachment: {'type': 'contact', 'name': _name.text.trim(), 'phone': _phone.text})),
              ),
            ),
          ]),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(fontSize: 14, color: p.danger))),
      ]),
    );
  }
}

/// Small OpenStreetMap preview with the place at the centre (web map-preview.tsx), built from plain
/// tiles so it is cheap in a chat thread. Attribution shown as OSM requires.
class MapPreview extends StatelessWidget {
  final double lat, lng;
  final int zoom;
  final double height;
  const MapPreview({super.key, required this.lat, required this.lng, this.zoom = 15, this.height = 128});

  @override
  Widget build(BuildContext context) {
    const tile = 256.0;
    final scale = tile * math.pow(2, zoom);
    final s = math.sin(lat * math.pi / 180);
    final px = (lng + 180) / 360 * scale;
    final py = (0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * scale;
    final tx = (px / tile).floor(), ty = (py / tile).floor();
    final ox = px - tx * tile, oy = py - ty * tile;
    final max = math.pow(2, zoom).toInt();
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ColoredBox(
        color: const Color(0xFFE5E3DF),
        child: LayoutBuilder(builder: (context, c) {
          final cx = c.maxWidth / 2, cy = c.maxHeight / 2;
          return Stack(clipBehavior: Clip.hardEdge, children: [
            for (var dy = -1; dy <= 1; dy++)
              for (var dx = -1; dx <= 1; dx++)
                if (ty + dy >= 0 && ty + dy < max)
                  Positioned(
                    left: cx + dx * tile - ox,
                    top: cy + dy * tile - oy,
                    width: tile,
                    height: tile,
                    child: Image.network(
                      'https://tile.openstreetmap.org/$zoom/${((tx + dx) % max + max) % max}/${ty + dy}.png',
                      headers: const {'User-Agent': 'WebWebAI/1.0 (ai.webweb.app)'},
                      errorBuilder: (_, __, ___) => const SizedBox(),
                    ),
                  ),
            Positioned(left: cx - 14, top: cy - 28, child: const WIcon(WI.pin, size: 28, color: Color(0xFFE53935), strokeWidth: 2.2)),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                color: Colors.white.withValues(alpha: .75),
                child: const Text('© OpenStreetMap', style: TextStyle(fontSize: 9, color: Color(0xFF333333))),
              ),
            ),
          ]);
        }),
      ),
    );
  }
}

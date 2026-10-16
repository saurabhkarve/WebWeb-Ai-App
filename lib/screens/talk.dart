import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../auth_provider.dart';
import '../call_manager.dart';
import '../location.dart';
import '../models.dart';
import '../notifications.dart';
import '../realtime.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/active_call_banner.dart';
import '../widgets/image_grid.dart';
import 'contact_picker.dart';
import 'find.dart' show FilterPill;
import 'profile.dart';

/// Opens (or creates) the 1:1 chat with [peer] and shows it.
Future<void> openChat(BuildContext context, Peer peer) async {
  final api = context.read<AuthProvider>().api;
  try {
    final id = (await api.post('/chats', {'userId': peer.uid}) as Map)['id'] as String;
    if (context.mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatThread(chatId: id, peer: peer)));
  } catch (e) {
    if (context.mounted) toast(context, '$e', error: true);
  }
}

Future<bool> confirmDeleteChat(BuildContext context, String name) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete chat?'),
      content: Text('Your chat with $name will be removed from your account. $name will still have their copy.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
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

// ---------- formatting helpers ----------
String _clock(BuildContext c, DateTime d) => TimeOfDay.fromDateTime(d).format(c);
bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String _dayLabel(DateTime d) {
  final now = DateTime.now();
  if (_sameDay(d, now)) return 'Today';
  if (_sameDay(d, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

String _listTime(BuildContext c, DateTime d) {
  final now = DateTime.now();
  if (_sameDay(d, now)) return _clock(c, d);
  if (_sameDay(d, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  return '${d.day}/${d.month}/${d.year % 100}';
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

class Ticks extends StatelessWidget {
  final Msg m;
  const Ticks(this.m, {super.key});
  @override
  Widget build(BuildContext context) {
    if (m.pending) return const Icon(Icons.access_time, size: 13, color: Color(0x991E1E1E));
    final read = m.readAt != null;
    return Icon(read || m.deliveredAt != null ? Icons.done_all : Icons.done, size: 16, color: read ? const Color(0xFF1B6FD6) : const Color(0x991E1E1E));
  }
}

// ============================ Talk tab ============================

class TalkScreen extends StatefulWidget {
  const TalkScreen({super.key});
  @override
  State<TalkScreen> createState() => _TalkScreenState();
}

class _TalkScreenState extends State<TalkScreen> {
  List<ChatSummary> _chats = [];
  List<CallLog> _calls = [];
  List<Profile> _people = [];
  bool _loading = true;
  String _filter = 'all';
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
    // safety net if the socket is down
    _poll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!context.read<RealtimeService>().connected) _load();
    });
  }

  Future<void> _load() async {
    try {
      final c = await _api.get('/chats') as List;
      final k = await _api.get('/app/calls') as List;
      if (!mounted) return;
      setState(() {
        _chats = c.map((e) => ChatSummary.fromJson(e as Map, _me)).toList();
        _calls = k.map((e) => CallLog.fromJson(e as Map)).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Everyone matching the search box (newest members when empty), so a new chat can be started.
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
        setState(() => _chats.removeWhere((x) => x.id == c.id));
        toast(context, 'Chat deleted');
      }
      return true;
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final rt = context.watch<RealtimeService>();
    final q = _q.text.trim().toLowerCase();
    final chats = _chats.where((c) {
      if (_filter == 'unread' && !c.unread) return false;
      if (q.isEmpty) return true;
      return '${c.peer.name} ${c.peer.company} ${c.lastMessage ?? ''}'.toLowerCase().contains(q);
    }).toList();
    final calls = _calls.where((c) => q.isEmpty || (c.peer?.name ?? '').toLowerCase().contains(q)).toList();
    final showCalls = _filter == 'calls';
    final chatted = _chats.map((c) => c.peer.uid).toSet();
    final morePeople = _people.where((u) => !chatted.contains(u.uid)).toList();

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: kGold,
        onRefresh: () async {
          await _load();
          await _loadPeople();
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
          Row(children: [
            const Expanded(child: Text('Talk', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700))),
            Container(width: 9, height: 9, decoration: BoxDecoration(color: rt.connected ? kGreen : Colors.orange, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(rt.connected ? 'Live' : 'Connecting…', style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
          Text('${_chats.length} ${_chats.length == 1 ? 'conversation' : 'conversations'}', style: TextStyle(color: p.muted, fontWeight: FontWeight.w500)),
          const SizedBox(height: 14),
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: p.field, borderRadius: BorderRadius.circular(30)),
            child: Row(children: [
              Icon(Icons.search, color: p.muted),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _q, onChanged: _onSearch, decoration: InputDecoration(hintText: 'Search people or messages', hintStyle: TextStyle(color: p.muted), border: InputBorder.none, isDense: true))),
            ]),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 42,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final e in {'all': 'All chats', 'unread': 'Unread', 'calls': 'Calls'}.entries)
                Padding(padding: const EdgeInsets.only(right: 8), child: FilterPill(label: e.value, selected: _filter == e.key, onTap: () => setState(() => _filter = e.key))),
            ]),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.all(40), child: PageLoader())
          else if (showCalls)
            if (calls.isEmpty) _empty(p, 'No calls yet', 'Open a chat and tap the call or video icon.') else for (final c in calls) _callTile(c, p)
          else ...[
            for (final c in chats) _chatTile(c, p),
            if (_filter == 'all' && morePeople.isNotEmpty) ...[
              Padding(padding: const EdgeInsets.only(top: 14, bottom: 4), child: Text(q.isEmpty ? 'START A NEW CHAT' : 'PEOPLE', style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .8))),
              for (final u in morePeople) _personTile(u, p),
            ],
            if (chats.isEmpty && (_filter != 'all' || morePeople.isEmpty))
              _empty(p, _filter == 'unread' ? 'No unread messages' : (q.isEmpty ? 'No messages yet' : 'No results'), _filter == 'unread' ? 'You are all caught up.' : (q.isEmpty ? 'Search for a person to start a chat.' : 'Try a different name.')),
          ],
        ]),
      ),
    );
  }

  Widget _empty(Pal p, String title, String sub) => DashedBox(
        radius: 18,
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        child: SizedBox(
          width: double.infinity,
          child: Column(children: [
            Container(width: 56, height: 56, decoration: BoxDecoration(color: kGold.withValues(alpha: .2), shape: BoxShape.circle), child: const Icon(Icons.forum_outlined, color: kGold)),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            const SizedBox(height: 4),
            Text(sub, textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontWeight: FontWeight.w500)),
          ]),
        ),
      );

  Widget _avatar(Peer u) {
    final on = context.read<RealtimeService>().isOnline(u.uid);
    return Stack(clipBehavior: Clip.none, children: [
      Avatar(name: u.name, photoUrl: u.photoUrl, ring: u.userType == 'entrepreneur'),
      if (on) Positioned(right: 0, bottom: 0, child: Container(width: 13, height: 13, decoration: BoxDecoration(color: kGreen, shape: BoxShape.circle, border: Border.all(color: Pal.of(context).canvas, width: 2)))),
    ]);
  }

  Widget _chatTile(ChatSummary c, Pal p) => Dismissible(
        key: ValueKey('chat-${c.id}'),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) => _deleteChat(c),
        background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), color: Colors.redAccent, child: const Icon(Icons.delete_outline, color: Colors.white)),
        child: ListTile(
          onLongPress: () => _deleteChat(c),
          contentPadding: EdgeInsets.zero,
          leading: _avatar(c.peer),
          title: Text(c.peer.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(c.lastMessage ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.unread ? p.text : p.muted, fontWeight: c.unread ? FontWeight.w700 : FontWeight.w500)),
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (c.lastMessageAt != null) Text(_listTime(context, c.lastMessageAt!), style: TextStyle(color: c.unread ? kGold : p.muted, fontSize: 12, fontWeight: FontWeight.w600)),
            if (c.unread) ...[const SizedBox(height: 6), Container(width: 11, height: 11, decoration: const BoxDecoration(gradient: kGoldGradient, shape: BoxShape.circle))],
          ]),
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatThread(chatId: c.id, peer: c.peer)));
            _load();
          },
        ),
      );

  Widget _personTile(Profile u, Pal p) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: _avatar(Peer.fromProfile(u)),
        title: Text(u.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('@${u.handle} · ${u.company} · ${u.location}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.call_outlined, color: kGold), onPressed: () => placeCall(context, Peer.fromProfile(u), false)),
          IconButton(icon: const Icon(Icons.chat_bubble_outline, color: kGold), onPressed: () async {
            await openChat(context, Peer.fromProfile(u));
            _load();
          }),
        ]),
        onTap: () async {
          await openChat(context, Peer.fromProfile(u));
          _load();
        },
      );

  Widget _callTile(CallLog c, Pal p) {
    final peer = c.peer;
    if (peer == null) return const SizedBox.shrink();
    final outgoing = c.callerUid == _me;
    final missed = !outgoing && c.status != 'completed';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _avatar(peer),
      title: Text(peer.name, style: TextStyle(fontWeight: FontWeight.w700, color: missed ? Colors.redAccent : null)),
      subtitle: Row(children: [
        Icon(outgoing ? Icons.call_made : (missed ? Icons.call_missed : Icons.call_received), size: 15, color: missed ? Colors.redAccent : kGreen),
        const SizedBox(width: 4),
        Flexible(child: Text('${_listTime(context, c.createdAt)} · ${callLabel(c, _me)}', overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted))),
      ]),
      trailing: IconButton(icon: Icon(c.video ? Icons.videocam_outlined : Icons.call_outlined, color: kGold), onPressed: () => placeCall(context, peer, c.video)),
      onTap: () => openChat(context, peer),
    );
  }
}

// ============================ Chat thread ============================

/// A row in the thread: a message or a call-log entry.
class _Item {
  final Msg? msg;
  final CallLog? call;
  _Item.msg(Msg m) : msg = m, call = null;
  _Item.call(CallLog c) : call = c, msg = null;
  DateTime get at => msg?.createdAt ?? call!.createdAt;
}

class ChatThread extends StatefulWidget {
  final String chatId;
  final Peer peer;
  const ChatThread({super.key, required this.chatId, required this.peer});
  @override
  State<ChatThread> createState() => _ChatThreadState();
}

class _ChatThreadState extends State<ChatThread> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<Msg> _msgs = [];
  List<CallLog> _calls = [];
  bool _typing = false;
  bool _uploading = false;
  bool _iAmTyping = false;
  Timer? _typingOff, _iTypingOff, _poll;
  StreamSubscription? _sub;
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
    // if the socket is down, fall back to polling like the web does
    _poll = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!_rt.connected) _loadNew();
    });
  }

  int get _lastId => _msgs.where((m) => !m.pending).fold(0, (a, m) => m.id > a ? m.id : a);

  Future<void> _load() async {
    try {
      final d = (await _api.get('/chats/${widget.chatId}/messages') as List).map((e) => Msg.fromJson(e as Map)).toList();
      final k = (await _api.get('/app/calls', {'peer': _peer.uid}) as List).map((e) => CallLog.fromJson(e as Map)).toList();
      if (!mounted) return;
      setState(() {
        _msgs = d;
        _calls = k;
      });
      _toBottom(jump: true);
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
      case 'delivered':
        if (e['chatId'] != widget.chatId) return;
        final ids = ((e['ids'] as List?) ?? []).map((x) => (x as num).toInt()).toSet();
        setState(() {
          for (final m in _msgs) {
            if (ids.contains(m.id)) m.deliveredAt ??= DateTime.now();
          }
        });
        break;
      case 'read':
        if (e['chatId'] != widget.chatId) return;
        final ids = ((e['ids'] as List?) ?? []).map((x) => (x as num).toInt()).toSet();
        setState(() {
          for (final m in _msgs) {
            if (ids.contains(m.id)) {
              m.readAt ??= DateTime.now();
              m.deliveredAt ??= DateTime.now();
            }
          }
        });
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

  Future<void> _send({String? text, String? imageUrl, Map<String, dynamic>? attachment}) async {
    final t = text ?? _input.text.trim();
    if (t.isEmpty && imageUrl == null && attachment == null) return;
    final tmp = 'tmp${DateTime.now().microsecondsSinceEpoch}';
    final pending = Msg(id: -DateTime.now().microsecondsSinceEpoch, senderUid: _me, text: t, imageUrl: imageUrl, attachment: attachment, createdAt: DateTime.now(), pending: true, tmpId: tmp);
    if (text == null) _input.clear();
    _setTyping(false);
    setState(() => _msgs = [..._msgs, pending]);
    _toBottom();
    try {
      final sent = Msg.fromJson(await _api.post('/chats/${widget.chatId}/messages', {'text': t, if (imageUrl != null) 'imageUrl': imageUrl, if (attachment != null) 'attachment': attachment}) as Map);
      if (!mounted) return;
      setState(() => _msgs = [for (final m in _msgs) m.tmpId == tmp ? sent : m]);
    } catch (e) {
      if (!mounted) return;
      setState(() => _msgs = _msgs.where((m) => m.tmpId != tmp).toList());
      if (text == null && imageUrl == null && attachment == null) _input.text = t; // give the text back so nothing is lost
      toast(context, '$e', error: true);
    }
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source, imageQuality: 75, maxWidth: 1280);
      if (file == null) return;
      setState(() => _uploading = true);
      final url = await _api.uploadImage(await file.readAsBytes(), file.name);
      if (mounted) setState(() => _uploading = false);
      await _send(text: '', imageUrl: url);
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        toast(context, 'Could not send image: $e', error: true);
      }
    }
  }

  /// Share contacts from the phone book (like WhatsApp): one message per contact.
  Future<void> _sendContacts() async {
    final picked = await Navigator.push<List<PickedContact>>(context, MaterialPageRoute(builder: (_) => ContactPicker(askerName: widget.peer.name, forChat: true)));
    for (final c in picked ?? const <PickedContact>[]) {
      await _send(text: '', attachment: {'type': 'contact', 'name': c.name.length > 60 ? c.name.substring(0, 60) : c.name, 'phone': _digits10(c.phone)});
    }
  }

  static String _digits10(String v) {
    final d = v.replaceAll(RegExp(r'\D'), '');
    return d.length > 10 ? d.substring(d.length - 10) : d;
  }

  Future<void> _sendLocation() async {
    try {
      final h = await currentLocation();
      await _send(text: '', attachment: {'type': 'location', 'lat': h.lat, 'lng': h.lng, if (h.node != 'Other') 'label': 'Near ${h.node}'});
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  void _showAttachSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _attachOption(Icons.camera_alt_outlined, 'Camera', () {
              Navigator.pop(ctx);
              _pickAndSendImage(ImageSource.camera);
            }),
            _attachOption(Icons.photo_library_outlined, 'Gallery', () {
              Navigator.pop(ctx);
              _pickAndSendImage(ImageSource.gallery);
            }),
            _attachOption(Icons.person_outline, 'Contact', () {
              Navigator.pop(ctx);
              _sendContacts();
            }),
            _attachOption(Icons.place_outlined, 'Location', () {
              Navigator.pop(ctx);
              _sendLocation();
            }),
          ]),
        ),
      ),
    );
  }

  Widget _attachOption(IconData icon, String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(padding: const EdgeInsets.all(14), decoration: const BoxDecoration(gradient: kGoldGradient, shape: BoxShape.circle), child: Icon(icon, color: Colors.black, size: 28)),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
        ),
      );

  void _setTyping(bool on) {
    if (on != _iAmTyping) {
      _iAmTyping = on;
      _rt.send({'type': 'typing', 'to': _peer.uid, 'chatId': widget.chatId, 'on': on});
    }
    _iTypingOff?.cancel();
    if (on) _iTypingOff = Timer(const Duration(seconds: 2), () => _setTyping(false));
  }

  @override
  void dispose() {
    if (NotificationService.activeChat == widget.chatId) NotificationService.activeChat = null;
    _setTyping(false);
    _sub?.cancel();
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
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: _peer.handle.isEmpty ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: _peer.handle))),
          child: Row(children: [
            Avatar(name: _peer.name, photoUrl: _peer.photoUrl, size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_peer.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                Text(_typing ? 'typing…' : (on ? 'online' : _peer.company), overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: _typing || on ? kGreen : p.muted, fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.videocam_outlined), onPressed: () => placeCall(context, _peer, true)),
          IconButton(icon: const Icon(Icons.call_outlined), onPressed: () => placeCall(context, _peer, false)),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v != 'delete') return;
              final yes = await confirmDeleteChat(context, _peer.name);
              if (!yes || !context.mounted) return;
              try {
                await _api.delete('/app/chats/${widget.chatId}');
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                if (context.mounted) toast(context, '$e', error: true);
              }
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete chat'))],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          const ActiveCallBanner(),
          if (_uploading) const LinearProgressIndicator(color: kGold, minHeight: 2),
          Expanded(
            child: items.isEmpty
                ? Center(child: Text('Say hello 👋', style: TextStyle(color: p.muted, fontWeight: FontWeight.w600)))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final it = items[i];
                      final showDay = i == 0 || !_sameDay(items[i - 1].at, it.at);
                      return Column(children: [if (showDay) _pill(_dayLabel(it.at), p), it.call != null ? _callRow(it.call!, p) : _bubble(it.msg!, p)]);
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.add_photo_alternate_outlined, color: kGold), onPressed: _showAttachSheet, tooltip: 'Attach'),
              Expanded(child: AppField(controller: _input, hint: 'Message', caps: TextCapitalization.sentences, onChanged: (v) => _setTyping(v.isNotEmpty), onSubmitted: (_) => _send())),
              const SizedBox(width: 8),
              InkWell(onTap: () => _send(), customBorder: const CircleBorder(), child: Container(width: 50, height: 50, decoration: const BoxDecoration(gradient: kGoldGradient, shape: BoxShape.circle), child: Icon(Icons.send_rounded, color: p.onGold, size: 21))),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _pill(String t, Pal p) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(10)), child: Text(t, style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w600))),
      );

  Widget _callRow(CallLog c, Pal p) {
    final mine = c.callerUid == _me;
    final missed = !mine && c.status != 'completed';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(c.video ? Icons.videocam_outlined : Icons.call_outlined, size: 17, color: missed ? Colors.redAccent : kGreen),
          const SizedBox(width: 8),
          Text('${callLabel(c, _me)}  ·  ${_clock(context, c.createdAt)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: missed ? Colors.redAccent : p.text)),
        ]),
      ),
    );
  }

  /// Contact / location / document attachments (sent from the app or the web).
  Widget _attachment(Map<String, dynamic> a, bool mine, Pal p) {
    final fg = mine ? p.onGold : p.text;
    switch (a['type']) {
      case 'contact':
        return InkWell(
          onTap: () => launchUrl(Uri(scheme: 'tel', path: '+91${a['phone']}')),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.call, size: 22, color: fg), const SizedBox(width: 10), Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${a['name']}', style: TextStyle(fontWeight: FontWeight.w700, color: fg)), Text('+91 ${a['phone']}', style: TextStyle(decoration: TextDecoration.underline, color: fg))]))]),
        );
      case 'location':
        return InkWell(
          onTap: () => launchUrl(Uri.parse('https://www.google.com/maps?q=${a['lat']},${a['lng']}'), mode: LaunchMode.externalApplication),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.place_outlined, size: 22, color: fg), const SizedBox(width: 10), Text('${a['label'] ?? 'Shared location'}', style: TextStyle(fontWeight: FontWeight.w700, color: fg))]),
        );
      default:
        return InkWell(
          onTap: () => launchUrl(Uri.parse(mediaUrl('${a['url']}')), mode: LaunchMode.externalApplication),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.insert_drive_file_outlined, size: 22, color: fg), const SizedBox(width: 10), Flexible(child: Text('${a['name']}', overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: fg)))]),
        );
    }
  }

  Widget _bubble(Msg m, Pal p) {
    final mine = m.senderUid == _me;
    final hasImage = m.imageUrl != null;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: hasImage ? const EdgeInsets.all(4) : const EdgeInsets.fromLTRB(12, 8, 10, 6),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
        decoration: BoxDecoration(
          gradient: mine ? kGoldGradient : null,
          color: mine ? null : p.card,
          border: mine ? null : Border.all(color: p.border),
          borderRadius: BorderRadius.only(topLeft: const Radius.circular(16), topRight: const Radius.circular(16), bottomLeft: Radius.circular(mine ? 16 : 4), bottomRight: Radius.circular(mine ? 4 : 16)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          if (hasImage)
            GestureDetector(
              onTap: () => openImageViewer(context, [m.imageUrl!], 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(mediaUrl(m.imageUrl!), width: 220, height: 200, fit: BoxFit.cover,
                    loadingBuilder: (_, child, prog) => prog == null ? child : Container(width: 220, height: 180, color: Colors.black12, child: const Center(child: LogoLoader(size: 36))),
                    errorBuilder: (_, __, ___) => Container(width: 220, height: 140, color: Colors.black12, child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)))),
              ),
            ),
          if (m.attachment != null) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: _attachment(m.attachment!, mine, p)),
          if (m.text.isNotEmpty)
            Padding(
              padding: hasImage ? const EdgeInsets.fromLTRB(8, 6, 8, 2) : EdgeInsets.zero,
              // no Align: the bubble hugs the text instead of stretching to the max width
              child: Text(m.text, style: TextStyle(color: mine ? p.onGold : p.text, fontSize: 15.5, fontWeight: FontWeight.w500)),
            ),
          const SizedBox(height: 2),
          Padding(
            padding: hasImage ? const EdgeInsets.only(right: 6, bottom: 4) : EdgeInsets.zero,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_clock(context, m.createdAt), style: TextStyle(fontSize: 11, color: mine ? const Color(0x991E1E1E) : p.muted)),
              if (mine) ...[const SizedBox(width: 3), Ticks(m)],
            ]),
          ),
        ]),
      ),
    );
  }
}

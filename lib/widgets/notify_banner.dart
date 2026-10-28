import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../i18n.dart';
import '../models.dart';
import '../notifications.dart';
import '../realtime.dart';
import '../screens/contact_picker.dart';
import '../screens/post_detail.dart';
import '../screens/talk.dart' show ChatThread;
import '../theme.dart';
import '../widgets.dart';
import 'response_sheet.dart';

/// The in-app notification while the app is open (web notify-banner.tsx): tap it to open what it is about. A chat
/// message also has a reply box, and a new ask from someone else has Reply and Refer, so neither needs a trip to the
/// page. It stays while something is typed or a sheet is open, and goes on its own otherwise. Mounted in the shell.
class NotifyBannerHost extends StatefulWidget {
  const NotifyBannerHost({super.key});
  @override
  State<NotifyBannerHost> createState() => _NotifyBannerHostState();
}

class _Banner {
  final String id, title, body;
  final String? chatId, postId, photo;
  final Peer? peer;
  _Banner({required this.id, required this.title, required this.body, this.chatId, this.postId, this.photo, this.peer});
}

class _NotifyBannerHostState extends State<NotifyBannerHost> {
  StreamSubscription<Map<String, dynamic>>? _sub;
  _Banner? _b;
  final _text = TextEditingController();
  final _focus = FocusNode();
  Timer? _timer;
  bool _busy = false, _sent = false, _sheet = false, _error = false;

  @override
  void initState() {
    super.initState();
    // the banner stands in for the system notification while the app is in front
    NotificationService.inAppBanners = true;
    _sub = context.read<RealtimeService>().events.listen(_onEvent);
    _focus.addListener(() => setState(_arm));
  }

  @override
  void dispose() {
    NotificationService.inAppBanners = false;
    _sub?.cancel();
    _timer?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _onEvent(Map<String, dynamic> e) async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final me = auth.profile?.uid;
    if (e['type'] == 'msg') {
      final m = Map<String, dynamic>.from(e['message'] as Map);
      final chatId = '${e['chatId']}';
      if (m['senderUid'] == me || NotificationService.activeChat == chatId) return;
      try {
        final c = ChatSummary.fromJson(await auth.api.get('/chats/$chatId') as Map, me ?? '');
        if (!mounted || NotificationService.activeChat == chatId) return;
        final text = '${m['text'] ?? ''}';
        _show(_Banner(id: 'msg-$chatId-${m['id']}', title: c.peer.shownName, body: text.isNotEmpty ? text : (m['imageUrl'] != null ? '📷' : ''), chatId: chatId, photo: c.peer.photoUrl, peer: c.peer));
      } catch (_) {}
    } else if (e['type'] == 'notify') {
      final data = Map<String, dynamic>.from((e['data'] as Map?) ?? {});
      final ask = e['kind'] == 'ask_match' || e['kind'] == 'alert_match';
      final postId = '${data['postId'] ?? ''}';
      _show(_Banner(id: '${e['id'] ?? DateTime.now().microsecondsSinceEpoch}', title: '${e['title'] ?? ''}', body: '${e['body'] ?? ''}', postId: ask && postId.isNotEmpty ? postId : null));
    }
  }

  void _show(_Banner b) {
    setState(() {
      _b = b;
      _text.clear();
      _busy = _sent = _sheet = _error = false;
      _arm();
    });
  }

  /// the timer runs only while nothing holds the banner
  void _arm() {
    _timer?.cancel();
    final b = _b;
    if (b == null) return;
    if (_busy || _sheet || _focus.hasFocus || _text.text.isNotEmpty) return;
    final ms = _sent ? 1800 : (b.chatId != null || b.postId != null ? 10000 : 6000);
    _timer = Timer(Duration(milliseconds: ms), () {
      if (mounted) setState(() => _b = null);
    });
  }

  void _open() {
    final b = _b;
    if (b == null) return;
    setState(() => _b = null);
    if (b.chatId != null && b.peer != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => ChatThread(chatId: b.chatId!, peer: b.peer!)));
    } else if (b.postId != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailScreen(postId: b.postId!)));
    }
  }

  Future<void> _send() async {
    final b = _b;
    final text = _text.text.trim();
    if (b?.chatId == null || text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = false;
    });
    try {
      await context.read<AuthProvider>().api.post('/chats/${b!.chatId}/messages', {'text': text});
      _focus.unfocus();
      if (mounted) {
        setState(() {
          _text.clear();
          _sent = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _arm();
        });
      }
    }
  }

  Future<void> _reply() async {
    final b = _b!;
    setState(() => _sheet = true);
    _timer?.cancel();
    final sent = await showResponseSheet(context, b.postId!);
    if (!mounted) return;
    setState(() {
      _sheet = false;
      if (sent) _b = null;
      _arm();
    });
  }

  Future<void> _refer() async {
    final b = _b!;
    final api = context.read<AuthProvider>().api;
    setState(() => _sheet = true);
    _timer?.cancel();
    var mine = 0;
    try {
      mine = ((await api.get('/app/posts/${b.postId}/referrals/mine')) as List).length;
    } catch (_) {}
    if (!mounted) return;
    final left = 5 - mine;
    if (left <= 0) {
      setState(() => _sheet = false);
      return toast(context, t('You can refer up to 5 contacts on one ask'));
    }
    final picked = await Navigator.push<List<PickedContact>>(context, MaterialPageRoute(builder: (_) => ContactPicker(askerName: b.body.split(' · ').first, maxSelect: left)));
    var ok = 0;
    String? err;
    for (final c in picked ?? const <PickedContact>[]) {
      try {
        await api.post('/posts/${b.postId}/refer', {'name': c.name, 'phone': c.phone});
        ok++;
      } catch (e) {
        err = '$e';
      }
    }
    if (!mounted) return;
    setState(() {
      _sheet = false;
      if (ok > 0) _b = null;
      _arm();
    });
    if (picked != null && picked.isNotEmpty) toast(context, ok > 0 ? t('Referral sent') : (err ?? t('Could not refer')), error: ok == 0);
  }

  @override
  Widget build(BuildContext context) {
    final b = _b;
    if (b == null) return const SizedBox.shrink();
    final p = Pal.of(context);
    Widget chip(String label, VoidCallback onTap, {bool gold = false}) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: gold ? kGold.withValues(alpha: .2) : null,
                border: Border.all(color: gold ? kGold.withValues(alpha: .5) : p.border),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.text)),
            ),
          ),
        );
    return Positioned(
      left: 12,
      right: 12,
      top: MediaQuery.of(context).padding.top + 8,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.border), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 6))]),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _open,
              child: Row(children: [
                Avatar(name: b.title, photoUrl: b.photo, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    if (b.body.isNotEmpty) Text(b.body, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted)),
                  ]),
                ),
              ]),
            ),
            if (b.chatId != null) ...[
              const SizedBox(height: 10),
              if (_sent)
                Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4), child: Text('✓ ${t('Sent')}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF059669))))
              else
                Row(children: [
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: TextField(
                        controller: _text,
                        focusNode: _focus,
                        maxLength: 2000,
                        textInputAction: TextInputAction.send,
                        onChanged: (_) => setState(_arm),
                        onSubmitted: (_) => _send(),
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: t('Write a reply…'),
                          hintStyle: TextStyle(color: p.muted),
                          counterText: '',
                          isDense: true,
                          filled: true,
                          fillColor: p.chip.withValues(alpha: .6),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: BorderSide(color: p.text)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _text.text.trim().isEmpty || _busy ? null : _send,
                    child: Opacity(
                      opacity: _text.text.trim().isEmpty || _busy ? .5 : 1,
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(99)),
                        child: Text(t('Send'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
                      ),
                    ),
                  ),
                ]),
              if (_error) Padding(padding: const EdgeInsets.only(top: 4, left: 4), child: Text(t('Could not send. Try again.'), style: TextStyle(fontSize: 12, color: p.danger))),
            ],
            if (b.postId != null) ...[
              const SizedBox(height: 10),
              Row(children: [chip(t('Reply'), _reply, gold: true), const SizedBox(width: 8), chip(t('Refer'), _refer)]),
            ],
          ]),
        ),
      ),
    );
  }
}

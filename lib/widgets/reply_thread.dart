import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'mention_suggest.dart';
import '../api.dart';
import '../auth_provider.dart';
import '../i18n.dart';
import '../links.dart';
import '../models.dart';
import '../screens/profile.dart';
import '../screens/talk.dart' show ChatThread;
import '../theme.dart';
import '../views.dart' show compactCount;
import '../widgets.dart';
import 'hashtag_text.dart';
import 'reaction_picker.dart';

const _bubble = BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(14), bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14));
const _rose = Color(0xFFF43F5E);

/// React on a reply (or a reply in its thread): the emoji once reacted, a heart before, and the count; rose while open.
class _ReactButton extends StatelessWidget {
  final String? value;
  final int count;
  final ValueChanged<String?> onChange;
  const _ReactButton({required this.value, required this.count, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return ReactionPicker(
      quick: true,
      value: value,
      onChange: onChange,
      trigger: (open) => Semantics(
        button: true,
        label: t('React'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(color: open ? _rose.withValues(alpha: .1) : null, borderRadius: BorderRadius.circular(99)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            value != null ? ReactionGlyph(value!, size: 13) : WIcon(WI.heart, size: 14, color: p.muted),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(compactCount(count), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: value != null ? p.text : p.muted)),
            ],
          ]),
        ),
      ),
    );
  }
}

Widget _textButton(BuildContext context, String label, VoidCallback onTap, {Color? color, WI? icon}) {
  final p = Pal.of(context);
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(99),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[WIcon(icon, size: 14, color: color ?? p.muted), const SizedBox(width: 4)],
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color ?? p.muted)),
      ]),
    ),
  );
}

/// A reply on an ask, as on x.com (and the web): react to it and reply to it from its name line (no extra row, to keep
/// the card short), and open the replies to it under the bubble (one level deep; replying to someone in the thread
/// starts the text with their @handle).
class ReplySocial extends StatefulWidget {
  final String postId;
  final ResponseLog reply;
  /// the name line (name, badge, time) and the reply itself (bubble, photo or the private-contact line)
  final List<Widget> meta;
  final Widget child;
  const ReplySocial({super.key, required this.postId, required this.reply, required this.meta, required this.child});
  @override
  State<ReplySocial> createState() => _ReplySocialState();
}

class _ReplySocialState extends State<ReplySocial> {
  late String? _mine = widget.reply.myReaction;
  late int _count = widget.reply.reactionsCount;
  late int _total = widget.reply.repliesCount;
  List<ReplyComment>? _thread;
  bool _open = false, _writing = false, _busy = false;
  final _text = TextEditingController();
  final _focus = FocusNode();

  Api get _api => context.read<AuthProvider>().api;
  String get _base => '/posts/${widget.postId}/replies/${widget.reply.uid}';

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = ((await _api.get('$_base/thread')) as List).map((e) => ReplyComment.fromJson(e as Map)).toList();
      if (mounted) {
        setState(() {
          _thread = list;
          _total = list.length;
        });
      }
    } catch (_) {}
  }

  Future<void> _react(String? next) async {
    final before = (_mine, _count);
    setState(() {
      _count += next != null && _mine == null ? 1 : next == null && _mine != null ? -1 : 0;
      _mine = next;
    });
    try {
      next == null ? await _api.delete('$_base/react') : await _api.post('$_base/react', {'type': next});
    } catch (_) {
      if (mounted) {
        setState(() {
          _mine = before.$1;
          _count = before.$2;
        });
      }
    }
  }

  void _write(String handle) {
    final me = context.read<AuthProvider>().profile?.handle;
    setState(() {
      _writing = true;
      _open = true;
      if (_text.text.trim().isEmpty) _text.text = handle.isNotEmpty && handle != me ? '@$handle ' : '';
    });
    if (_thread == null && _total > 0) _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      _text.selection = TextSelection.collapsed(offset: _text.text.length);
    });
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final c = ReplyComment.fromJson(await _api.post('$_base/thread', {'text': body}) as Map);
      if (!mounted) return;
      setState(() {
        _thread = [...?_thread, c];
        _total++;
        _text.clear();
        _writing = false;
      });
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(ReplyComment c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        content: Text(t('Delete this reply?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(t('Cancel'))),
          TextButton(onPressed: () => Navigator.pop(d, true), child: Text(t('Delete'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.delete('$_base/thread/${c.id}');
      if (mounted) {
        setState(() {
          _thread = _thread?.where((x) => x.id != c.id).toList();
          _total = _total > 0 ? _total - 1 : 0;
        });
      }
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final me = context.watch<AuthProvider>().profile;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // a chat bubble holding who and when on top (React and Reply at that line's end) and the reply under it, as on the web
      Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 4, 6),
        decoration: BoxDecoration(color: p.chip.withValues(alpha: .55), borderRadius: _bubble),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            ...widget.meta,
            if (me != null) ...[
              const SizedBox(width: 8),
              _ReactButton(value: _mine, count: _count, onChange: _react),
              _textButton(context, t('Reply'), () => _write(widget.reply.handle), icon: WI.reply),
            ],
          ]),
          Padding(padding: const EdgeInsets.only(right: 6), child: widget.child),
        ]),
      ),
      if (_total > 0)
        Transform.translate(
          offset: const Offset(-6, 0),
          child: _textButton(
            context,
            _open ? t('Hide replies') : t(_total == 1 ? 'View 1 reply' : 'View {n} replies', {'n': _total}),
            () {
              if (!_open && _thread == null) _load();
              setState(() => _open = !_open);
            },
            color: p.link,
          ),
        ),
      if (_open && (_thread?.isNotEmpty ?? false))
        for (final c in _thread!)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _ThreadReply(postId: widget.postId, replyUid: widget.reply.uid, c: c, mine: c.uid == me?.uid, onReply: () => _write(c.handle), onDelete: () => _delete(c)),
          ),
      if (_writing && me != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Avatar(name: me.name, photoUrl: me.photoUrl, size: 24, uid: me.uid),
            const SizedBox(width: 8),
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [TextField(
                controller: _text,
                focusNode: _focus,
                maxLength: 300,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: t('Write a reply…'),
                  counterText: '',
                  isDense: true,
                  filled: true,
                  fillColor: p.field,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(borderRadius: _bubble, borderSide: BorderSide(color: p.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: _bubble, borderSide: BorderSide(color: p.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: _bubble, borderSide: BorderSide(color: p.border)),
                ),
              ),
              MentionSuggest(controller: _text, focus: _focus),
            ]),
            ),
            const SizedBox(width: 8),
            ListenableBuilder(
              listenable: _text,
              builder: (_, __) => Opacity(
                opacity: _busy || _text.text.trim().isEmpty ? .4 : 1,
                child: InkWell(
                  onTap: _send,
                  borderRadius: BorderRadius.circular(99),
                  child: Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: kGold, borderRadius: BorderRadius.circular(99)),
                    child: Text(t('Reply'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kInk)),
                  ),
                ),
              ),
            ),
          ]),
        ),
    ]);
  }
}

class _ThreadReply extends StatefulWidget {
  final String postId, replyUid;
  final ReplyComment c;
  final bool mine;
  final VoidCallback onReply, onDelete;
  const _ThreadReply({required this.postId, required this.replyUid, required this.c, required this.mine, required this.onReply, required this.onDelete});
  @override
  State<_ThreadReply> createState() => _ThreadReplyState();
}

class _ThreadReplyState extends State<_ThreadReply> {
  late String? _mine = widget.c.myReaction;
  late int _count = widget.c.reactionsCount;

  Future<void> _react(String? next) async {
    final api = context.read<AuthProvider>().api;
    final before = (_mine, _count);
    setState(() {
      _count += next != null && _mine == null ? 1 : next == null && _mine != null ? -1 : 0;
      _mine = next;
    });
    final base = '/posts/${widget.postId}/replies/${widget.replyUid}/react';
    try {
      next == null ? await api.delete(base, {'commentId': '${widget.c.id}'}) : await api.post(base, {'type': next, 'commentId': widget.c.id});
    } catch (_) {
      if (mounted) {
        setState(() {
          _mine = before.$1;
          _count = before.$2;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final c = widget.c;
    void profile() => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: c.handle)));
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GestureDetector(onTap: profile, child: Avatar(name: c.display, photoUrl: c.photoUrl, size: 24, uid: c.uid)),
      const SizedBox(width: 8),
      Flexible(
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 4, 4, 6),
          decoration: BoxDecoration(color: p.chip.withValues(alpha: .55), borderRadius: _bubble),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: GestureDetector(onTap: profile, child: Text(c.display, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)))),
              if (c.verification > 0) ...[const SizedBox(width: 4), VerifiedBadge(level: c.verification, size: 12)],
              const SizedBox(width: 6),
              Text(timeAgo(c.createdAt), style: TextStyle(fontSize: 11, color: p.muted)),
              const SizedBox(width: 8),
              _ReactButton(value: _mine, count: _count, onChange: _react),
              _textButton(context, t('Reply'), widget.onReply, icon: WI.reply),
              if (widget.mine) _textButton(context, t('Delete'), widget.onDelete),
            ]),
            Padding(padding: const EdgeInsets.only(right: 6), child: HashtagText(c.text, style: const TextStyle(fontSize: 12, height: 1.35))),
            if (firstLink([c.text]) case final link?) Padding(padding: const EdgeInsets.only(right: 6), child: LinkPreviewCard(link, key: ValueKey(link), compact: true, margin: const EdgeInsets.only(top: 6))),
          ]),
        ),
      ),
    ]);
  }
}

/// Beside "Shared a contact privately": anyone but the replier and the asker can ask the replier for their number.
/// The request is a message in the chat with them, which they allow or reject there; once sent this opens that chat.
class RequestShare extends StatefulWidget {
  final String replyUid, askerUid;
  final String? postId;
  final Peer? peer;
  const RequestShare({super.key, required this.replyUid, required this.askerUid, this.postId, this.peer});
  @override
  State<RequestShare> createState() => _RequestShareState();
}

class _RequestShareState extends State<RequestShare> {
  String _state = 'idle';
  String? _chatId;

  Future<void> _send() async {
    setState(() => _state = 'busy');
    try {
      final r = await context.read<AuthProvider>().api.post('/users/${widget.replyUid}/contact-request', {if (widget.postId != null) 'postId': widget.postId});
      if (mounted) {
        setState(() {
          _state = 'sent';
          _chatId = (r is Map ? r['chatId'] : null) as String?;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _state = 'idle');
        toast(context, '$e', error: true);
      }
    }
  }

  void _openChat() {
    if (_chatId == null || widget.peer == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ChatThread(chatId: _chatId!, peer: widget.peer!)));
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final me = context.watch<AuthProvider>().profile?.uid;
    if (me == null || me == widget.replyUid || me == widget.askerUid) return const SizedBox.shrink();
    final sent = _state == 'sent';
    return Opacity(
      opacity: _state == 'busy' ? .7 : 1,
      // quiet, as on the web: the ask's own chips keep the gold on the card
      child: Material(
        color: p.canvas.withValues(alpha: .7),
        shape: StadiumBorder(side: BorderSide(color: p.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: _state == 'idle' ? _send : (sent ? _openChat : null),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 3, 10, 3),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              WIcon(WI.contactCard, size: 12, color: p.text.withValues(alpha: .75)),
              const SizedBox(width: 4),
              Text(sent ? (widget.peer != null && _chatId != null ? '${t('Requested')} · ${t('Open chat')}' : t('Requested')) : t('Request to share'),
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.text.withValues(alpha: .75))),
            ]),
          ),
        ),
      ),
    );
  }
}

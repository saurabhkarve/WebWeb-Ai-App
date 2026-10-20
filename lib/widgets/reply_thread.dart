import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../auth_provider.dart';
import '../i18n.dart';
import '../models.dart';
import '../screens/profile.dart';
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
      Row(children: [
        ...widget.meta,
        if (me != null) ...[
          const Spacer(),
          Transform.translate(
            offset: const Offset(6, 0),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _ReactButton(value: _mine, count: _count, onChange: _react),
              _textButton(context, t('Reply'), () => _write(widget.reply.handle), icon: WI.reply),
            ]),
          ),
        ],
      ]),
      widget.child,
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
              child: TextField(
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
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: GestureDetector(onTap: profile, child: Text(c.display, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))),
            if (c.verification > 0) ...[const SizedBox(width: 4), VerifiedBadge(level: c.verification, size: 13)],
            const SizedBox(width: 6),
            Text(timeAgo(c.createdAt), style: TextStyle(fontSize: 12, color: p.muted)),
            const Spacer(),
            Transform.translate(
              offset: const Offset(6, 0),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _ReactButton(value: _mine, count: _count, onChange: _react),
                _textButton(context, t('Reply'), widget.onReply, icon: WI.reply),
                if (widget.mine) _textButton(context, t('Delete'), widget.onDelete),
              ]),
            ),
          ]),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: p.chip, borderRadius: _bubble),
            child: HashtagText(c.text, style: const TextStyle(fontSize: 13, height: 1.35)),
          ),
        ]),
      ),
    ]);
  }
}

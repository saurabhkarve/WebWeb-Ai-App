import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../auth_provider.dart';
import '../config.dart';
import '../i18n.dart';
import '../models.dart';
import '../screens/profile.dart';
import '../theme.dart';
import '../widgets.dart';
import 'reaction_picker.dart' show ReactionGlyph;
import '../share_log.dart';

/// Full-screen update player (web update-viewer.tsx): tap right / left to move, auto-advances every
/// 5 s. Others' updates get a right rail (react, repost, share) and a message field that replies in
/// chat; your own show views and let you delete.
class StoryViewer extends StatefulWidget {
  final List<StoryGroup> groups;
  final int startGroup;
  final String? meUid;
  final void Function(String updateId)? onSeen;
  final Future<void> Function(String updateId)? onDelete;
  /// Loads the next page of people into [groups] (the same list) when the last loaded one is passed;
  /// resolves to how many were added (0: the end).
  final Future<int> Function()? onLoadMore;
  const StoryViewer({super.key, required this.groups, this.startGroup = 0, this.meUid, this.onSeen, this.onDelete, this.onLoadMore});
  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer> with SingleTickerProviderStateMixin {
  static const _duration = Duration(seconds: 5);
  late int _g = widget.startGroup;
  int _i = 0;
  late final AnimationController _progress = AnimationController(vsync: this, duration: _duration)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _next();
    });

  final _draft = TextEditingController();
  final _focus = FocusNode();
  bool _picker = false, _busy = false, _insightsOpen = false;
  Timer? _pickerTimer;
  String? _note;
  Timer? _noteTimer;
  final Set<String> _reposted = {};
  Map<String, dynamic>? _insights;

  StoryGroup get _group => widget.groups[_g];
  StoryItem get _item => _group.items[_i];
  bool get _mine => widget.meUid != null && _group.uid == widget.meUid;
  Api get _api => context.read<AuthProvider>().api;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_syncPause);
    _enter();
  }

  /// A new frame: count the view (others) or load insights (mine), mark it seen, restart the bar.
  void _enter() {
    _pickerTimer?.cancel();
    _picker = false;
    _insights = null;
    final it = _item;
    if (_mine) {
      _api.get('/updates/${it.id}/insights').then((d) {
        if (mounted && _item.id == it.id) setState(() => _insights = Map<String, dynamic>.from(d as Map));
      }).catchError((_) {});
    } else if (widget.meUid != null) {
      _api.post('/updates/${it.id}/view', {}).catchError((_) => null);
    }
    widget.onSeen?.call(it.id);
    _progress.forward(from: 0);
    _syncPause();
  }

  bool _away = false; // the author's page is open on top
  double _pullDown = 0; // swipe down to close: how far the screen follows the finger
  bool get _paused => _insightsOpen || _focus.hasFocus || _picker || _away;

  /// Tapping the author opens their page; the update waits and carries on when you come back.
  Future<void> _openAuthor(String handle) async {
    if (handle.isEmpty) return;
    setState(() => _away = true);
    _syncPause();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: handle)));
    if (!mounted) return;
    _away = false;
    _syncPause();
  }

  void _syncPause() {
    if (_paused) {
      _progress.stop();
    } else if (!_progress.isAnimating && _progress.value < 1) {
      _progress.forward();
    }
    if (mounted) setState(() {});
  }

  void _next() {
    if (_i < _group.items.length - 1) {
      setState(() => _i++);
    } else if (_g < widget.groups.length - 1) {
      setState(() {
        _g++;
        _i = 0;
      });
    } else if (widget.onLoadMore != null && !_loadingMore) {
      // swiped past the last loaded person: fetch the next page and carry on
      _loadingMore = true;
      _progress.stop();
      widget.onLoadMore!().then((added) {
        _loadingMore = false;
        if (!mounted) return;
        if (added > 0 && _g < widget.groups.length - 1) {
          setState(() {
            _g++;
            _i = 0;
          });
          _enter();
        } else {
          Navigator.of(context).maybePop();
        }
      });
      return;
    } else {
      if (!_loadingMore) Navigator.of(context).maybePop();
      return;
    }
    _enter();
  }

  bool _loadingMore = false;

  void _prev() {
    if (_i > 0) {
      setState(() => _i--);
    } else if (_g > 0) {
      setState(() {
        _g--;
        _i = 0;
      });
    }
    _enter();
  }

  void _flash(String s) {
    _noteTimer?.cancel();
    setState(() => _note = s);
    _noteTimer = Timer(const Duration(milliseconds: 1800), () => mounted ? setState(() => _note = null) : null);
  }

  void _openPicker() {
    _pickerTimer?.cancel();
    _picker = true;
    _pickerTimer = Timer(const Duration(seconds: 3), _closePicker);
    _syncPause();
  }

  void _closePicker() {
    _pickerTimer?.cancel();
    _picker = false;
    _syncPause();
  }

  Future<void> _react(String? type, {bool close = true}) async {
    if (close) _closePicker();
    final it = _item;
    final prev = it.myReaction, count = it.reactionsCount;
    setState(() {
      it.myReaction = type;
      it.reactionsCount = (count + (type != null && prev == null ? 1 : (type == null && prev != null ? -1 : 0))).clamp(0, 1 << 30);
    });
    try {
      type == null ? await _api.delete('/updates/${it.id}/react') : await _api.post('/updates/${it.id}/react', {'type': type});
    } catch (_) {
      if (!mounted) return;
      setState(() {
        it.myReaction = prev;
        it.reactionsCount = count;
      });
    }
  }

  Future<void> _repost() async {
    final it = _item;
    if (_reposted.contains(it.id)) return;
    try {
      await _api.post('/updates/${it.id}/repost', {});
      setState(() => _reposted.add(it.id));
      _flash(t('Reposted to your updates'));
    } catch (_) {
      _flash(t('Could not repost'));
    }
  }

  Future<void> _share() async {
    try {
      await shareAndLog(_api, entity: 'update', ref: _item.id, text: '$siteUrl/update/${_item.id}', subject: '${_group.shownName} · ${t('Update')}');
    } catch (_) {}
  }

  Future<void> _sendReply() async {
    final text = _draft.text.trim();
    if (text.isEmpty || _busy) return;
    final g = _group, it = _item;
    setState(() => _busy = true);
    try {
      final chatId = (await _api.post('/chats', {'userId': g.uid}) as Map)['id'] as String;
      final title = (it.text ?? '').isEmpty ? 'Update' : it.text!;
      await _api.post('/chats/$chatId/messages', {
        'text': text,
        'attachment': {
          'type': 'post',
          'postId': it.id,
          'kind': 'update',
          'title': title.length > 100 ? title.substring(0, 100) : title,
          if (it.imageUrl != null) 'imageUrl': it.imageUrl,
          'by': g.shownName,
          'path': '/update/${it.id}',
        },
      });
      _draft.clear();
      _focus.unfocus();
      _flash(t('Message sent'));
    } catch (_) {
      _flash(t('Could not send'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showInsights() async {
    _insightsOpen = true;
    _syncPause();
    final p = Pal.of(context);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.canvas,
      barrierColor: kInk.withValues(alpha: .6),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final views = (_insights?['views'] as num?)?.toInt() ?? 0;
        final viewers = ((_insights?['viewers'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .7),
          child: ListView(shrinkWrap: true, padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).padding.bottom + 24), children: [
            Row(children: [
              Expanded(child: Text(t('Insights'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
              GestureDetector(onTap: () => Navigator.pop(ctx), child: WIcon(WI.close, size: 24, color: p.text)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              WIcon(WI.eye, size: 20, color: p.text),
              const SizedBox(width: 8),
              Text('$views', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              Text(' ${t(views == 1 ? 'view' : 'views')}', style: const TextStyle(fontSize: 14)),
              Text(' · ${timeAgo(_item.createdAt)}', style: TextStyle(fontSize: 14, color: p.muted)),
            ]),
            const SizedBox(height: 12),
            if (_insights != null && viewers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(t('No views yet. Members see updates for 24 hours.'), textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: p.muted)),
              ),
            for (var k = 0; k < viewers.length; k++)
              Builder(builder: (_) {
                final v = viewers[k];
                final name = displayName('${v['userType']}', '${v['name']}', '${v['company'] ?? ''}');
                return InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: '${v['handle']}'))),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: k == 0 ? null : BoxDecoration(border: Border(top: BorderSide(color: p.border))),
                    child: Row(children: [
                      Avatar(name: name, photoUrl: v['photoURL'] as String?, size: 40, type: '${v['userType']}', badge: 16),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                            const SizedBox(width: 4),
                            VerifiedBadge(level: (v['verification'] as num?)?.toInt() ?? 0, size: 14),
                          ]),
                          Text('@${v['handle']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted)),
                        ]),
                      ),
                      Text(timeAgo(DateTime.fromMillisecondsSinceEpoch((v['viewedAt'] as num).toInt())), style: TextStyle(fontSize: 12, color: p.muted)),
                    ]),
                  ),
                );
              }),
          ]),
        );
      },
    );
    _insightsOpen = false;
    _syncPause();
  }

  @override
  void dispose() {
    _progress.dispose();
    _pickerTimer?.cancel();
    _noteTimer?.cancel();
    _focus.dispose();
    _draft.dispose();
    super.dispose();
  }

  Widget _railBtn({required Widget child, required String label, required VoidCallback onTap}) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: Container(width: 48, height: 48, alignment: Alignment.center, decoration: BoxDecoration(color: kInk.withValues(alpha: .35), shape: BoxShape.circle), child: child),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final g = _group, it = _item;
    final mine = _mine;
    final bottomInset = MediaQuery.of(context).padding.bottom + MediaQuery.of(context).viewInsets.bottom;
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: kInk,
      resizeToAvoidBottomInset: false,
      body: Transform.translate(
        offset: Offset(0, _pullDown),
        child: Opacity(
          opacity: (1 - _pullDown / 600).clamp(0.4, 1).toDouble(),
          child: Stack(children: [
            // content
            Positioned.fill(
              child: it.imageUrl != null
                  ? NetImg(it.imageUrl!, fit: BoxFit.contain, fallback: const SizedBox())
                  : Container(
                      decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF3A3A3A), kInk], begin: Alignment.topLeft, end: Alignment.bottomRight)),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(32),
                      child: Text(it.text ?? '', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700, height: 1.33)),
                    ),
            ),
            if (it.imageUrl != null && (it.text ?? '').isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 32 + 76 + bottomInset),
                  decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [kInk.withValues(alpha: .8), kInk.withValues(alpha: 0)])),
                  child: Text(it.text!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            // tap zones (previous = left third)
            Positioned(
              top: top + 72,
              bottom: 96 + bottomInset,
              left: 0,
              right: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  if (_focus.hasFocus) return _focus.unfocus();
                  if (_picker) return _closePicker();
                  d.localPosition.dx < MediaQuery.of(context).size.width / 3 ? _prev() : _next();
                },
                onLongPressStart: (_) => _progress.stop(),
                onLongPressEnd: (_) => _syncPause(),
                // swipe down closes the update (the screen follows the finger, then slides away)
                onVerticalDragStart: (_) => _progress.stop(),
                onVerticalDragUpdate: (d) => setState(() => _pullDown = (_pullDown + d.delta.dy).clamp(0, 1000).toDouble()),
                onVerticalDragEnd: (d) {
                  if (_pullDown > 110 || (d.primaryVelocity ?? 0) > 700) {
                    Navigator.of(context).maybePop();
                  } else {
                    setState(() => _pullDown = 0);
                    _syncPause();
                  }
                },
              ),
            ),
            // top bar: progress, author, delete / close
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(12, top + 12, 12, 24),
                decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [kInk.withValues(alpha: .6), kInk.withValues(alpha: 0)])),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  AnimatedBuilder(
                    animation: _progress,
                    builder: (_, __) => Row(children: [
                      for (var k = 0; k < g.items.length; k++) ...[
                        if (k > 0) const SizedBox(width: 4),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: k < _i ? 1 : (k == _i ? _progress.value : 0),
                              minHeight: 2,
                              backgroundColor: Colors.white.withValues(alpha: .3),
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    // author: opens their page
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Semantics(
                          button: true,
                          label: g.shownName,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _openAuthor(g.handle),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Avatar(name: g.shownName, size: 32, photoUrl: g.photoUrl, type: g.userType, badge: 14),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(mine ? t('Your update') : g.shownName,
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                              ),
                              if (!mine && g.verification > 0) ...[const SizedBox(width: 4), VerifiedBadge(level: g.verification, size: 14)],
                              const SizedBox(width: 8),
                              Text(timeAgo(it.createdAt), style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 12)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                    if (mine && widget.onDelete != null)
                      Semantics(
                        button: true,
                        label: t('Delete update'),
                        child: GestureDetector(
                          onTap: () async {
                            _progress.stop();
                            await widget.onDelete!(it.id);
                            if (context.mounted) Navigator.of(context).pop(true);
                          },
                          behavior: HitTestBehavior.opaque,
                          child: const SizedBox(width: 40, height: 40, child: Center(child: WIcon(WI.trash, size: 20, color: Colors.white))),
                        ),
                      ),
                    Semantics(
                      button: true,
                      label: t('Close'),
                      // 48 pt wide: centred on the same column as the react / repost / share buttons below
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.of(context).pop(),
                        child: const SizedBox(width: 48, height: 40, child: Center(child: WIcon(WI.close, size: 24, color: Colors.white))),
                      ),
                    ),
                  ]),
                  if (it.repostedFrom != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .15), borderRadius: BorderRadius.circular(20)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const WIcon(WI.repost, size: 14, color: Colors.white),
                          const SizedBox(width: 4),
                          Text('${t('Reposted from')} ${it.repostedFrom!['name']}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                ]),
              ),
            ),
            // right rail: react, repost, share
            Positioned(
              right: 12,
              bottom: 112 + bottomInset,
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (!mine)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_picker)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .2), borderRadius: BorderRadius.circular(30)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          for (final r in kReactions)
                            GestureDetector(
                              onTap: () => _react(it.myReaction == r ? null : r),
                              child: Container(
                                width: 40,
                                height: 40,
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(shape: BoxShape.circle, color: it.myReaction == r ? Colors.white.withValues(alpha: .3) : Colors.transparent),
                                child: ReactionGlyph(r, size: 24),
                              ),
                            ),
                        ]),
                      ),
                    _railBtn(
                      label: t('React'),
                      onTap: () {
                        if (it.myReaction == null) {
                          // first tap gives the default reaction and offers the others
                          _react('heart', close: false);
                          _openPicker();
                        } else if (_picker) {
                          _closePicker();
                        } else {
                          _openPicker();
                        }
                      },
                      child: it.myReaction != null ? ReactionGlyph(it.myReaction!, size: 24) : const WIcon(WI.heart, size: 28, color: Colors.white),
                    ),
                  ]),
                if (!mine) ...[
                  const SizedBox(height: 12),
                  _railBtn(
                    label: t('Repost'),
                    onTap: _repost,
                    child: _reposted.contains(it.id) ? const WIcon(WI.checkCircle, size: 28, color: Color(0xFF34D399)) : const WIcon(WI.repost, size: 28, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                ],
                _railBtn(label: t('Share'), onTap: _share, child: const WIcon(WI.share, size: 28, color: Colors.white)),
              ]),
            ),
            // bottom: message field (others) or insights (own)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(12, 32, 12, 36 + bottomInset),
                decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [kInk.withValues(alpha: .8), kInk.withValues(alpha: 0)])),
                child: mine
                    ? GestureDetector(
                        onTap: _showInsights,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: .15), borderRadius: BorderRadius.circular(30)),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const WIcon(WI.eye, size: 20, color: Colors.white),
                            const SizedBox(width: 8),
                            Text(
                              _insights == null ? t('Insights') : '${_insights!['views']} ${t((_insights!['views'] as num?) == 1 ? 'view' : 'views')}',
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                            ),
                            if (it.reactionsCount > 0) Text('  · ${it.reactionsCount} ❤️', style: TextStyle(color: Colors.white.withValues(alpha: .8), fontSize: 14, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.only(left: 16, right: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: Colors.white.withValues(alpha: .4)),
                        ),
                        child: Row(children: [
                          Expanded(
                            child: TextField(
                              controller: _draft,
                              focusNode: _focus,
                              maxLength: 500,
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (_) => _sendReply(),
                              textInputAction: TextInputAction.send,
                              cursorColor: Colors.white,
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                              decoration: InputDecoration(
                                hintText: t('Send message'),
                                hintStyle: TextStyle(color: Colors.white.withValues(alpha: .7)),
                                counterText: '',
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                isDense: true,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: _busy || _draft.text.trim().isEmpty ? null : _sendReply,
                            child: Opacity(
                              opacity: _busy || _draft.text.trim().isEmpty ? .4 : 1,
                              child: const SizedBox(width: 36, height: 36, child: Center(child: WIcon(WI.send, size: 20, color: Colors.white))),
                            ),
                          ),
                        ]),
                      ),
              ),
            ),
            if (_note != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 6 + bottomInset,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration:
                        BoxDecoration(color: Colors.white.withValues(alpha: .9), borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6)]),
                    child: Text(_note!, style: const TextStyle(color: kInk, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Bottom sheet to add an update (web update-composer.tsx): a photo, a caption, or both.
Future<bool?> showStoryComposer(BuildContext context) {
  final p = Pal.of(context);
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.canvas,
    barrierColor: kInk.withValues(alpha: .6),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => const _StoryComposer(),
  );
}

class _StoryComposer extends StatefulWidget {
  const _StoryComposer();
  @override
  State<_StoryComposer> createState() => _StoryComposerState();
}

class _StoryComposerState extends State<_StoryComposer> {
  final _text = TextEditingController();
  XFile? _file;
  bool _busy = false;
  String? _error;

  Future<void> _post() async {
    final api = context.read<AuthProvider>().api;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      String? url;
      if (_file != null) url = await api.uploadImage(await _file!.readAsBytes(), _file!.name);
      await api.post('/updates', {if (url != null) 'imageUrl': url, if (_text.text.trim().isNotEmpty) 'text': _text.text.trim()});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _pick() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1280, imageQuality: 75);
    if (f != null) setState(() => _file = f);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(t('Add an update'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          GestureDetector(onTap: () => Navigator.pop(context), child: WIcon(WI.close, size: 24, color: p.text)),
        ]),
        const SizedBox(height: 12),
        if (_file != null)
          GestureDetector(
            onTap: _pick,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 288),
                color: kInk,
                child: FutureBuilder(future: _file!.readAsBytes(), builder: (_, s) => s.hasData ? Image.memory(s.data!, fit: BoxFit.contain, width: double.infinity) : const SizedBox(height: 160)),
              ),
            ),
          )
        else
          DashedBox(
            onTap: _pick,
            radius: 8,
            padding: EdgeInsets.zero,
            child: SizedBox(
              height: 144,
              width: double.infinity,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                WIcon(WI.imageAdd, size: 32, color: p.muted),
                const SizedBox(height: 8),
                Text(t('Choose a photo (optional)'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.muted)),
              ]),
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          maxLength: 200,
          minLines: 2,
          maxLines: 4,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(
            hintText: t('Write something... (disappears in 24 hours)'),
            hintStyle: TextStyle(color: p.muted),
            counterText: '',
            filled: true,
            fillColor: p.field,
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.text)),
          ),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(fontSize: 12, color: p.danger))),
        const SizedBox(height: 12),
        GoldButton(label: t('Add update'), loading: _busy, onPressed: (_file != null || _text.text.trim().isNotEmpty) ? _post : null),
      ]),
    );
  }
}

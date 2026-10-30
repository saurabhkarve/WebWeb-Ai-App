import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../i18n.dart';
import '../screens/profile.dart';
import '../theme.dart';
import '../widgets.dart';

const kStar = Color(0xFFF5B301);

/// Five stars, [value] rounded to the nearest whole star.
class Stars extends StatelessWidget {
  final double value;
  final double size;
  const Stars({super.key, required this.value, this.size = 14});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var k = 1; k <= 5; k++) Icon(Icons.star_rounded, size: size, color: k <= value.round() ? kStar : p.text.withValues(alpha: .15)),
    ]);
  }
}

/// Reviews on a member's page (web reviews-section.tsx): the average and the spread, the reviews with the
/// member's replies, and the visitor's own review to write or change. GET/PUT/DELETE /users/:id/review(s).
class ReviewsCard extends StatefulWidget {
  final String uid, name;
  final bool own;
  const ReviewsCard({super.key, required this.uid, required this.name, required this.own});
  @override
  State<ReviewsCard> createState() => _ReviewsCardState();
}

class _ReviewsCardState extends State<ReviewsCard> {
  Map? _d;
  bool _all = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await context.read<AuthProvider>().api.get('/users/${widget.uid}/reviews', {'limit': '20'}) as Map;
      if (mounted) setState(() => _d = d);
    } catch (_) {
      if (mounted) setState(() => _d = const {'count': 0, 'avg': 0, 'dist': [0, 0, 0, 0, 0], 'reviews': []});
    }
  }

  Future<void> _write() async {
    final mine = _d?['mine'] as Map?;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.of(context).card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _ReviewSheet(uid: widget.uid, name: widget.name, rating: (mine?['rating'] as num?)?.toInt() ?? 0, text: '${mine?['text'] ?? ''}', exists: mine != null),
    );
    if (saved == true) _load();
  }

  Future<void> _reply(Map r) async {
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Reply')),
        content: TextField(controller: c, maxLength: 300, autofocus: true, decoration: InputDecoration(hintText: t('Thank them or answer'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(t('Reply'))),
        ],
      ),
    );
    if (text == null || text.isEmpty || !mounted) return;
    try {
      await context.read<AuthProvider>().api.put('/reviews/${r['id']}/reply', {'text': text});
      _load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final d = _d;
    if (d == null) return const SizedBox.shrink();
    final count = (d['count'] as num?)?.toInt() ?? 0;
    final avg = (d['avg'] as num?)?.toDouble() ?? 0;
    final dist = [for (final x in (d['dist'] as List? ?? const [0, 0, 0, 0, 0])) (x as num).toInt()];
    final most = dist.fold<int>(1, (a, b) => b > a ? b : a);
    final list = (d['reviews'] as List? ?? const []).cast<Map>();
    final mine = d['mine'] as Map?;
    final shown = _all ? list : list.take(3).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: p.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Column(children: [
            Text(count > 0 ? avg.toStringAsFixed(1) : '–', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, height: 1)),
            const SizedBox(height: 4),
            Stars(value: avg, size: 13),
            const SizedBox(height: 2),
            Text(t(count == 1 ? '{n} review' : '{n} reviews', {'n': count}), style: TextStyle(fontSize: 12, color: p.muted)),
          ]),
          const SizedBox(width: 18),
          Expanded(
            child: Column(children: [
              for (var s = 5; s >= 1; s--)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.5),
                  child: Row(children: [
                    SizedBox(width: 12, child: Text('$s', style: TextStyle(fontSize: 11, color: p.muted))),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(value: dist[s - 1] / most, minHeight: 6, backgroundColor: p.text.withValues(alpha: .08), color: kStar),
                      ),
                    ),
                  ]),
                ),
            ]),
          ),
        ]),
        if (!widget.own) ...[
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _write,
            icon: const Icon(Icons.star_outline_rounded, color: kStar),
            label: Text(mine == null ? t('Review {name}', {'name': widget.name}) : t('Change your review'), maxLines: 1, overflow: TextOverflow.ellipsis),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44), shape: const StadiumBorder(), foregroundColor: p.text, side: BorderSide(color: p.border)),
          ),
        ],
        if (count == 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(widget.own ? t('No reviews yet. Share your page with customers and ask them to review you.') : t('No reviews yet. Be the first to review.'), style: TextStyle(fontSize: 13, color: p.muted)),
          ),
        for (final r in shown) _row(p, r),
        if (list.length > 3 && !_all)
          TextButton(onPressed: () => setState(() => _all = true), child: Text(t('See all {n}', {'n': list.length}))),
      ]),
    );
  }

  Widget _row(Pal p, Map r) {
    final a = (r['author'] as Map?) ?? const {};
    final who = displayName('${a['userType'] ?? ''}', '${a['name'] ?? ''}', '${a['company'] ?? ''}');
    final reply = r['reply'] as String?;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: '${a['handle']}'))),
          child: Row(children: [
            Avatar(name: who, photoUrl: a['photoURL'] as String?, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(who, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                Stars(value: (r['rating'] as num).toDouble(), size: 11),
              ]),
            ),
          ]),
        ),
        if ((r['text'] as String? ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(r['text'] as String, style: const TextStyle(fontSize: 14, height: 1.4))),
        if ((reply ?? '').isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(10), border: const Border(left: BorderSide(color: kStar, width: 2))),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '${t('Reply from {name}', {'name': widget.name})} ', style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: reply),
            ]), style: const TextStyle(fontSize: 12.5, height: 1.4)),
          )
        else if (widget.own)
          GestureDetector(onTap: () => _reply(r), child: Padding(padding: const EdgeInsets.only(top: 6), child: Text(t('Reply'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.link)))),
      ]),
    );
  }
}

class _ReviewSheet extends StatefulWidget {
  final String uid, name, text;
  final int rating;
  final bool exists;
  const _ReviewSheet({required this.uid, required this.name, required this.rating, required this.text, required this.exists});
  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  late int _rating = widget.rating;
  late final _text = TextEditingController(text: widget.text);
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (_rating == 0) return setState(() => _error = t('Choose 1 to 5 stars'));
    setState(() => (_busy = true, _error = null));
    try {
      final text = _text.text.trim();
      await context.read<AuthProvider>().api.put('/users/${widget.uid}/review', {'rating': _rating, if (text.isNotEmpty) 'text': text});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => (_busy = false, _error = '$e'));
    }
  }

  Future<void> _delete() async {
    try {
      await context.read<AuthProvider>().api.delete('/users/${widget.uid}/review');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.exists ? t('Change your review') : t('Review {name}', {'name': widget.name}), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var k = 1; k <= 5; k++)
            IconButton(
              onPressed: () => setState(() => _rating = k),
              iconSize: 40,
              icon: Icon(k <= _rating ? Icons.star_rounded : Icons.star_outline_rounded, color: k <= _rating ? kStar : p.muted),
            ),
        ]),
        TextField(controller: _text, maxLength: 500, maxLines: 3, minLines: 2, decoration: InputDecoration(hintText: t('What was it like to work with them? (optional)'))),
        if (_error != null) Text(_error!, style: TextStyle(color: p.danger, fontSize: 13)),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy ? null : _save,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: kStar, foregroundColor: kInk, shape: const StadiumBorder()),
          child: Text(t('Post review'), style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        if (widget.exists) TextButton(onPressed: _delete, child: Text(t('Delete'), style: TextStyle(color: p.danger))),
      ]),
    );
  }
}

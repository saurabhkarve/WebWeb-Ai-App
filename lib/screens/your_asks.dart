import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ask_types.dart';
import '../auth_provider.dart';
import '../i18n.dart';
import '../realtime.dart';
import '../theme.dart';
import '../widgets.dart';
import 'post_detail.dart';

/// Home asks the Ask tab to open on "Your asks" (the pill beside the Asks heading); the Ask tab resets it.
final ValueNotifier<bool> yourAsksRequest = ValueNotifier(false);

/// One of my asks with what came in on it (GET /posts/mine/activity).
class MyAskActivity {
  final String id, title;
  final String? askType;
  final bool closed;
  final int replies, newReplies, referrals, newReferrals, reactions, views;
  final DateTime? lastAt, createdAt;
  MyAskActivity.fromJson(Map j)
      : id = '${j['id']}',
        title = '${j['title'] ?? ''}',
        askType = j['askType'] as String?,
        closed = j['closed'] == true,
        replies = (j['replies'] as num?)?.toInt() ?? 0,
        newReplies = (j['newReplies'] as num?)?.toInt() ?? 0,
        referrals = (j['referrals'] as num?)?.toInt() ?? 0,
        newReferrals = (j['newReferrals'] as num?)?.toInt() ?? 0,
        reactions = (j['reactions'] as num?)?.toInt() ?? 0,
        views = (j['views'] as num?)?.toInt() ?? 0,
        lastAt = j['lastAt'] is num ? DateTime.fromMillisecondsSinceEpoch((j['lastAt'] as num).toInt()) : null,
        createdAt = j['createdAt'] is num ? DateTime.fromMillisecondsSinceEpoch((j['createdAt'] as num).toInt()) : null;
  int get fresh => newReplies + newReferrals;
}

/// My asks with their activity, newest activity first; reloads when something lands and every so often.
mixin MyAskActivityLoader<T extends StatefulWidget> on State<T> {
  List<MyAskActivity>? asks;
  StreamSubscription? _rtSub;
  Timer? _tick;

  void initAskActivity() {
    loadAskActivity();
    _rtSub = context.read<RealtimeService>().events.listen((e) {
      if (e['type'] == 'notify') loadAskActivity();
    });
    _tick = Timer.periodic(const Duration(seconds: 60), (_) => loadAskActivity());
  }

  Future<void> loadAskActivity() async {
    try {
      final r = await context.read<AuthProvider>().api.get('/posts/mine/activity') as List;
      if (mounted) setState(() => asks = r.map((e) => MyAskActivity.fromJson(e as Map)).toList());
    } catch (_) {
      if (mounted && asks == null) setState(() => asks = []);
    }
  }

  void disposeAskActivity() {
    _rtSub?.cancel();
    _tick?.cancel();
  }
}

/// The Ask tab's second tab: each ask with its type icon, time and what came in (replies, referrals, reactions, views).
class YourAsksList extends StatelessWidget {
  final List<MyAskActivity>? asks;
  final Future<void> Function() onRefresh;
  const YourAsksList({super.key, required this.asks, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final items = asks;
    if (items == null) return const PageLoader();
    if (items.isEmpty) {
      return ListView(padding: const EdgeInsets.all(24), children: [
        const SizedBox(height: 40),
        Center(child: Text(t('You have not posted an ask yet'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text))),
        const SizedBox(height: 6),
        Center(child: Text(t('Post what you need and the replies will show up here.'), textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: p.muted))),
      ]);
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
        itemCount: items.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: p.border.withValues(alpha: .6)),
        itemBuilder: (_, i) => _AskRow(a: items[i]),
      ),
    );
  }
}

class _AskRow extends StatelessWidget {
  final MyAskActivity a;
  const _AskRow({required this.a});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final type = askTypeDef(a.askType);
    final when = a.lastAt ?? a.createdAt;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailScreen(postId: a.id, expandResponses: true))),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: a.fresh > 0 ? BoxDecoration(color: kGold.withValues(alpha: .08), borderRadius: BorderRadius.circular(12)) : null,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: kGold.withValues(alpha: .25), shape: BoxShape.circle),
            child: Center(child: WIcon(categoryIcon(type?.icon ?? 'other'), size: 20, color: p.dark ? kGold : const Color(0xFF7A5A00), still: true)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (when != null) Text(t(timeAgo(when)), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.muted)),
                if (a.closed) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(20)),
                    child: Text(t('Closed'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.muted)),
                  ),
                ],
              ]),
              const SizedBox(height: 2),
              Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, height: 1.25, fontWeight: a.fresh > 0 ? FontWeight.w800 : FontWeight.w700, color: p.text)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                _Chip(WI.talk, a.replies, a.newReplies),
                _Chip(WI.refer, a.referrals, a.newReferrals),
                _Chip(WI.thumbsUp, a.reactions, 0),
                _Chip(WI.views, a.views, 0),
              ]),
            ]),
          ),
          Padding(padding: const EdgeInsets.only(top: 10, left: 6), child: WIcon(WI.arrow, size: 16, color: p.muted, still: true)),
        ]),
      ),
    );
  }
}

/// A count in a small chip: gold when some of it is new, faded at zero.
class _Chip extends StatelessWidget {
  final WI icon;
  final int n, fresh;
  const _Chip(this.icon, this.n, this.fresh);
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final gold = fresh > 0;
    final fg = gold ? (p.dark ? kGold : const Color(0xFF7A5A00)) : (n > 0 ? p.text.withValues(alpha: .8) : p.muted.withValues(alpha: .7));
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: gold ? kGold.withValues(alpha: .25) : p.chip.withValues(alpha: n > 0 ? 1 : .5), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        WIcon(icon, size: 14, color: fg, still: true),
        const SizedBox(width: 4),
        Text('$n', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg, fontFeatures: const [FontFeature.tabularFigures()])),
        if (gold) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(color: kGold, borderRadius: BorderRadius.circular(20)),
            child: Text('+$fresh', style: const TextStyle(fontSize: 10, height: 1.5, fontWeight: FontWeight.w800, color: Color(0xFF1E1E1E))),
          ),
        ],
      ]),
    );
  }
}

/// Home: a small button at the end of the Asks heading to "Your asks", with how much is new. Nothing when I have asked nothing.
class YourAsksPill extends StatefulWidget {
  final VoidCallback onOpen;
  const YourAsksPill({super.key, required this.onOpen});
  @override
  State<YourAsksPill> createState() => _YourAsksPillState();
}

class _YourAsksPillState extends State<YourAsksPill> with MyAskActivityLoader {
  @override
  void initState() {
    super.initState();
    initAskActivity();
  }

  @override
  void dispose() {
    disposeAskActivity();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = asks;
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    final p = Pal.of(context);
    final fresh = items.fold<int>(0, (n, a) => n + a.fresh);
    return GestureDetector(
      onTap: () {
        yourAsksRequest.value = true;
        widget.onOpen();
      },
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: fresh > 0 ? kGold.withValues(alpha: .10) : p.canvas,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: fresh > 0 ? kGold.withValues(alpha: .6) : p.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(t('Your asks'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.text)),
          if (fresh > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFFE27A), kGold]), borderRadius: BorderRadius.circular(20)),
              child: Text(t('{n} new', {'n': '$fresh'}), style: const TextStyle(fontSize: 11, height: 1.45, fontWeight: FontWeight.w800, color: Color(0xFF1E1E1E))),
            ),
          ],
          const SizedBox(width: 6),
          WIcon(WI.arrow, size: 12, color: p.muted, still: true),
        ]),
      ),
    );
  }
}

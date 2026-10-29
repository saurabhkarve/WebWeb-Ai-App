import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart';
import '../i18n.dart';
import '../models.dart';
import '../icons.dart';
import '../theme.dart';

enum OptionState { open, other, mine, right, wrong }

/// The mark at the start of a poll or quiz option: an empty ring to tap before answering; after, a tick or cross.
class OptionMark extends StatelessWidget {
  final OptionState state;
  const OptionMark(this.state, {super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    if (state == OptionState.open || state == OptionState.other) {
      return Container(width: 22, height: 22, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: p.muted.withValues(alpha: state == OptionState.open ? .6 : .3), width: 2)));
    }
    final bg = state == OptionState.wrong ? const Color(0xFFEF4444) : (state == OptionState.right ? const Color(0xFF059669) : kGold);
    final fg = state == OptionState.mine ? kInk : Colors.white;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: state == OptionState.wrong ? Text('✕', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg)) : WIcon(WI.tick, size: 14, color: fg),
    );
  }
}

/// The options of a poll ask, tappable; after a vote (or on your own poll) the bars show what members chose.
class PollVote extends StatefulWidget {
  final Post post;
  final bool mine;
  final void Function(Post voted) onVoted;
  const PollVote({super.key, required this.post, required this.mine, required this.onVoted});
  @override
  State<PollVote> createState() => _PollVoteState();
}

class _PollVoteState extends State<PollVote> {
  bool _busy = false;

  Future<void> _vote(int o) async {
    if (_busy || widget.post.myVote != null || widget.mine || widget.post.closed) return;
    setState(() => _busy = true);
    try {
      final r = await context.read<AuthProvider>().api.post('/posts/${widget.post.id}/vote', {'option': o}) as Map;
      if (mounted) widget.onVoted(Post.fromJson(r));
    } catch (_) {} finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final post = widget.post;
    final voted = post.myVote != null;
    final show = voted || widget.mine || post.closed;
    final total = post.pollCounts.fold<int>(0, (a, b) => a + b);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t(show ? 'What members chose' : 'Choose one option').toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .4, color: p.muted)),
        const SizedBox(height: 6),
        for (var k = 0; k < post.pollOptions.length; k++)
          Builder(builder: (_) {
            final c = k < post.pollCounts.length ? post.pollCounts[k] : 0;
            final pct = total == 0 ? 0 : (c / total * 100).round();
            final mineK = post.myVote == k;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _vote(k),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: p.chip.withValues(alpha: .5), borderRadius: BorderRadius.circular(12), border: Border.all(color: mineK ? kGold : Colors.transparent, width: 2)),
                child: Stack(children: [
                  if (show)
                    Positioned.fill(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: pct / 100),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOut,
                        builder: (_, w, __) => FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: w, child: Container(color: kGold.withValues(alpha: .3))),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(children: [
                      OptionMark(mineK ? OptionState.mine : (show ? OptionState.other : OptionState.open)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(post.pollOptions[k], style: TextStyle(fontSize: 14, fontWeight: mineK ? FontWeight.w700 : FontWeight.w600))),
                      if (show) Text('$pct%', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ]),
              ),
            );
          }),
      ]),
    );
  }
}

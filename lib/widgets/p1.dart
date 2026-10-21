import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// P1 (docs/P1-MICRO-PLAN.md), as on the web: offers on replies, closed asks, "Did you find someone?" and the
/// winner's moment. Web: offer.tsx, ask-outcome.tsx.

const kGreen = Color(0xFF059669);
const kGreenDark = Color(0xFF34D399);

const kReadyLabel = {'today': 'Today', 'week': 'This week', 'month': 'This month'};

/// An ask is worth asking about a few days after it went up (the push comes at 3 days too).
bool outcomeDue(Post p) => p.isRequirement && !p.closed && DateTime.now().difference(p.createdAt).inDays >= 3;

/// Why an ask is a lead for this member (from the API, in English), in the member's language.
String leadReasonText(String reason) {
  final alert = RegExp(r'^Matches your alert: (.+)$').firstMatch(reason);
  if (alert != null) return t('Matches your alert: {label}', {'label': alert.group(1)!});
  final m = RegExp(r'^Matches your (.+) business$').firstMatch(reason);
  if (m != null) return t('Matches your {trade} business', {'trade': t(labelOf(kProfileCategories, m.group(1)))});
  return reason.split(' · ').map(t).join(' · ');
}

/// "I can do this" on a reply, with its price and when, as small chips. Nothing when the reply is not an offer.
class OfferChips extends StatelessWidget {
  final bool canDo;
  final String? quote, readyWhen;
  const OfferChips({super.key, this.canDo = false, this.quote, this.readyWhen});

  @override
  Widget build(BuildContext context) {
    if (!canDo && (quote ?? '').isEmpty && readyWhen == null) return const SizedBox.shrink();
    final p = Pal.of(context);
    final green = p.dark ? kGreenDark : kGreen;
    Widget chip(String text, {Color? bg, Color? fg, bool bold = true, Widget? lead}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: bg ?? p.chip, borderRadius: BorderRadius.circular(99)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (lead != null) ...[lead, const SizedBox(width: 3)],
            Text(text, style: TextStyle(fontSize: 11, fontWeight: bold ? FontWeight.w700 : FontWeight.w600, color: fg ?? p.text)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Wrap(spacing: 4, runSpacing: 4, children: [
        if (canDo) chip(t('Can do this'), bg: green.withValues(alpha: .12), fg: green, lead: WIcon(WI.check, size: 12, color: green)),
        if ((quote ?? '').isNotEmpty) chip(quote!),
        if (readyWhen != null && kReadyLabel[readyWhen] != null) chip(t(kReadyLabel[readyWhen]!), fg: p.muted, bold: false),
      ]),
    );
  }
}

/// How a closed ask reads: the winner sees "You won this job", everyone else that it was found on WEBWEB, or closed.
class ClosedChip extends StatelessWidget {
  final Post post;
  const ClosedChip(this.post, {super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final me = context.read<AuthProvider>().profile?.uid;
    final won = me != null && post.wonBy == me;
    final found = post.outcome == 'found_here';
    final green = p.dark ? kGreenDark : kGreen;
    final bg = won ? kGold.withValues(alpha: .3) : (found ? green.withValues(alpha: .12) : p.chip);
    final fg = won ? p.tagText : (found ? green : p.muted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(won ? '🏆 ${t('You won this job')}' : (found ? '✓ ${t('Found on WEBWEB')}' : t('Closed')),
          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

/// On a lead: how many have replied, and whether there is still room to be among the first.
class Competition extends StatelessWidget {
  final int replies;
  const Competition(this.replies, {super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final green = p.dark ? kGreenDark : kGreen;
    final text = replies == 0
        ? t('No replies yet · be the first')
        : replies < 3
            ? t('{n} replied · be among the first 3', {'n': replies})
            : t('{n} replied', {'n': replies});
    final dot = replies == 0 ? green : (replies < 3 ? kGold : p.muted.withValues(alpha: .5));
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Flexible(child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: replies == 0 ? green : p.muted))),
      ]),
    );
  }
}

/// My own open ask on the feed, a few days in: one quiet line that leads to the question.
class OutcomeNudge extends StatelessWidget {
  final Post post;
  final VoidCallback onTap;
  const OutcomeNudge({super.key, required this.post, required this.onTap});
  @override
  Widget build(BuildContext context) {
    if (!outcomeDue(post)) return const SizedBox.shrink();
    final p = Pal.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: kGold.withValues(alpha: .1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: kGold.withValues(alpha: .5))),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(children: [
              Expanded(child: Text(t('Did you find someone?'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
              Text('${t('Close this ask')} →', style: TextStyle(fontSize: 12, color: p.muted)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The winner's moment on the ask page.
class WinnerBanner extends StatelessWidget {
  final String ownerName;
  const WinnerBanner({super.key, required this.ownerName});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('🎉 ${t('You won this job')}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kInk)),
          const SizedBox(height: 2),
          Text(t('{name} chose you for this ask.', {'name': ownerName}), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kInk)),
          const SizedBox(height: 4),
          Text(t('It now counts on your profile as a deal won.'), style: const TextStyle(fontSize: 12, color: kInk)),
        ]),
      );
}

/// Someone who replied or referred, who the owner can say they chose.
class Responder {
  final String uid, name;
  final String? photoUrl;
  const Responder(this.uid, this.name, [this.photoUrl]);
}

/// The owner's "Did you find someone?" on their ask (web OutcomeCard): four answers; "Yes, on WEBWEB" then asks who,
/// and that member hears "You won this job". Once closed, it says how and offers Reopen.
class OutcomeCard extends StatefulWidget {
  final Post post;
  final List<Responder> responders;
  final bool prominent;
  final VoidCallback onChanged;
  const OutcomeCard({super.key, required this.post, required this.responders, this.prominent = false, required this.onChanged});
  @override
  State<OutcomeCard> createState() => _OutcomeCardState();
}

class _OutcomeCardState extends State<OutcomeCard> {
  bool _picking = false, _busy = false, _later = false;
  String? _winner, _error;

  Future<void> _run(Future<void> Function() fn) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await fn();
      if (!mounted) return;
      setState(() => _picking = false);
      widget.onChanged();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final api = context.read<AuthProvider>().api;
    final post = widget.post;
    final id = post.id;
    final green = p.dark ? kGreenDark : kGreen;

    if (post.closed) {
      final chosen = widget.responders.where((r) => r.uid == post.wonBy).firstOrNull;
      final how = post.outcome == 'found_here'
          ? (chosen != null ? t('You chose {name}', {'name': chosen.name}) : t('Found on WEBWEB'))
          : post.outcome == 'found_elsewhere'
              ? t('Found elsewhere')
              : t('No longer needed');
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: p.chip.withValues(alpha: .4), border: Border.all(color: p.border), borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          WIcon(WI.checkCircle, size: 24, color: green),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('This ask is closed'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              Text(how, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted)),
            ]),
          ),
          SizedBox(width: 96, child: GoldButton(label: t('Reopen'), outlined: true, height: 32, loading: _busy, onPressed: () => _run(() => api.delete('/posts/$id/outcome')))),
        ]),
      );
    }

    if (_later) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: p.border), borderRadius: BorderRadius.circular(18)),
        child: Text(t("Got it. We'll ask again in a week."), style: TextStyle(fontSize: 14, color: p.muted)),
      );
    }

    Widget answer(String key, String label) {
      final disabled = key == 'found_here' && widget.responders.isEmpty;
      return Expanded(
        child: GoldButton(
          label: t(label),
          height: 40,
          outlined: key != 'found_here',
          onPressed: _busy || disabled
              ? null
              : () {
                  if (key == 'found_here') {
                    setState(() => _picking = true);
                  } else if (key == 'later') {
                    _run(() async {
                      await api.post('/posts/$id/outcome/later', {});
                      if (mounted) setState(() => _later = true);
                    });
                  } else {
                    _run(() => api.post('/posts/$id/outcome', {'outcome': key}));
                  }
                },
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.prominent ? kGold.withValues(alpha: .1) : p.chip.withValues(alpha: .3),
        border: Border.all(color: widget.prominent ? kGold : p.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('Did you find someone?'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        Text(t('Closing your ask tells the person you chose, and stops new replies.'), style: TextStyle(fontSize: 12, color: p.muted)),
        const SizedBox(height: 12),
        if (!_picking) ...[
          Row(children: [answer('found_here', 'Yes, on WEBWEB'), const SizedBox(width: 8), answer('found_elsewhere', 'Yes, elsewhere')]),
          const SizedBox(height: 8),
          Row(children: [answer('later', 'Still looking'), const SizedBox(width: 8), answer('not_needed', 'No longer needed')]),
        ] else ...[
          Text(t('Who did you choose?'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final r in widget.responders)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: _winner == r.uid ? kGold.withValues(alpha: .15) : Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: _winner == r.uid ? kGold : p.border)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _winner = r.uid),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(children: [
                      Avatar(name: r.name, photoUrl: r.photoUrl, size: 32, uid: r.uid),
                      const SizedBox(width: 10),
                      Expanded(child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                      if (_winner == r.uid) WIcon(WI.checkCircle, size: 20, color: p.tagText),
                    ]),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: GoldButton(label: t('Back'), outlined: true, height: 40, onPressed: _busy ? null : () => setState(() => _picking = false))),
            const SizedBox(width: 8),
            Expanded(
              child: GoldButton(
                label: t('Confirm'),
                height: 40,
                loading: _busy,
                onPressed: _winner == null ? null : () => _run(() => api.post('/posts/$id/outcome', {'outcome': 'found_here', 'winnerUid': _winner})),
              ),
            ),
          ]),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(fontSize: 14, color: p.danger))),
      ]),
    );
  }
}

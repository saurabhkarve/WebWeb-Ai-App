import 'dart:async';
import 'dart:math' as math;
import 'package:share_plus/share_plus.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../auth_provider.dart';
import '../i18n.dart';
import '../models.dart';
import '../notifications.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/city_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart' show siteUrl;
import '../views.dart';
import '../widgets/area_map.dart' show askTimeLeft;
import '../widgets/p1.dart' show kGreenDark, leadReasonText;
import '../widgets/tour.dart' show Tours;
import 'find.dart';
import 'profile.dart';
import 'talk.dart' show ChatThread;
import 'leads.dart';
import 'post_detail.dart';

/// P2 (docs/P2-MICRO-PLAN.md), as on the web: Today in your area with Today's question (components/today.tsx,
/// /today), alerts for new asks (components/alert-sheet.tsx, /alerts) and the push nudge (components/push-nudge.tsx).

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _icon = {'rates': '📈', 'notice': '⚠', 'tender': '📄', 'event': '📅'};
const _typeLabel = {'rates': 'Rates', 'notice': 'Notice', 'tender': 'Tender / scheme', 'event': 'Event'};
const _amber = Color(0xFFB45309);
const _amberDark = Color(0xFFFBBF24);

DateTime _ymd(String d) => DateTime.parse('${d}T12:00:00Z');
String _ymdOf(DateTime d) => d.toIso8601String().substring(0, 10);

/// "Wed, 21 Oct"
String dayLabel(String day) {
  final d = _ymd(day);
  return '${t(_days[d.weekday - 1])}, ${d.day} ${t(_months[d.month - 1])}';
}

/// An item's title and body in the member's language, when the team wrote one.
({String title, String? body}) _text(TodayItem it) {
  final tx = it.i18n[currentLang] as Map?;
  return (title: (tx?['title'] as String?)?.isNotEmpty == true ? tx!['title'] as String : it.title, body: (tx?['body'] as String?)?.isNotEmpty == true ? tx!['body'] as String : it.body);
}

String _question(Poll p) => ((p.i18n[currentLang] as Map?)?['question'] as String?)?.isNotEmpty == true ? (p.i18n[currentLang] as Map)['question'] as String : p.question;

String _money(num? n) {
  if (n == null) return '';
  final s = n.round().toString();
  if (s.length <= 3) return '₹$s';
  // Indian grouping: 1,00,000
  final last = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '₹${parts.join(',')},$last';
}

Future<void> openToday(BuildContext context, {String? poll}) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => SubPage(title: t('Today in your area'), body: TodayScreen(poll: poll))));
Future<void> openAlerts(BuildContext context) => Navigator.push(context, MaterialPageRoute(builder: (_) => SubPage(title: t('Alerts'), body: const AlertsScreen())));

// ===================== Today =====================

/// A rate with its move: green up, red down.
class RatePill extends StatelessWidget {
  final Rate r;
  const RatePill(this.r, {super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final c = r.change ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: p.card.withValues(alpha: .8), border: Border.all(color: p.border), borderRadius: BorderRadius.circular(99)),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '${r.name} ', style: TextStyle(color: p.muted)),
          TextSpan(text: r.value, style: const TextStyle(fontWeight: FontWeight.w700)),
          if ((r.unit ?? '').isNotEmpty) TextSpan(text: '/${r.unit!.replaceFirst(RegExp(r'^/'), '')}', style: TextStyle(color: p.muted)),
          if (c > 0) TextSpan(text: ' ▲${c.abs()}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.dark ? kGreenDark : kGreen)),
          if (c < 0) TextSpan(text: ' ▼${c.abs()}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.danger)),
        ]),
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}

/// Today in your area: everything the team published for the member's city today (rates first, then what's
/// nearest), and Today's question. Up to 7 days back; opening it clears the dot on Connect.
class TodayScreen extends StatefulWidget {
  final String? poll;
  const TodayScreen({super.key, this.poll});
  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  String? _day;
  TodayFeed? _feed;

  @override
  void initState() {
    super.initState();
    _load();
    context.read<AuthProvider>().api.post('/today/seen').catchError((_) => null);
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    try {
      final f = TodayFeed.fromJson(await api.get('/today', {if (_day != null) 'day': _day, if (widget.poll != null) 'poll': widget.poll}) as Map);
      if (mounted) setState(() => _feed = f);
    } catch (_) {
      if (mounted) setState(() => _feed = const TodayFeed());
    }
  }

  void _go(String? day) {
    setState(() => _day = day);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final feed = _feed;
    if (feed == null) return const PageLoader();
    if (feed.cluster == null) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        EmptyState(title: t("Today isn't in your area yet"), hint: t("We're starting with Navi Mumbai. Set your city on your profile to get it when it reaches you.")),
      ]);
    }
    final today = feed.today!;
    final shown = feed.day ?? today;
    final oldest = _ymdOf(_ymd(today).subtract(const Duration(days: 7)));
    String shift(int n) => _ymdOf(_ymd(shown).add(Duration(days: n)));
    return LogoRefresh(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, islandSpace(context)),
        children: [
          Row(children: [
            Expanded(child: Text('☀ ${t('Today in {place}', {'place': feed.cluster!})}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            IconButton(
              tooltip: t('Previous day'),
              visualDensity: VisualDensity.compact,
              onPressed: shown.compareTo(oldest) <= 0 ? null : () => _go(shift(-1)),
              icon: Text('‹', style: TextStyle(fontSize: 22, color: shown.compareTo(oldest) <= 0 ? p.border : p.text)),
            ),
            Text(shown == today ? t('Today') : dayLabel(shown), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            IconButton(
              tooltip: t('Next day'),
              visualDensity: VisualDensity.compact,
              onPressed: shown.compareTo(today) >= 0 ? null : () => _go(shift(1).compareTo(today) >= 0 ? null : shift(1)),
              icon: Text('›', style: TextStyle(fontSize: 22, color: shown.compareTo(today) >= 0 ? p.border : p.text)),
            ),
          ]),
          Text(
            shown != today && _day == null ? t("Nothing new yet today: this is yesterday's.") : t('Rates, notices, tenders and events for businesses near you. New every morning.'),
            style: TextStyle(fontSize: 14, color: p.muted),
          ),
          if (feed.poll != null) ...[const SizedBox(height: 16), PollCard(key: ValueKey(feed.poll!.id), poll: feed.poll!)],
          if (feed.items.isEmpty)
            EmptyState(title: t('Nothing here yet for this day'), hint: t('Check back after 10 am.'))
          else
            for (var i = 0; i < feed.items.length; i++) ...[
              if (i > 0) Divider(height: 1, color: p.border),
              _ItemRow(key: ValueKey(feed.items[i].id), it: feed.items[i], onChange: _load),
            ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(t('Something to add for your area? ') + t('Tell us'), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.muted)),
          ),
        ],
      ),
    );
  }
}

/// One item on the Today page, with Useful / Interested and Outdated or wrong.
class _ItemRow extends StatefulWidget {
  final TodayItem it;
  final VoidCallback onChange;
  const _ItemRow({super.key, required this.it, required this.onChange});
  @override
  State<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends State<_ItemRow> {
  late final Set<String> _marked = {...widget.it.marked};
  late int _interested = widget.it.interested;

  Future<void> _toggle(String kind) async {
    final api = context.read<AuthProvider>().api;
    final on = !_marked.contains(kind);
    setState(() {
      on ? _marked.add(kind) : _marked.remove(kind);
      if (kind == 'interested') _interested += on ? 1 : -1;
    });
    try {
      on ? await api.post('/today/items/${widget.it.id}/mark', {'kind': kind}) : await api.delete('/today/items/${widget.it.id}/mark', {'kind': kind});
    } catch (_) {}
    if (kind == 'outdated') widget.onChange();
  }

  String? _daysLeft(String? deadline) {
    if (deadline == null) return null;
    final end = DateTime.parse('${deadline}T23:59:59+05:30');
    final d = (end.difference(DateTime.now()).inHours / 24).ceil();
    if (d < 0) return t('Closed');
    if (d == 0) return t('Closes today');
    return t(d == 1 ? '1 day left' : '{n} days left', {'n': d});
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final it = widget.it;
    final x = _text(it);
    final pl = it.payload;
    final amber = p.dark ? _amberDark : _amber;
    Widget mark(String kind, String label) {
      final on = _marked.contains(kind);
      return GestureDetector(
        onTap: () => _toggle(kind),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: on ? kGold.withValues(alpha: .2) : null, border: Border.all(color: on ? kGold : p.border), borderRadius: BorderRadius.circular(99)),
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      );
    }

    final left = it.type == 'tender' ? _daysLeft(pl['deadline'] as String?) : null;
    return Container(
      color: it.type == 'notice' ? kGold.withValues(alpha: .07) : null,
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('${_icon[it.type]} ', style: const TextStyle(fontSize: 13)),
          Text(t(_typeLabel[it.type] ?? '').toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .4, color: p.muted)),
          if (it.type == 'notice' && pl['when'] != null) Text(' · ${pl['when']}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: amber)),
          if (it.type == 'event' && pl['startsAt'] != null) Text(' · ${pl['startsAt']}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.link)),
          if (left != null)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: amber.withValues(alpha: .15), borderRadius: BorderRadius.circular(99)),
              child: Text(left, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: amber)),
            ),
          Expanded(child: Text(it.source ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: p.muted))),
        ]),
        const SizedBox(height: 4),
        Text(x.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        if (it.type == 'rates')
          for (final r in it.rates)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border.withValues(alpha: .6)))),
              child: Row(children: [
                Expanded(child: Text(r.name, style: const TextStyle(fontSize: 14))),
                Text.rich(TextSpan(children: [
                  TextSpan(text: r.value, style: const TextStyle(fontWeight: FontWeight.w700)),
                  if ((r.unit ?? '').isNotEmpty) TextSpan(text: '/${r.unit!.replaceFirst(RegExp(r'^/'), '')}', style: TextStyle(color: p.muted)),
                ]), style: const TextStyle(fontSize: 14)),
                SizedBox(
                  width: 52,
                  child: Text(
                    (r.change ?? 0) > 0 ? '▲ ${r.change!.abs()}' : (r.change ?? 0) < 0 ? '▼ ${r.change!.abs()}' : '–',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: (r.change ?? 0) > 0 ? (p.dark ? kGreenDark : kGreen) : (r.change ?? 0) < 0 ? p.danger : p.muted),
                  ),
                ),
              ]),
            ),
        if ((x.body ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(x.body!, style: TextStyle(fontSize: 14, color: p.text.withValues(alpha: .8)))),
        if (it.type == 'tender' && pl['who'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${t('Who can apply')}: ${pl['who']}', style: TextStyle(fontSize: 12, color: p.muted))),
        if (it.type == 'event' && pl['venue'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('📍 ${pl['venue']}', style: TextStyle(fontSize: 12, color: p.muted))),
        const SizedBox(height: 10),
        Row(children: [
          it.type == 'event'
              ? mark('interested', '${_marked.contains('interested') ? '★' : '☆'} ${t('Interested')}${_interested > 0 ? ' · $_interested' : ''}')
              : mark('useful', '👍 ${t('Useful')}'),
          const Spacer(),
          GestureDetector(
            onTap: () => _toggle('outdated'),
            child: Text(_marked.contains('outdated') ? t('Marked outdated') : t('Outdated or wrong?'), style: TextStyle(fontSize: 12, color: p.muted)),
          ),
        ]),
      ]),
    );
  }
}

/// Today's question: a rate check (type a number) or a poll (tap an option). The result shows only after answering,
/// and only from 5 answers; that's the reward.
class PollCard extends StatefulWidget {
  final Poll poll;
  /// without its own frame and label, inside a story card
  final bool bare;
  const PollCard({super.key, required this.poll, this.bare = false});
  @override
  State<PollCard> createState() => _PollCardState();
}

class _PollCardState extends State<PollCard> {
  late Poll _poll = widget.poll;
  final _value = TextEditingController();
  bool _busy = false;
  int? _picked;
  String? _error;

  static const _letters = ['A', 'B', 'C', 'D'];

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Future<void> _send({int? option, num? value}) async {
    setState(() {
      _busy = true;
      _picked = option;
      _error = null;
    });
    try {
      final r = Poll.fromJson(await context.read<AuthProvider>().api.post('/polls/${_poll.id}/answer', {if (option != null) 'option': option, if (value != null) 'value': value}) as Map);
      if (mounted) setState(() => _poll = r);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _picked = null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "Closes in 3 hr" for the strip under the question
  String _closesIn() {
    final left = _poll.closesAt.difference(DateTime.now());
    if (left.isNegative) return t('Closed');
    if (left.inHours >= 48) return t('Closes in {n} days', {'n': (left.inHours / 24).round()});
    if (left.inMinutes >= 60) return t('Closes in {n} hr', {'n': (left.inMinutes / 60).round()});
    return t('Closes in {n} min', {'n': left.inMinutes < 1 ? 1 : left.inMinutes});
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final q = _poll;
    final res = q.result;
    final open = !q.answered && !q.closed;
    final bare = widget.bare;
    final answers = t(q.answers == 1 ? '1 answer' : '{n} answers', {'n': q.answers});
    return Container(
      padding: bare ? EdgeInsets.zero : const EdgeInsets.all(16),
      decoration: bare ? null : BoxDecoration(color: kGold.withValues(alpha: .05), border: Border.all(color: kGold.withValues(alpha: .5)), borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // a story card names it in its own strip
        if (!bare) ...[
          Text('❓ ${t(q.kind == 'rate' ? 'Rate check' : "Today's question").toUpperCase()}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .4, color: p.tagText)),
          const SizedBox(height: 4),
        ],
        Text(_question(q), style: bare ? const TextStyle(fontSize: 22, height: 1.2, fontWeight: FontWeight.w800) : const TextStyle(fontSize: 18, height: 1.3, fontWeight: FontWeight.w700)),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 12),
          child: Wrap(spacing: 12, runSpacing: 2, children: [
            Text('👥 $answers', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.muted)),
            if (!q.closed) Text('⏳ ${_closesIn()}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.muted)),
          ]),
        ),
        if (open && q.kind == 'rate')
          Row(children: [
            Expanded(
              child: AppField(
                controller: _value,
                hint: '0',
                prefixText: '₹ ',
                keyboard: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                suffix: (q.unit ?? '').isEmpty ? null : Padding(padding: const EdgeInsets.only(top: 12, right: 12), child: Text('/${q.unit}', style: TextStyle(fontSize: 14, color: p.muted))),
              ),
            ),
            const SizedBox(width: 8),
            GoldButton(
              label: t('Send'),
              height: 44,
              loading: _busy,
              onPressed: _value.text.trim().isEmpty ? null : () => _send(value: num.tryParse(_value.text.trim())),
            ),
          ]),
        // big tappable choices with letter badges
        if (open && q.kind == 'poll')
          for (var i = 0; i < q.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Opacity(
                opacity: _busy && _picked != i ? .45 : 1,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _busy ? null : () => _send(option: i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: _picked == i ? kGold.withValues(alpha: .15) : p.canvas,
                      border: Border.all(color: _picked == i ? kGold : p.border, width: 2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: _picked == i ? kGold : p.chip, shape: BoxShape.circle),
                        child: Text(_busy && _picked == i ? '…' : _letters[i % 4], style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _picked == i ? kInk : p.muted)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(q.options[i], style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                    ]),
                  ),
                ),
              ),
            ),
        if (open) Padding(padding: const EdgeInsets.only(top: 2), child: Text('🔒 ${t('Answers are anonymous. See what others said after you answer.')}', style: TextStyle(fontSize: 12, color: p.muted))),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(fontSize: 12, color: p.danger))),
        if (!open)
          if (res == null || !res.ready)
            _locked(p, q, res)
          else ...[
            if (q.kind == 'rate') _rateResult(p, q, res) else _pollResult(p, q, res),
            _shareButton(p, q),
          ],
      ]),
    );
  }

  /// Until 5 answers: thanks, and how close it is
  Widget _locked(Pal p, Poll q, PollResult? res) {
    final n = res?.n ?? q.answers;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p.chip.withValues(alpha: .6), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(q.answered ? '✓ ${t('Thanks, your answer is in')}' : t('Closed'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(children: [
          for (var k = 0; k < 5; k++) Expanded(child: Container(height: 8, margin: EdgeInsets.only(right: k < 4 ? 6 : 0), decoration: BoxDecoration(color: k < n ? kGold : p.border, borderRadius: BorderRadius.circular(99)))),
        ]),
        const SizedBox(height: 6),
        Text(t("Results at 5 answers · {n} so far. We'll tell you when they're in.", {'n': n}), style: TextStyle(fontSize: 12, color: p.muted)),
      ]),
    );
  }

  Widget _shareButton(Pal p, Poll q) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: GestureDetector(
          onTap: () => SharePlus.instance.share(ShareParams(text: '${_question(q)}\n$siteUrl/today?poll=${q.id}')),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(border: Border.all(color: p.border), borderRadius: BorderRadius.circular(99)),
            child: Text('📤 ${t('Share with a group')}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted)),
          ),
        ),
      );

  Widget _rateResult(Pal p, Poll q, PollResult res) {
    final low = res.low ?? 0, high = res.high ?? 0;
    double at(num v) => ((v - low) / (high - low == 0 ? 1 : high - low)).clamp(0, 1).toDouble();
    final med = res.median, mine = q.myValue;
    String? vs;
    if (mine != null && med != null) {
      vs = mine == med
          ? t('You said {v}: right on the median', {'v': _money(mine)})
          : mine > med
              ? t('You said {v}: {d} above the median', {'v': _money(mine), 'd': _money(mine - med)})
              : t('You said {v}: {d} below the median', {'v': _money(mine), 'd': _money(med - mine)});
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.chip.withValues(alpha: .5), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t('What members say').toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .4, color: p.muted)),
        const SizedBox(height: 4),
        Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 10, children: [
          Text(_money(med), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
          Padding(padding: const EdgeInsets.only(bottom: 5), child: Text('${t('median')}${(q.unit ?? '').isEmpty ? '' : ' /${q.unit}'}', style: TextStyle(fontSize: 14, color: p.muted))),
        ]),
        const SizedBox(height: 16),
        // where the member's own answer sits in the range; the dots slide in
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOut,
          builder: (_, k, __) => LayoutBuilder(builder: (_, c) {
            Widget dot(num v, Color color) => Positioned(left: at(v) * k * (c.maxWidth - 16), top: -3, child: Container(width: 16, height: 16, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: p.canvas, width: 2))));
            return SizedBox(
              height: 10,
              child: Stack(clipBehavior: Clip.none, children: [
                Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), gradient: LinearGradient(colors: [kGold.withValues(alpha: .25), kGold.withValues(alpha: .75)]))),
                if (med != null) dot(med, p.text),
                if (mine != null) dot(mine, p.link),
              ]),
            );
          }),
        ),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${t('Low')} ${_money(res.low)}', style: TextStyle(fontSize: 12, color: p.muted)),
          Text('${t('High')} ${_money(res.high)}', style: TextStyle(fontSize: 12, color: p.muted)),
        ]),
        if (vs != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(vs, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
        if (res.places.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(res.places.map((x) => '${x.place} ${_money(x.median)}').join(' · '), style: TextStyle(fontSize: 12, color: p.muted))),
      ]),
    );
  }

  Widget _pollResult(Pal p, Poll q, PollResult res) {
    final counts = res.counts ?? const <int>[];
    final most = counts.isEmpty ? 0 : counts.reduce(math.max);
    return Column(children: [
      for (var i = 0; i < q.options.length; i++)
        Builder(builder: (_) {
          final count = counts.elementAtOrNull(i) ?? 0;
          final pct = (count / (res.n == 0 ? 1 : res.n) * 100).round();
          final top = count > 0 && count == most, mine = q.myOption == i;
          Widget tag(String text, Color bg, Color fg) => Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
                child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg)),
              );
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(color: mine ? null : p.chip.withValues(alpha: .5), border: Border.all(color: mine ? kGold : Colors.transparent, width: 2), borderRadius: BorderRadius.circular(14)),
            clipBehavior: Clip.antiAlias,
            child: Stack(children: [
              // the bar grows in, each a little after the one above
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: pct / 100),
                  duration: Duration(milliseconds: 600 + i * 90),
                  curve: Curves.easeOut,
                  builder: (_, w, __) => FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: w, child: Container(color: kGold.withValues(alpha: top ? .55 : .25))),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: mine ? kGold : p.canvas.withValues(alpha: .8), shape: BoxShape.circle),
                    child: Text(mine ? '✓' : _letters[i % 4], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: mine ? kInk : p.muted)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 2, children: [
                      Text(q.options[i], style: TextStyle(fontSize: 14, fontWeight: top || mine ? FontWeight.w700 : FontWeight.w500)),
                      if (top) tag('👑 ${t('Most picked')}', kGold, kInk),
                      if (mine) tag(t('Your pick'), p.text, p.canvas),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('$pct%', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1.1)),
                    Text(t(count == 1 ? '1 vote' : '{n} votes', {'n': count}), style: TextStyle(fontSize: 10.5, color: p.muted)),
                  ]),
                ]),
              ),
            ]),
          );
        }),
    ]);
  }
}

// ===================== alerts =====================

/// Words of "what" that become the alert's keywords (the first five of three letters or more).
List<String> keywordsOf(String s) => s.toLowerCase().split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)).where((w) => w.length > 2).toSet().take(5).toList();

/// What to suggest in the alert sheet: the member's services and skills, then their trade.
List<String> alertSuggestions(Profile? p) =>
    {...?p?.services, ...?p?.skills, if ((p?.category ?? '').isNotEmpty) p!.category}.map((s) => s.trim()).where((s) => s.isNotEmpty).take(6).toList();

const _radii = [5, 10, 25, 50];
const _budgets = [(null, 'Any'), (10000, 'Over ₹10k'), (50000, 'Over ₹50k'), (100000, 'Over ₹1 lakh')];
const _how = [('instant', 'Instantly', 'A notification for each new ask'), ('daily', 'Once a day', 'One summary at 8 pm'), ('leads', 'Only in Leads', 'No notification')];

/// "Alert me when someone asks for…" (web AlertSheet). Returns the saved alert and, for a new one, how many open
/// asks already fit (they're in Leads now).
Future<({Alert alert, int openNow})?> showAlertSheet(BuildContext context, {String? label, String? category, String? place, Alert? editing}) {
  final p = Pal.of(context);
  return showModalBottomSheet<({Alert alert, int openNow})>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.canvas,
    barrierColor: kInk.withValues(alpha: .6),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => _AlertSheet(label: label, category: category, place: place, editing: editing),
  );
}

class _AlertSheet extends StatefulWidget {
  final String? label, category, place;
  final Alert? editing;
  const _AlertSheet({this.label, this.category, this.place, this.editing});
  @override
  State<_AlertSheet> createState() => _AlertSheetState();
}

class _AlertSheetState extends State<_AlertSheet> {
  late final _what = TextEditingController(text: widget.editing?.label ?? widget.label ?? '');
  late String? _category = widget.editing?.category ?? widget.category;
  late String _place = widget.editing?.place ?? widget.place ?? context.read<AuthProvider>().profile?.location ?? '';
  late int _radius = widget.editing?.radiusKm ?? 10;
  late int? _budget = widget.editing?.budgetMin;
  late String _delivery = widget.editing?.delivery ?? 'instant';
  int? _count;
  bool _busy = false;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _preview();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _what.dispose();
    super.dispose();
  }

  String get _label => _what.text.trim().isNotEmpty ? _what.text.trim() : (_category == null ? '' : t(kCategoryShort[_category] ?? 'Ask'));
  Map<String, dynamic> get _input => {
        'label': _label,
        'keywords': keywordsOf(_what.text),
        'category': _category,
        'place': _place.isEmpty ? null : _place,
        'radiusKm': _radius,
        'budgetMin': _budget,
        'delivery': _delivery,
      };

  // "4 asks like this in the last 30 days", a moment after each change
  void _preview() {
    _debounce?.cancel();
    if (keywordsOf(_what.text).isEmpty && _category == null) {
      setState(() => _count = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final r = await context.read<AuthProvider>().api.post('/alerts/preview', {..._input}..remove('label')) as Map;
        if (mounted) setState(() => _count = (r['count'] as num?)?.toInt());
      } catch (_) {
        if (mounted) setState(() => _count = null);
      }
    });
  }

  void _set(VoidCallback fn) {
    setState(fn);
    _preview();
  }

  Future<void> _save() async {
    final api = context.read<AuthProvider>().api;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = (widget.editing != null ? await api.patch('/alerts/${widget.editing!.id}', _input) : await api.post('/alerts', _input)) as Map;
      if (mounted) Navigator.pop(context, (alert: Alert.fromJson(r), openNow: (r['openNow'] as num?)?.toInt() ?? 0));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final suggestions = alertSuggestions(context.read<AuthProvider>().profile);
    Widget label(String s) => Padding(padding: const EdgeInsets.only(top: 16, bottom: 6), child: Text(t(s).toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .4, color: p.muted)));
    Widget chip(String text, bool on, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 6, bottom: 6),
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: on ? kGold.withValues(alpha: .2) : null, border: Border.all(color: on ? kGold : p.border), borderRadius: BorderRadius.circular(99)),
              child: Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: on ? p.text : p.muted)),
            ),
          ),
        );
    Widget scroll(List<Widget> kids) => SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: kids));
    final hasWhat = _label.length >= 2;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .92),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            WIcon(WI.bell, size: 20, color: p.tagText),
            const SizedBox(width: 8),
            Expanded(child: Text(t(widget.editing != null ? 'Edit alert' : 'Alert me when someone asks for…'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            GestureDetector(onTap: () => Navigator.pop(context), child: WIcon(WI.close, size: 24, color: p.text)),
          ]),
          label('What'),
          AppField(controller: _what, hint: t('e.g. CNC machining, logo design, godown'), onChanged: (_) => _set(() {})),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(children: [for (final s in suggestions) chip(s, _what.text.trim() == s, () => _set(() => _what.text = s))]),
          ],
          label('Type of ask'),
          scroll([
            chip(t('Any'), _category == null, () => _set(() => _category = null)),
            for (final e in kCategoryShort.entries) chip(t(e.value), _category == e.key, () => _set(() => _category = e.key)),
          ]),
          label('Where'),
          CityPill(value: _place, anyLabel: t('Anywhere'), onChanged: (c) => _set(() => _place = c.name)),
          if (_place.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(children: [for (final r in _radii) chip(t('{n} km', {'n': r}), _radius == r, () => _set(() => _radius = r))]),
          ],
          label('Budget'),
          scroll([for (final b in _budgets) chip(t(b.$2), _budget == b.$1, () => _set(() => _budget = b.$1))]),
          label('How to tell me'),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < _how.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _delivery = _how[i].$1),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 64),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _delivery == _how[i].$1 ? kGold.withValues(alpha: .15) : null,
                      border: Border.all(color: _delivery == _how[i].$1 ? kGold : p.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t(_how[i].$2), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      Text(t(_how[i].$3), style: TextStyle(fontSize: 11, color: p.muted)),
                    ]),
                  ),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 12),
          if (_count != null)
            Text(
              _count == 0 ? t('No asks like this in the last 30 days yet.') : t(_count == 1 ? '1 ask like this in the last 30 days' : '{n} asks like this in the last 30 days', {'n': _count!}),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _count == 0 ? p.muted : p.tagText),
            ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(fontSize: 12, color: p.danger))),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: GoldButton(label: t('Save alert'), wi: WI.bell, loading: _busy, onPressed: hasWhat ? _save : null)),
        ]),
      ),
    );
  }
}

/// Alerts: "tell me when someone asks for…". Each says what, where and how it tells the member, and how many asks
/// it found; matches also join Leads for you. Add, edit, pause and delete here.
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});
  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  List<Alert>? _list;
  int _limit = 5;
  String? _saved;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await context.read<AuthProvider>().api.get('/alerts') as Map;
      if (mounted) {
        setState(() {
          _list = ((r['alerts'] as List?) ?? const []).map((e) => Alert.fromJson(e as Map)).toList();
          _limit = (r['limit'] as num?)?.toInt() ?? 5;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _list = []);
    }
  }

  Future<void> _sheet([Alert? editing]) async {
    final r = await showAlertSheet(context, editing: editing);
    if (r == null || !mounted) return;
    setState(() => _saved = editing != null ? null : savedMessage(r.openNow));
    _load();
  }

  Future<void> _menu(Alert a) async {
    final p = Pal.of(context);
    final pick = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: p.canvas,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final m in ['Edit', a.paused ? 'Resume' : 'Pause', 'Delete'])
            ListTile(title: Text(t(m), style: TextStyle(fontWeight: FontWeight.w600, color: m == 'Delete' ? p.danger : p.text)), onTap: () => Navigator.pop(ctx, m)),
        ]),
      ),
    );
    if (!mounted || pick == null) return;
    final api = context.read<AuthProvider>().api;
    try {
      if (pick == 'Edit') return await _sheet(a);
      if (pick == 'Delete') await api.delete('/alerts/${a.id}');
      if (pick == 'Pause' || pick == 'Resume') await api.patch('/alerts/${a.id}', {'paused': !a.paused});
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final list = _list;
    if (list == null) return const PageLoader();
    const how = {'instant': 'Instantly', 'daily': 'Once a day', 'leads': 'Only in Leads'};
    final green = p.dark ? kGreenDark : kGreen;
    return LogoRefresh(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, islandSpace(context)),
        children: [
          Row(children: [
            Expanded(child: Text(t('Get told when someone asks for what you do. Matches also show in Leads for you.'), style: TextStyle(fontSize: 14, color: p.muted))),
            const SizedBox(width: 12),
            GoldButton(label: t('Add'), wi: WI.plus, height: 36, onPressed: list.length >= _limit ? null : _sheet),
          ]),
          if (_saved != null)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: green.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
              child: Text(_saved!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: green)),
            ),
          if (list.isEmpty) ...[
            EmptyState(title: t('No alerts yet'), hint: t('Set one for your trade and area, and be the first to reply when a fitting ask comes in.')),
            Center(child: GoldButton(label: t('Set an alert'), wi: WI.bell, height: 40, onPressed: _sheet)),
          ],
          for (final a in list)
            Opacity(
              opacity: a.paused ? .6 : 1,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: kGold.withValues(alpha: .2), shape: BoxShape.circle),
                    child: WIcon(WI.bell, size: 20, color: p.tagText),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      Text(
                        [
                          if (a.category != null) t(kCategoryShort[a.category] ?? 'Ask'),
                          a.place != null ? t('within {km} km of {place}', {'km': a.radiusKm, 'place': a.place!}) : t('Anywhere'),
                          if (a.budgetMin != null) t('over ₹{n}', {'n': _money(a.budgetMin).substring(1)}),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: p.muted),
                      ),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(
                            text: a.recentMatches == 0 ? t('No matches yet') : t(a.recentMatches == 1 ? '1 match this month' : '{n} matches this month', {'n': a.recentMatches}),
                            style: TextStyle(fontWeight: FontWeight.w600, color: p.tagText),
                          ),
                          if (a.lastMatchedAt != null) TextSpan(text: ' · ${t('last {when}', {'when': timeAgo(a.lastMatchedAt!)})}', style: TextStyle(color: p.muted)),
                          TextSpan(text: ' · ${a.paused ? t('Paused') : t(how[a.delivery] ?? '')}', style: TextStyle(color: p.muted)),
                        ]),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ]),
                  ),
                  IconButton(tooltip: t('More options'), onPressed: () => _menu(a), icon: WIcon(WI.more, size: 20, color: p.muted)),
                ]),
              ),
            ),
          if (list.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(t('{n} of {max} alerts used', {'n': list.length, 'max': _limit}), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.muted)),
            ),
        ],
      ),
    );
  }
}

/// What to say once an alert is saved.
String savedMessage(int openNow) => openNow > 0
    ? t(openNow == 1 ? "Saved. 1 open ask already fits: it's in your Leads." : "Saved. {n} open asks already fit: they're in your Leads.", {'n': openNow})
    : t("Saved. We'll tell you when a fitting ask comes in.");

// ===================== push nudge =====================

/// "Turn on notifications" at the moment it obviously helps (after replying to an ask, on your own open ask), when
/// this phone doesn't show our notifications yet.
class PushNudge extends StatefulWidget {
  final String title, hint;
  const PushNudge({super.key, required this.title, required this.hint});
  @override
  State<PushNudge> createState() => _PushNudgeState();
}

class _PushNudgeState extends State<PushNudge> {
  bool? _on;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    context.read<NotificationService>().alertsEnabled().then((v) {
      if (mounted) setState(() => _on = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_on != false) return const SizedBox.shrink();
    final p = Pal.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kGold.withValues(alpha: .1), border: Border.all(color: kGold.withValues(alpha: .6)), borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        Container(width: 40, height: 40, alignment: Alignment.center, decoration: BoxDecoration(color: kGold.withValues(alpha: .3), shape: BoxShape.circle), child: WIcon(WI.bell, size: 20, color: p.tagText)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            Text(widget.hint, style: TextStyle(fontSize: 12, color: p.muted)),
          ]),
        ),
        const SizedBox(width: 8),
        GoldButton(
          label: t('Turn on'),
          height: 32,
          loading: _busy,
          onPressed: () async {
            setState(() => _busy = true);
            final on = await context.read<NotificationService>().enableAlerts();
            if (mounted) {
              setState(() {
                _busy = false;
                _on = on;
              });
            }
          },
        ),
      ]),
    );
  }
}

// ===================== daily stories =====================

/*
 * The daily circles at the front of Updates (web daily-stories.tsx): Leads for you by kind of ask, Today in your area
 * by kind of item, and businesses that just joined. Each circle is a story of cards, its ring cut into one segment per
 * card (gold until that card is seen), and the player carries on from one circle to the next, as updates do.
 */

/// An emoji for each kind of ask.
const kCategoryEmoji = {
  'job': '👷', 'supplier': '📦', 'buyer': '🛒', 'logistics': '🚚', 'funding': '💰', 'advice': '💡', 'mentorship': '🧭', 'partnership': '🤝',
  'machinery': '⚙️', 'space': '🏢', 'training': '🎓', 'jobwork': '🏭', 'compliance': '📑', 'consultant': '🧑‍💼', 'export': '🌍', 'tender': '📄',
  'digital': '💻', 'repair': '🔧', 'daily': '🥛', 'events': '🎉', 'rental': '🚜', 'wellness': '🩺', 'printing': '🖨️', 'other': '✨',
};

/// Short names under the circles (the long ones don't fit 84 px).
const _categoryTile = {
  'job': 'Jobs', 'supplier': 'Suppliers', 'buyer': 'Buyers', 'logistics': 'Logistics', 'funding': 'Funding', 'advice': 'Advice', 'mentorship': 'Mentors',
  'partnership': 'Partners', 'machinery': 'Machinery', 'space': 'Space', 'training': 'Training', 'jobwork': 'Job work', 'compliance': 'GST / Legal',
  'consultant': 'Consultants', 'export': 'Export', 'tender': 'Tenders', 'digital': 'Digital', 'repair': 'Repairs', 'daily': 'Daily', 'events': 'Events', 'rental': 'Rentals', 'wellness': 'Wellness', 'printing': 'Printing', 'other': 'Other',
};

const _bg = {
  'ink': [Color(0xFFF2C230), Color(0xFFB8860B), Color(0xFF6B4F06)],
  'poll': [Color(0xFFC99400), Color(0xFF5A4710), Color(0xFF1E1E1E)],
  'rates': [Color(0xFF22875C), Color(0xFF0F3A29), Color(0xFF0B1F17)],
  'notice': [Color(0xFFD9700F), Color(0xFF5A2F08), Color(0xFF1F1206)],
  'tender': [Color(0xFF2F6FC4), Color(0xFF13305A), Color(0xFF0B1424)],
  'event': [Color(0xFF9A45C9), Color(0xFF3D1957), Color(0xFF170A21)],
  'new': [Color(0xFFE0457B), Color(0xFF5A1A33), Color(0xFF1E1E1E)],
};

/// The circles' fills (null: ink).
const _tone = <String, List<Color>>{
  'poll': [Color(0xFFFFF4C7), Color(0xFFFFC700)],
  'rates': [Color(0xFFC9F2DC), Color(0xFF2FA36F)],
  'notice': [Color(0xFFFFE2C2), Color(0xFFF08A24)],
  'tender': [Color(0xFFD6E6FF), Color(0xFF4A86D8)],
  'event': [Color(0xFFF0DCFF), Color(0xFFA45BD6)],
};

/// The coloured strip naming a card.
const _strip = <String, List<Color>>{
  'lead': [Color(0xFF1E1E1E), Color(0xFF1E1E1E)],
  'poll': [Color(0xFFFFD84A), Color(0xFFC99400)],
  'rates': [Color(0xFF059669), Color(0xFF059669)],
  'notice': [Color(0xFFE07B16), Color(0xFFE07B16)],
  'tender': [Color(0xFF2F6FC4), Color(0xFF2F6FC4)],
  'event': [Color(0xFF8A3FBF), Color(0xFF8A3FBF)],
  'new': [Color(0xFFE0457B), Color(0xFFFF8A4C)],
};

const _todayKinds = [
  (type: 'rates', emoji: '📈', plural: 'Rates'),
  (type: 'notice', emoji: '⚠️', plural: 'Notices'),
  (type: 'tender', emoji: '📄', plural: 'Tenders'),
  (type: 'event', emoji: '📅', plural: 'Events'),
];

/// Leaves the story for a page (back from it lands on Connect).
typedef DailyGo = void Function(Widget page);

/// One card of a circle's story.
class DailyCard {
  final String id;
  final bool fresh;
  final List<Color> bg;
  final int ms;
  final VoidCallback? onShow;
  final Widget Function(DailyGo go) build;
  const DailyCard({required this.id, required this.fresh, required this.bg, required this.ms, required this.build, this.onShow});
}

/// One circle: what it shows in the row, and its cards.
class DailyGroup {
  final String id, emoji, label, title, allLabel;
  /// the circle's fill; null for ink
  final List<Color>? tone;
  /// a photo instead of the emoji (New here)
  final ({String name, String? url})? photo;
  final Widget Function() allPage;
  /// the tour's target on the first leads and the first Today circle
  final String? tour;
  final List<DailyCard> cards;
  const DailyGroup({required this.id, required this.emoji, required this.label, required this.title, required this.allLabel, required this.allPage, required this.cards, this.tone, this.photo, this.tour});
  int get fresh => cards.where((c) => c.fresh).length;
}

/// The circles from Leads for you, Today and the businesses that just joined; [seen] is what this phone has shown
/// (a lead the server no longer calls new counts as seen too).
List<DailyGroup> buildDailyGroups({required List<Post>? leads, required TodayFeed? today, required List<Profile>? biz, required Set<String> seen, required Api api}) {
  final out = <DailyGroup>[];
  // ---- Leads for you, by kind of ask (the three busiest, then the rest together)
  if (leads != null && leads.isNotEmpty) {
    final by = <String, List<Post>>{};
    for (final x in leads.take(30)) {
      (by[x.category ?? 'other'] ??= []).add(x);
    }
    int freshOf(List<Post> ps) => ps.where((x) => x.leadNew && !seen.contains('lead:${x.id}')).length;
    final ranked = by.entries.toList()..sort((a, b) => freshOf(b.value) != freshOf(a.value) ? freshOf(b.value) - freshOf(a.value) : b.value.length - a.value.length);
    final sets = [
      for (final e in ranked.take(3)) (cat: e.key, posts: e.value),
      if (ranked.length > 3) (cat: 'more', posts: [for (final e in ranked.skip(3)) ...e.value]),
    ];
    for (var gi = 0; gi < sets.length; gi++) {
      final cat = sets[gi].cat;
      out.add(DailyGroup(
        id: 'leads:$cat',
        emoji: cat == 'more' ? '✨' : (kCategoryEmoji[cat] ?? '✨'),
        label: cat == 'more' ? t('More leads') : t(_categoryTile[cat] ?? 'Other'),
        title: cat == 'more' ? t('Leads for you') : '${t('Leads for you')} · ${t(kCategoryShort[cat] ?? 'Other')}',
        allLabel: t('All leads'),
        allPage: () => SubPage(title: t('Leads for you'), body: const LeadsScreen()),
        tour: gi == 0 ? 'today' : null,
        cards: [
          for (final x in sets[gi].posts.take(8))
            DailyCard(
              id: 'lead:${x.id}',
              fresh: x.leadNew && !seen.contains('lead:${x.id}'),
              bg: _bg['ink']!,
              ms: 8000,
              onShow: () => ViewTracker.record(api, x.id),
              build: (go) => _LeadStoryCard(post: x, go: go),
            ),
        ],
      ));
    }
  }
  // ---- Today in your area: the question, then a circle per kind of item
  if (today != null && today.cluster != null) {
    final place = today.cluster!;
    final isToday = today.day == today.today;
    var tour = 'today-area';
    String? nextTour() {
      final r = tour.isEmpty ? null : tour;
      tour = '';
      return r;
    }

    void seenToday() => api.post('/today/seen').catchError((_) => null);
    final q = today.poll;
    if (q != null && !q.closed) {
      final rate = q.kind == 'rate';
      out.add(DailyGroup(
        id: 'today:poll',
        emoji: rate ? '💸' : '❓',
        label: t(rate ? 'Rate check' : 'Question'),
        title: '${t('Today in {place}', {'place': place})} · ${t(rate ? 'Rate check' : "Today's question")}',
        tone: _tone['poll'],
        allLabel: t('Today'),
        allPage: () => SubPage(title: t('Today in your area'), body: const TodayScreen()),
        tour: nextTour(),
        cards: [
          DailyCard(id: 'poll:${q.id}', fresh: !q.answered && !seen.contains('poll:${q.id}'), bg: _bg['poll']!, ms: 12000, onShow: seenToday, build: (_) => _PollStory(feed: today)),
        ],
      ));
    }
    for (final k in _todayKinds) {
      final items = today.items.where((i) => i.type == k.type).toList();
      if (items.isEmpty) continue;
      out.add(DailyGroup(
        id: 'today:${k.type}',
        emoji: k.emoji,
        label: t(k.plural),
        title: '${t('Today in {place}', {'place': place})} · ${t(k.plural)}',
        tone: _tone[k.type],
        allLabel: t('Today'),
        allPage: () => SubPage(title: t('Today in your area'), body: const TodayScreen()),
        tour: nextTour(),
        cards: [
          for (final it in items)
            DailyCard(
              id: 'today:${it.id}',
              fresh: isToday && !seen.contains('today:${it.id}'),
              bg: _bg[it.type]!,
              ms: it.type == 'rates' ? 9000 : 8000,
              onShow: seenToday,
              build: (_) => _TodayStoryCard(it: it, day: today.day ?? today.today ?? ''),
            ),
        ],
      ));
    }
  }
  // ---- New here: businesses that just joined, the member's city first
  if (biz != null && biz.isNotEmpty) {
    final first = biz.first;
    out.add(DailyGroup(
      id: 'new',
      emoji: '🎉',
      label: t('New here'),
      title: t('New on WEBWEB'),
      photo: (name: first.company.isNotEmpty ? first.company : first.name, url: first.photoUrl),
      allLabel: t('Find more'),
      allPage: () => const FindScreen(standalone: true, initialScope: 'business'),
      cards: [
        for (final u in biz) DailyCard(id: 'biz:${u.uid}', fresh: !seen.contains('biz:${u.uid}'), bg: _bg['new']!, ms: 7000, build: (go) => _NewBizCard(u: u, go: go)),
      ],
    ));
  }
  return out;
}

/// A circle's ring cut into one segment per card: gold for the ones not seen yet, grey for the rest.
class _SegmentRing extends CustomPainter {
  final List<bool> fresh;
  final Color seen;
  _SegmentRing(this.fresh, this.seen);
  @override
  void paint(Canvas canvas, Size size) {
    final n = fresh.isEmpty ? 1 : fresh.length;
    const w = 2.5;
    final r = size.width / 2 - w / 2 - .25;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: r);
    const full = 2 * 3.141592653589793;
    final gap = n > 1 ? (6 / r).clamp(0, full / n / 4).toDouble() : 0.0;
    final sweep = full / n - gap;
    for (var k = 0; k < n; k++) {
      final on = k < fresh.length && fresh[k];
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = n > 1 ? StrokeCap.round : StrokeCap.butt
        ..shader = on ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFD84A), Color(0xFFC99400)]).createShader(rect) : null
        ..color = on ? const Color(0xFFFFD84A) : seen;
      canvas.drawArc(rect, -3.141592653589793 / 2 + k * (sweep + gap) + gap / 2, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(_SegmentRing old) => old.seen != seen || old.fresh.length != fresh.length || [for (var i = 0; i < fresh.length; i++) old.fresh[i] != fresh[i]].any((x) => x);
}

/// The circle in the Updates row.
class DailyCircle extends StatelessWidget {
  final DailyGroup group;
  final VoidCallback onTap;
  const DailyCircle({super.key, required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    const box = 74.0;
    final g = group;
    final n = g.fresh;
    final tone = g.tone;
    final circle = Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: g.photo != null ? p.chip : (tone == null ? (p.dark ? const Color(0xFF2E2E2E) : kInk) : null),
        gradient: g.photo == null && tone != null ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: tone) : null,
      ),
      child: g.photo != null
          ? ClipOval(
              child: (g.photo!.url ?? '').isNotEmpty
                  ? (starterTone(g.photo!.url) != null ? StarterMono(url: g.photo!.url!, name: g.photo!.name, size: 64) : Image.network(g.photo!.url!, width: 64, height: 64, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Text(initials(g.photo!.name))))
                  : Text(initials(g.photo!.name), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.muted)),
            )
          : Text(g.emoji, style: const TextStyle(fontSize: 28, height: 1)),
    );
    final tile = Container(
      width: 84,
      margin: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(children: [
          SizedBox(
            width: box,
            height: box,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(child: CustomPaint(painter: _SegmentRing([for (final c in g.cards) c.fresh], p.border))),
              Center(child: circle),
              // how many are new, or the circle's emoji on a photo
              if (n > 0 || g.photo != null)
                Positioned(
                  left: box * .854 - 11,
                  top: box * .854 - 11,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 22),
                    height: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(11), border: Border.all(color: p.canvas, width: 2)),
                    child: Text(g.photo != null ? g.emoji : '$n', style: TextStyle(fontSize: g.photo != null ? 10 : 10, height: 1, fontWeight: FontWeight.w800, color: const Color(0xFFFFD84A))),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 4),
          Text(g.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: n > 0 ? FontWeight.w600 : FontWeight.w400)),
        ]),
      ),
    );
    return g.tour == null ? tile : KeyedSubtree(key: Tours.key(g.tour!), child: tile);
  }
}

/// Plays [groups] from [start], one circle after another, like updates.
Future<void> openDailyStories(BuildContext context, List<DailyGroup> groups, int start, void Function(String id) onSeen) =>
    Navigator.push(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => DailyStories(groups: groups, start: start, onSeen: onSeen)));

/// Tap right for the next card and left for the one before, hold to pause. Each card carries what to do now (I can do
/// this, Answer, Interested, View profile) and a link (Open ask, Directions, Say hello); the header links to the page.
class DailyStories extends StatefulWidget {
  final List<DailyGroup> groups;
  final int start;
  final void Function(String id) onSeen;
  const DailyStories({super.key, required this.groups, required this.start, required this.onSeen});
  @override
  State<DailyStories> createState() => _DailyStoriesState();
}

class _DailyStoriesState extends State<DailyStories> with SingleTickerProviderStateMixin {
  // the groups as they were when opened: seeing cards mustn't reorder anything under the player
  late final List<DailyGroup> _list = widget.groups;
  late int _g = widget.start;
  late int _i = _firstFresh(_list[_g]);
  late final AnimationController _bar = AnimationController(vsync: this)..addStatusListener((s) {
      if (s == AnimationStatus.completed) _next();
    });
  bool _held = false, _typing = false;

  static int _firstFresh(DailyGroup g) => g.cards.indexWhere((c) => c.fresh).clamp(0, g.cards.length - 1);

  DailyGroup get _group => _list[_g];
  DailyCard get _card => _group.cards[_i];

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_focus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  // a field in focus (the rate check) holds the card
  void _focus() {
    final typing = FocusManager.instance.primaryFocus?.context?.widget is EditableText;
    if (typing != _typing) {
      _typing = typing;
      _sync();
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focus);
    _bar.dispose();
    super.dispose();
  }

  void _start() {
    if (!mounted) return;
    final c = _card;
    _bar.duration = Duration(milliseconds: c.ms);
    _bar.value = 0;
    c.onShow?.call();
    widget.onSeen(c.id);
    _sync();
  }

  void _sync() {
    if (_held || _typing) {
      _bar.stop();
    } else if (!_bar.isAnimating) {
      _bar.forward();
    }
  }

  void _next() {
    if (_i < _group.cards.length - 1) {
      setState(() => _i++);
    } else if (_g < _list.length - 1) {
      setState(() {
        _g++;
        _i = _firstFresh(_group);
      });
    } else {
      Navigator.maybePop(context);
      return;
    }
    _start();
  }

  void _prev() {
    if (_i > 0) {
      setState(() => _i--);
    } else if (_g > 0) {
      setState(() {
        _g--;
        _i = 0;
      });
    } else {
      return;
    }
    _start();
  }

  void _go(Widget page) => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final g = _group;
    final c = _card;
    return Scaffold(
      backgroundColor: kInk,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // tap the left third for the card before, anywhere else for the next; buttons and fields keep their taps
        onTapUp: (d) => d.localPosition.dx < MediaQuery.of(context).size.width / 3 ? _prev() : _next(),
        onLongPressStart: (_) {
          _held = true;
          _sync();
        },
        onLongPressEnd: (_) {
          _held = false;
          _sync();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(gradient: RadialGradient(center: const Alignment(-.5, -.8), radius: 1.4, colors: c.bg, stops: const [0, .5, 1])),
          child: Stack(children: [
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, top + 76, 16, 32),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (w, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: .96, end: 1.0).animate(a), child: w)),
                    child: KeyedSubtree(key: ValueKey(c.id), child: SingleChildScrollView(child: c.build(_go))),
                  ),
                ),
              ),
            ),
            // top bar, as on an update
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(12, top + 10, 4, 16),
                decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withValues(alpha: .6), Colors.black.withValues(alpha: 0)])),
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: AnimatedBuilder(
                      animation: _bar,
                      builder: (_, __) => Row(children: [
                        for (var k = 0; k < g.cards.length; k++) ...[
                          if (k > 0) const SizedBox(width: 4),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: k < _i ? 1 : (k == _i ? _bar.value : 0),
                                minHeight: 3,
                                backgroundColor: Colors.white.withValues(alpha: .3),
                                valueColor: const AlwaysStoppedAnimation(Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ]),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: g.tone == null ? (g.photo != null ? Colors.white24 : const Color(0xFF2E2E2E)) : null,
                        gradient: g.tone == null ? null : LinearGradient(colors: g.tone!),
                        border: Border.all(color: const Color(0xFFFFD84A), width: 2),
                      ),
                      child: Text(g.emoji, style: const TextStyle(fontSize: 17, height: 1)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(g.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                        Text('${_i + 1} / ${g.cards.length}', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: .7))),
                      ]),
                    ),
                    GestureDetector(
                      onTap: () => _go(g.allPage()),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .15), borderRadius: BorderRadius.circular(99)),
                        child: Text('${g.allLabel} →', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                    IconButton(onPressed: () => Navigator.maybePop(context), icon: const WIcon(WI.close, size: 24, color: Colors.white), tooltip: t('Close')),
                  ]),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ----------------------- cards -----------------------

/// A story button: the gold one does the main thing, the soft one the other.
class _Cta extends StatelessWidget {
  final String emoji, label;
  final VoidCallback? onTap;
  final bool soft, active;
  const _Cta({required this.emoji, required this.label, this.onTap, this.soft = false, this.active = false});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 48,
          decoration: BoxDecoration(
            gradient: soft ? null : kGoldGradient,
            color: soft ? (active ? kGold.withValues(alpha: .2) : p.chip) : null,
            border: soft ? Border.all(color: active ? kGold : p.border) : null,
            borderRadius: BorderRadius.circular(16),
            boxShadow: soft ? null : const [BoxShadow(color: Color(0x66C99400), blurRadius: 16, offset: Offset(0, 6))],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(emoji, style: const TextStyle(fontSize: 17, height: 1)),
              const SizedBox(width: 8),
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: soft ? p.text : kInk))),
            ]),
          ),
        ),
      ),
    );
  }
}

Widget _ctas(List<Widget> ctas) => Row(children: [
      for (var k = 0; k < ctas.length; k++) ...[if (k > 0) const SizedBox(width: 8), Expanded(child: ctas[k])],
    ]);

/// The card a story frame shows, with a coloured strip naming what it is.
class _Shell extends StatelessWidget {
  final String strip;
  final List<Color> stripColors;
  final Color stripFg;
  final String? right;
  final Widget child;
  const _Shell({required this.strip, required this.stripColors, this.stripFg = Colors.white, this.right, required this.child});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: p.canvas, borderRadius: BorderRadius.circular(28), boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 40, offset: Offset(0, 16))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(gradient: LinearGradient(colors: stripColors)),
          child: Row(children: [
            Expanded(child: Text(strip.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .6, color: stripFg))),
            if (right != null) Text(right!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: stripFg.withValues(alpha: .85))),
          ]),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 20), child: child),
      ]),
    );
  }
}

/// A small pill with an emoji: where, how much, how soon.
class _Fact extends StatelessWidget {
  final String emoji, text;
  final Color? tint;
  const _Fact(this.emoji, this.text, {this.tint});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: tint?.withValues(alpha: .16) ?? p.chip, borderRadius: BorderRadius.circular(99)),
      child: Text('$emoji  $text', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }
}

/// One lead: what, where, the budget and how soon, who asks and why it fits, how many replied; I can do this, or open it.
class _LeadStoryCard extends StatelessWidget {
  final Post post;
  final DailyGo go;
  const _LeadStoryCard({required this.post, required this.go});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final x = post;
    final left = askTimeLeft(x);
    final n = x.sharesCount;
    return _Shell(
      strip: '${kCategoryEmoji[x.category] ?? '✨'} ${t(kCategoryShort[x.category] ?? 'Ask')}',
      stripColors: _strip['lead']!,
      stripFg: const Color(0xFFFFD84A),
      right: '${x.leadNew ? '${t('NEW')} · ' : ''}${timeAgo(x.createdAt)}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(x.title ?? '', style: const TextStyle(fontSize: 24, height: 1.15, fontWeight: FontWeight.w800)),
        if ((x.description ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(x.description!, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, height: 1.45, color: p.text.withValues(alpha: .75))),
        ],
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if ((x.locationPref ?? '').isNotEmpty) _Fact('📍', '${t(x.locationPref!)}${x.distanceM == null ? '' : ' · ${formatDistance(x.distanceM!)}'}'),
          if ((x.budget ?? '').isNotEmpty) _Fact('💰', x.budget!, tint: kGold),
          if (left != null) _Fact('⏳', left),
        ]),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () => go(ProfileScreen(handle: x.authorHandle)),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Avatar(name: x.shownName, photoUrl: x.authorPhotoUrl, type: x.authorType, size: 36, badge: 13),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(x.shownName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  if ((x.leadReason ?? '').isNotEmpty)
                    Text('✨ ${leadReasonText(x.leadReason!)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.tagText)),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          n == 0 ? '🔥 ${t('No replies yet · be the first')}' : '👥 ${t(n == 1 ? '1 replied' : '{n} replied', {'n': n})}',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: n == 0 ? (p.dark ? kGreenDark : kGreen) : p.muted),
        ),
        const SizedBox(height: 16),
        _ctas([
          _Cta(emoji: '✋', label: t('I can do this'), onTap: () => go(PostDetailScreen(postId: x.id, openReply: true))),
          _Cta(emoji: '👀', label: t('Open ask'), soft: true, onTap: () => go(PostDetailScreen(postId: x.id))),
        ]),
      ]),
    );
  }
}

/// One Today item, with what to do with it now: share it, mark it useful or interested, open the tender, get directions.
class _TodayStoryCard extends StatefulWidget {
  final TodayItem it;
  final String day;
  const _TodayStoryCard({required this.it, required this.day});
  @override
  State<_TodayStoryCard> createState() => _TodayStoryCardState();
}

class _TodayStoryCardState extends State<_TodayStoryCard> {
  late final Set<String> _marked = {...widget.it.marked};
  late int _interested = widget.it.interested;

  Future<void> _toggle(String kind) async {
    final api = context.read<AuthProvider>().api;
    final on = !_marked.contains(kind);
    setState(() {
      on ? _marked.add(kind) : _marked.remove(kind);
      if (kind == 'interested') _interested += on ? 1 : -1;
    });
    try {
      on ? await api.post('/today/items/${widget.it.id}/mark', {'kind': kind}) : await api.delete('/today/items/${widget.it.id}/mark', {'kind': kind});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final it = widget.it;
    final x = _text(it);
    final pl = it.payload;
    final kind = _todayKinds.firstWhere((k) => k.type == it.type, orElse: () => _todayKinds.first);
    void open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    final share = _Cta(emoji: '📤', label: 'WhatsApp', onTap: () => open('https://wa.me/?text=${Uri.encodeComponent('${x.title}\n$siteUrl/today')}'));
    String? left;
    if (it.type == 'tender' && pl['deadline'] != null) {
      final d = (DateTime.parse('${pl['deadline']}T23:59:59+05:30').difference(DateTime.now()).inHours / 24).ceil();
      left = d < 0 ? t('Closed') : d == 0 ? t('Closes today') : t(d == 1 ? '1 day left' : '{n} days left', {'n': d});
    }
    final green = p.dark ? kGreenDark : kGreen;
    return _Shell(
      strip: '${kind.emoji} ${t(_typeLabel[it.type] ?? '')}',
      stripColors: _strip[it.type] ?? _strip['lead']!,
      right: it.source ?? dayLabel(widget.day),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (it.type != 'rates')
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (it.type == 'notice' && pl['when'] != null) _Fact('🕘', '${pl['when']}', tint: const Color(0xFFF08A24)),
            if (left != null) _Fact('⏳', left, tint: const Color(0xFF4A86D8)),
            if (it.type == 'event' && pl['startsAt'] != null) _Fact('🗓️', '${pl['startsAt']}', tint: const Color(0xFFA45BD6)),
            if ((it.place ?? '').isNotEmpty) _Fact('📍', it.place!),
          ]),
        if (it.type != 'rates') const SizedBox(height: 12),
        Text(x.title, style: const TextStyle(fontSize: 22, height: 1.2, fontWeight: FontWeight.w800)),
        if (it.type == 'rates') ...[
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(border: Border.all(color: p.border), borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              for (var k = 0; k < it.rates.length; k++)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(border: k == 0 ? null : Border(top: BorderSide(color: p.border))),
                  child: Row(children: [
                    Expanded(child: Text(it.rates[k].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                    Text.rich(TextSpan(children: [
                      TextSpan(text: it.rates[k].value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      if ((it.rates[k].unit ?? '').isNotEmpty) TextSpan(text: '/${it.rates[k].unit!.replaceFirst(RegExp(r'^/'), '')}', style: TextStyle(fontSize: 13, color: p.muted)),
                    ])),
                    const SizedBox(width: 10),
                    Builder(builder: (_) {
                      final c = it.rates[k].change ?? 0;
                      final col = c > 0 ? green : (c < 0 ? p.danger : p.muted);
                      return Container(
                        width: 56,
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: c == 0 ? p.chip : col.withValues(alpha: .15), borderRadius: BorderRadius.circular(99)),
                        child: Text(c > 0 ? '▲ ${c.abs()}' : c < 0 ? '▼ ${c.abs()}' : '–', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: col)),
                      );
                    }),
                  ]),
                ),
            ]),
          ),
        ],
        if ((x.body ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(x.body!, style: TextStyle(fontSize: 15, height: 1.45, color: p.text.withValues(alpha: .75))),
        ],
        if (it.type == 'tender' && pl['who'] != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text('✅ ${t('Who can apply')}: ${pl['who']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
        if (it.type == 'event' && pl['venue'] != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text('📍 ${pl['venue']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
        if (it.type == 'event' && _interested > 0) Padding(padding: const EdgeInsets.only(top: 4), child: Text('⭐ ${t('{n} interested', {'n': _interested})}', style: TextStyle(fontSize: 14, color: p.muted))),
        const SizedBox(height: 16),
        if (it.type == 'event')
          _ctas([
            _Cta(emoji: _marked.contains('interested') ? '⭐' : '☆', label: t('Interested'), onTap: () => _toggle('interested')),
            if (pl['venue'] != null) _Cta(emoji: '🗺️', label: t('Directions'), soft: true, onTap: () => open('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent('${pl['venue']}')}')),
          ])
        else if (it.type == 'tender' && pl['link'] != null)
          _ctas([
            _Cta(emoji: '🔗', label: t('Open tender'), onTap: () => open('${pl['link']}')),
            _Cta(emoji: '📤', label: 'WhatsApp', soft: true, onTap: () => open('https://wa.me/?text=${Uri.encodeComponent('${x.title}\n$siteUrl/today')}')),
          ])
        else
          _ctas([share, _Cta(emoji: '👍', label: t('Useful'), soft: true, active: _marked.contains('useful'), onTap: () => _toggle('useful'))]),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => _toggle('outdated'),
          child: Text(
            _marked.contains('outdated') ? '🚩 ${t('Marked outdated')}' : t('Outdated or wrong?'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _marked.contains('outdated') ? p.danger : p.muted),
          ),
        ),
      ]),
    );
  }
}

/// Today's question in a story: answer it right here.
class _PollStory extends StatelessWidget {
  final TodayFeed feed;
  const _PollStory({required this.feed});
  @override
  Widget build(BuildContext context) {
    final q = feed.poll!;
    return _Shell(
      strip: q.kind == 'rate' ? '💸 ${t('Rate check')}' : '❓ ${t("Today's question")}',
      stripColors: _strip['poll']!,
      stripFg: kInk,
      right: '📍 ${feed.cluster}',
      child: PollCard(poll: q, bare: true),
    );
  }
}

/// A business that just joined: who they are and what they do; View profile, or Say hello.
class _NewBizCard extends StatefulWidget {
  final Profile u;
  final DailyGo go;
  const _NewBizCard({required this.u, required this.go});
  @override
  State<_NewBizCard> createState() => _NewBizCardState();
}

class _NewBizCardState extends State<_NewBizCard> {
  bool _busy = false;

  Future<void> _hello() async {
    if (_busy) return;
    setState(() => _busy = true);
    final u = widget.u;
    final peer = Peer(uid: u.uid, name: u.name, company: u.company, handle: u.handle, userType: u.userType, photoUrl: u.photoUrl, verification: u.verification);
    try {
      final id = (await context.read<AuthProvider>().api.post('/chats', {'userId': u.uid}) as Map)['id'] as String;
      widget.go(ChatThread(chatId: id, peer: peer));
    } catch (_) {
      widget.go(ProfileScreen(handle: u.handle));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final u = widget.u;
    final name = u.company.isNotEmpty ? u.company : u.name;
    return _Shell(
      strip: '🎉 ${t('New on WEBWEB')}',
      stripColors: _strip['new']!,
      right: t('joined {when}', {'when': timeAgo(u.createdAt)}),
      child: Column(children: [
        Avatar(name: name, photoUrl: u.photoUrl, type: u.userType, size: 80, badge: 20),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Flexible(child: Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, height: 1.2, fontWeight: FontWeight.w800))),
          const SizedBox(width: 6),
          VerifiedBadge(level: u.verification, size: 18),
        ]),
        if (u.company.isNotEmpty && u.name != u.company) Text(u.name, style: TextStyle(fontSize: 14, color: p.muted)),
        const SizedBox(height: 12),
        Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
          if (u.category.isNotEmpty) _Fact('🏷️', t(labelOf(kProfileCategories, u.category))),
          if (u.location.isNotEmpty) _Fact('📍', u.location),
        ]),
        if ((u.bio ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(u.bio!, maxLines: 3, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.45, color: p.text.withValues(alpha: .75))),
        ],
        if (u.services.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
            for (final s in u.services.take(4))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: kGold.withValues(alpha: .1), border: Border.all(color: kGold.withValues(alpha: .5)), borderRadius: BorderRadius.circular(99)),
                child: Text(s, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
          ]),
        ],
        const SizedBox(height: 20),
        _ctas([
          _Cta(emoji: '👤', label: t('View profile'), onTap: () => widget.go(ProfileScreen(handle: u.handle))),
          _Cta(emoji: '👋', label: t('Say hello'), soft: true, onTap: _hello),
        ]),
      ]),
    );
  }
}

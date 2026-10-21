import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../i18n.dart';
import '../models.dart';
import '../notifications.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/city_picker.dart';
import '../widgets/p1.dart' show kGreenDark;

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
  const PollCard({super.key, required this.poll});
  @override
  State<PollCard> createState() => _PollCardState();
}

class _PollCardState extends State<PollCard> {
  late Poll _poll = widget.poll;
  final _value = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Future<void> _send({int? option, num? value}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = Poll.fromJson(await context.read<AuthProvider>().api.post('/polls/${_poll.id}/answer', {if (option != null) 'option': option, if (value != null) 'value': value}) as Map);
      if (mounted) setState(() => _poll = r);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final q = _poll;
    final res = q.result;
    final open = !q.answered && !q.closed;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: kGold.withValues(alpha: .05), border: Border.all(color: kGold.withValues(alpha: .5)), borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('❓ ${t(q.kind == 'rate' ? 'Rate check' : "Today's question").toUpperCase()}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .4, color: p.tagText))),
          Text(t(q.answers == 1 ? '1 answer' : '{n} answers', {'n': q.answers}), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.muted)),
        ]),
        const SizedBox(height: 4),
        Text(_question(q), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        if (open && q.kind == 'rate') ...[
          const SizedBox(height: 12),
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
        ],
        if (open && q.kind == 'poll') ...[
          const SizedBox(height: 12),
          for (var i = 0; i < q.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SizedBox(width: double.infinity, child: GoldButton(label: q.options[i], outlined: true, height: 40, onPressed: _busy ? null : () => _send(option: i))),
            ),
        ],
        if (open) Padding(padding: const EdgeInsets.only(top: 8), child: Text(t('Answers are anonymous. See what others said after you answer.'), style: TextStyle(fontSize: 12, color: p.muted))),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(fontSize: 12, color: p.danger))),
        if (!open)
          if (res == null || !res.ready)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(t("Results at 5 answers · {n} so far. We'll tell you when they're in.", {'n': res?.n ?? q.answers}), style: TextStyle(fontSize: 14, color: p.muted)),
            )
          else if (q.kind == 'rate')
            _rateResult(p, q, res)
          else
            _pollResult(p, q, res),
      ]),
    );
  }

  Widget _rateResult(Pal p, Poll q, PollResult res) {
    final low = res.low ?? 0, high = res.high ?? 0;
    double at(num v) => ((v - low) / (high - low == 0 ? 1 : high - low)).clamp(0, 1).toDouble();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 12, runSpacing: 4, children: [
          Text(_money(res.median), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          Text('${t('median')}${(q.unit ?? '').isEmpty ? '' : ' /${q.unit}'}', style: TextStyle(fontSize: 14, color: p.muted)),
          Text.rich(TextSpan(children: [
            TextSpan(text: '${t('Range')} '),
            TextSpan(text: '${_money(res.low)} – ${_money(res.high)}', style: TextStyle(fontWeight: FontWeight.w700, color: p.text)),
          ]), style: TextStyle(fontSize: 14, color: p.muted)),
        ]),
        const SizedBox(height: 12),
        // where the member's own answer sits in the range
        LayoutBuilder(builder: (_, c) {
          Widget dot(num v, Color color) => Positioned(left: at(v) * (c.maxWidth - 14), top: -3, child: Container(width: 14, height: 14, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: p.canvas, width: 2))));
          return SizedBox(
            height: 8,
            child: Stack(clipBehavior: Clip.none, children: [
              Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), gradient: LinearGradient(colors: [kGold.withValues(alpha: .25), kGold.withValues(alpha: .7)]))),
              if (res.median != null) dot(res.median!, p.text),
              if (q.myValue != null) dot(q.myValue!, p.link),
            ]),
          );
        }),
        if (q.myValue != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(t('You said {v}', {'v': _money(q.myValue)}), style: TextStyle(fontSize: 12, color: p.muted))),
        if (res.places.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(res.places.map((x) => '${x.place} ${_money(x.median)}').join(' · '), style: TextStyle(fontSize: 12, color: p.muted))),
      ]),
    );
  }

  Widget _pollResult(Pal p, Poll q, PollResult res) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(children: [
          for (var i = 0; i < q.options.length; i++)
            Builder(builder: (_) {
              final pct = ((res.counts?.elementAtOrNull(i) ?? 0) / (res.n == 0 ? 1 : res.n) * 100).round();
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(border: Border.all(color: p.border), borderRadius: BorderRadius.circular(8)),
                clipBehavior: Clip.antiAlias,
                child: Stack(children: [
                  Positioned.fill(child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: pct / 100, child: Container(color: kGold.withValues(alpha: .25)))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(children: [
                      Expanded(child: Text('${q.options[i]}${q.myOption == i ? ' ✓' : ''}', style: TextStyle(fontSize: 14, fontWeight: q.myOption == i ? FontWeight.w700 : FontWeight.w400))),
                      Text('$pct%', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ]),
              );
            }),
        ]),
      );
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

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth_provider.dart';
import '../i18n.dart';
import '../theme.dart';

/// One stop of a guided tour: points at the widget carrying `Tours.key(target)`, or a centred card when null.
class TourStep {
  final String? target;
  final String title;
  final String body;
  /// an animated picture above the text in a centred card ('give-take')
  final String? visual;
  const TourStep(this.title, this.body, [this.target, this.visual]);
}

/// The first-login tour of the app: the feed (same wording as the web's components/tour.tsx, so the
/// translations are shared), then the tabs and the account menu, where "Take the app tour" replays it.
/// Its id changes when it gains new stops, so members who saw the earlier one see it once more ("connect2":
/// leads, I can do this, closing an ask, your week; "connect3": Today in your area, show your work, alerts).
const kConnectTourId = 'connect5';
const kConnectTour = [
  TourStep('Welcome to WebWeb: Give and Take', 'Take: post what you need and pick who helps. Give: answer asks that fit you. Do both and your name and rank grow.', null, 'give-take'),
  TourStep('Leads for you', 'Asks that fit your business, picked for you every day. Reply early.', 'today'),
  TourStep('Every ask says who wants what', 'Like "SkyQ is looking for a space". Swipe its cards for photos, details and the budget.', 'first-ask'),
  TourStep('Say "I can help"', 'Add your price and when. The asker compares and picks.', 'reply'),
  TourStep('Need something yourself?', 'Tap Ask. Choose Hire, Buy, Sell, Advice, a Poll and more: it takes a minute.', 'nav-ask'),
  TourStep('Alerts, your week, and this tour', 'Set alerts for the asks you want first. Your week shows your leads, jobs won and rank.', 'account'),
];

/// "Take the app tour" in the account menu: the shell switches to Connect and starts the tour.
final tourRequest = ValueNotifier<int>(0);

const kAskTour = [
  TourStep('What is your ask?', 'Hire, buy, sell, ask advice, run a poll. Your ask reaches the members who can help.', null, 'ask-types'),
  TourStep('Say it in one line', 'For example: Need 5 CNC operators in Turbhe. The kind of ask is picked from it.', 'ask-title'),
  TourStep('Add the details', 'Quantity, quality, timing. The more specific, the better the answers.', 'ask-description'),
  TourStep('Not right? Tap to change', 'This is what your ask is. Tap it to pick another, or Other to say it in your own words.', 'ask-category'),
  TourStep('Where, when and budget', 'All optional. They show as cards your members can swipe.', 'ask-details'),
  TourStep('See your cards', 'This is how members will see your ask. Add photos and watch it come alive.', 'ask-preview'),
  TourStep('Publish', 'See who it reaches, then publish. Replies arrive in your notifications.', 'ask-publish'),
];

/// First-visit guided tours. Shown once per member: the server keeps the log per tour (shared with the
/// web), and a local list skips the round trip once a tour is finished or skipped. Both are per account, so a
/// new member signing in on a phone someone else used still gets their tours.
class Tours {
  static String _doneKey(String uid) => 'webweb_tours_done_$uid';
  static final _keys = <String, GlobalKey>{};
  static Future<Map<String, dynamic>>? _log;
  static String? _logFor; // the account [_log] belongs to
  static bool _showing = false;

  /// The key a tour target carries, e.g. `KeyedSubtree(key: Tours.key('updates'), child: ...)`.
  static GlobalKey key(String target) => _keys.putIfAbsent(target, () => GlobalKey(debugLabel: 'tour:$target'));

  static RenderBox? _box(String target) {
    final ro = _keys[target]?.currentContext?.findRenderObject();
    return ro is RenderBox && ro.attached && ro.hasSize && !ro.size.isEmpty ? ro : null;
  }

  static String get _platform => kIsWeb ? 'web' : (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android');

  static void _record(dynamic api, String id, String status, int step, int steps) {
    api.put('/me/tours/$id', {'status': status, 'step': step, 'steps': steps, 'platform': _platform}).catchError((_) => null);
  }

  /// Show tour [id] now, whether or not it was seen (the account menu's "Take the app tour").
  static Future<void> start(BuildContext context, String id, List<TourStep> steps) async {
    if (_showing) return;
    final auth = context.read<AuthProvider>();
    await Future.delayed(const Duration(milliseconds: 500)); // let the tab switch settle
    if (!context.mounted || _showing) return;
    _run(context, auth.api, id, steps, () {});
  }

  /// Show tour [id] if this member hasn't finished or skipped it yet.
  static Future<void> maybeShow(BuildContext context, String id, List<TourStep> steps) async {
    if (_showing) return;
    final auth = context.read<AuthProvider>();
    final api = auth.api;
    final uid = auth.profile?.uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getStringList(_doneKey(uid)) ?? const <String>[];
    if (done.contains(id)) return;
    if (_logFor != uid) {
      _logFor = uid;
      _log = null;
    }
    _log ??= api.get('/me/tours').then((r) => Map<String, dynamic>.from(r as Map)).catchError((_) {
      _log = null;
      return <String, dynamic>{};
    });
    final log = await _log!;
    final seen = log[id];
    void markDone() => prefs.setStringList(_doneKey(uid), {...done, id}.toList());
    if (seen is Map && seen['status'] != 'started') return markDone();
    await Future.delayed(const Duration(milliseconds: 900)); // let the page settle
    if (!context.mounted || _showing) return;
    _run(context, api, id, steps, () {
      markDone();
      _log = _log?.then((l) => {...l, id: {'status': 'done'}});
    });
  }

  static Future<void> _run(BuildContext context, dynamic api, String id, List<TourStep> steps, VoidCallback onEnd) async {
    // parts that load on their own (the leads card) get up to 2.5 s to appear
    for (var waited = 0; waited < 2500 && steps.any((s) => s.target != null && _box(s.target!) == null); waited += 250) {
      await Future.delayed(const Duration(milliseconds: 250));
    }
    if (!context.mounted || _showing) return;
    // only the stops that are on screen now (no "first ask" stop on an empty feed)
    final list = steps.where((s) => s.target == null || _box(s.target!) != null).toList();
    if (list.isEmpty) return;
    _showing = true;
    _record(api, id, 'started', 0, list.length);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TourOverlay(
        steps: list,
        onDone: (status, step) {
          entry.remove();
          _showing = false;
          onEnd();
          _record(api, id, status, step, list.length);
        },
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(entry);
  }
}

class _TourOverlay extends StatefulWidget {
  final List<TourStep> steps;
  final void Function(String status, int step) onDone;
  const _TourOverlay({required this.steps, required this.onDone});
  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay> {
  int _i = 0;
  Rect? _rect;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _go(0);
  }

  Rect? _measure(String? target) {
    final box = target == null ? null : Tours._box(target);
    if (box == null) return null;
    final r = box.localToGlobal(Offset.zero) & box.size;
    // clip to the screen: a sideways-scrolling chip row is wider than the phone
    final w = MediaQuery.of(context).size.width;
    return Rect.fromLTRB(r.left.clamp(8, w - 8), r.top, r.right.clamp(8, w - 8), r.bottom);
  }

  Future<void> _go(int n) async {
    final gen = ++_gen;
    final target = widget.steps[n].target;
    setState(() => _i = n);
    final ctx = target == null ? null : Tours._keys[target]?.currentContext;
    if (ctx != null && ctx.mounted) {
      try {
        await Scrollable.ensureVisible(ctx, alignment: .3, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      } catch (_) {}
    }
    if (!mounted || gen != _gen) return;
    setState(() => _rect = _measure(target));
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final mq = MediaQuery.of(context);
    final step = widget.steps[_i];
    final last = _i == widget.steps.length - 1;
    final hole = _rect?.inflate(6);
    const pad = 16.0;

    final card = Material(
      color: p.canvas,
      borderRadius: BorderRadius.circular(16),
      elevation: 12,
      shadowColor: Colors.black54,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('{n} of {total}', {'n': '${_i + 1}', 'total': '${widget.steps.length}'}).toUpperCase(),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .8, color: p.muted)),
          const SizedBox(height: 4),
          if (step.visual == 'give-take') ...[const _GiveTake(), const SizedBox(height: 10)],
          if (step.visual == 'ask-types') ...[const _AskTypesDemo(), const SizedBox(height: 10)],
          Text(t(step.title), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(t(step.body), style: TextStyle(fontSize: 14, height: 1.4, color: p.text)),
          const SizedBox(height: 12),
          Row(children: [
            for (var k = 0; k < widget.steps.length; k++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 4),
                width: k == _i ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(color: k == _i ? kGold : p.border, borderRadius: BorderRadius.circular(3)),
              ),
            const Spacer(),
            if (!last) TextButton(onPressed: () => widget.onDone('skipped', _i), child: Text(t('Skip'), style: TextStyle(color: p.muted, fontWeight: FontWeight.w600))),
            if (_i > 0) TextButton(onPressed: () => _go(_i - 1), child: Text(t('Back'), style: TextStyle(color: p.text, fontWeight: FontWeight.w600))),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => last ? widget.onDone('completed', _i) : _go(_i + 1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(20)),
                child: Text(t(last ? 'Got it' : 'Next'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
              ),
            ),
          ]),
        ]),
      ),
    );

    // card below the spotlight when it fits, else above it, else centred
    Widget placed;
    if (hole == null) {
      placed = Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: pad), child: card));
    } else if (mq.size.height - hole.bottom > 230) {
      placed = Positioned(left: pad, right: pad, top: hole.bottom + 12, child: card);
    } else {
      placed = Positioned(left: pad, right: pad, bottom: mq.size.height - hole.top + 12, child: card);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onDone('skipped', _i); // system back = skip
      },
      child: Stack(children: [
        // dim everything except the spotlight; taps on the page are held while the tour runs
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            // a step with nothing to point at just dims the screen: a TweenAnimationBuilder with a null target
            // throws in its initState (crash reports c028c40d…, Android), so it only animates a real spotlight
            child: hole == null
                ? CustomPaint(painter: _HolePainter(null, const Color(0x9E14120C)))
                : TweenAnimationBuilder<Rect?>(
                    tween: RectTween(end: hole),
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    builder: (_, r, __) => CustomPaint(painter: _HolePainter(r, const Color(0x9E14120C))),
                  ),
          ),
        ),
        placed,
      ]),
    );
  }
}

class _HolePainter extends CustomPainter {
  final Rect? hole;
  final Color color;
  _HolePainter(this.hole, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    var path = Path()..addRect(Offset.zero & size);
    if (hole != null) {
      final rr = RRect.fromRectAndRadius(hole!, const Radius.circular(14));
      path = Path.combine(PathOperation.difference, path, Path()..addRRect(rr));
      canvas.drawPath(path, Paint()..color = color);
      canvas.drawRRect(rr, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = kGold);
    } else {
      canvas.drawPath(path, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_HolePainter old) => old.hole != hole || old.color != color;
}

/// [Take] = I need something: ask, replies come in, pick one. [Give] = I can do it: a lead arrives, I reply, I'm chosen.
const _scenes = {
  'take': [
    ('📣', 'You post what you need', 'SkyQ is looking for a space'),
    ('💬', 'Members reply with a price', '₹18,000 · ₹16,500 · ₹17,200'),
    ('🏆', 'You pick one, they win the job', 'Close your ask, they hear it'),
  ],
  'give': [
    ('🔔', 'A lead arrives that fits you', 'Asks matching your business'),
    ('🙋', 'You tap "I can do this"', 'Add your price and when'),
    ('⭐', 'They choose you', 'Jobs won build your rank'),
  ],
};

class _GiveTake extends StatefulWidget {
  const _GiveTake();
  @override
  State<_GiveTake> createState() => _GiveTakeState();
}

class _GiveTakeState extends State<_GiveTake> {
  String _mode = 'take';
  int _n = 0;
  bool _auto = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 2200), (_) {
      if (_auto && mounted) setState(() => _n = (_n + 1) % 3);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final scenes = _scenes[_mode]!;
    Widget tab(String m, String label) => Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              _mode = m;
              _n = 0;
              _auto = true;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(gradient: _mode == m ? kGoldGradient : null, borderRadius: BorderRadius.circular(99)),
              child: Text(t(label), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _mode == m ? kInk : p.muted)),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kGold.withValues(alpha: .22), kGold.withValues(alpha: .06)]), borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: p.canvas.withValues(alpha: .7), borderRadius: BorderRadius.circular(99)),
          child: Row(children: [tab('take', 'I need something (Take)'), tab('give', 'I can help (Give)')]),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 80,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, .2), end: Offset.zero).animate(a), child: c)),
            child: Container(
              key: ValueKey('$_mode$_n'),
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: p.canvas, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Container(width: 46, height: 46, alignment: Alignment.center, decoration: BoxDecoration(color: kGold.withValues(alpha: .25), shape: BoxShape.circle), child: Text(scenes[_n].$1, style: const TextStyle(fontSize: 24))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t(scenes[_n].$2), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.25)),
                    Text(t(scenes[_n].$3), style: TextStyle(fontSize: 12, color: p.muted)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var k = 0; k < 3; k++)
            GestureDetector(
              onTap: () => setState(() {
                _n = k;
                _auto = false;
              }),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: AnimatedContainer(duration: const Duration(milliseconds: 200), width: k == _n ? 22 : 8, height: 8, decoration: BoxDecoration(color: k == _n ? kGold : p.border, borderRadius: BorderRadius.circular(4))),
              ),
            ),
        ]),
        Text(t('Every reply you give builds your name. Every ask you take makes your business grow.'), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.text.withValues(alpha: .7))),
      ]),
    );
  }
}

/// The kinds of ask, tappable: each shows how it reads on a card, in the asker's name
const _typeDemo = [
  ('👷', 'Hire', 'Saurabh is looking to hire someone', '5 CNC operators, Turbhe'),
  ('🔎', 'Buy / Quote', 'SkyQ is looking for a space', '450 sq ft, Vashi'),
  ('🏷️', 'Sell / Offer', 'Rahul has something to offer', '2 VMC machines on rent'),
  ('💡', 'Advice', 'Neha wants your advice', 'GST on export invoices?'),
  ('🗳️', 'Poll', 'Amit wants your vote', 'Open on Sunday: yes or no?'),
  ('⭐', 'Recommend', 'Pooja wants a recommendation', 'A trusted electrician, Nerul'),
];

class _AskTypesDemo extends StatefulWidget {
  const _AskTypesDemo();
  @override
  State<_AskTypesDemo> createState() => _AskTypesDemoState();
}

class _AskTypesDemoState extends State<_AskTypesDemo> {
  int _k = 0;
  bool _auto = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 2200), (_) {
      if (_auto && mounted) setState(() => _k = (_k + 1) % _typeDemo.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final d = _typeDemo[_k];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kGold.withValues(alpha: .22), kGold.withValues(alpha: .06)]), borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
          for (var i = 0; i < _typeDemo.length; i++)
            GestureDetector(
              onTap: () => setState(() {
                _k = i;
                _auto = false;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(gradient: i == _k ? kGoldGradient : null, color: i == _k ? null : p.canvas.withValues(alpha: .7), borderRadius: BorderRadius.circular(20)),
                child: Text('${_typeDemo[i].$1} ${t(_typeDemo[i].$2)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: i == _k ? kInk : p.muted)),
              ),
            ),
        ]),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, .15), end: Offset.zero).animate(a), child: c)),
          child: Container(
            key: ValueKey(_k),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.canvas, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(d.$1, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(child: Text(t(d.$3), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, height: 1.25))),
              ]),
              const SizedBox(height: 4),
              Text(t(d.$4), style: TextStyle(fontSize: 12, color: p.muted)),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Text(t('Pick what you want. WebWeb finds the right members.'), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.text.withValues(alpha: .7))),
      ]),
    );
  }
}

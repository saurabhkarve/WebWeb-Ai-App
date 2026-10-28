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
const kConnectTourId = 'connect4';
const kConnectTour = [
  TourStep('Welcome to WebWeb', 'Businesses and job seekers near you ask for what they need here, and others answer with a contact. Here is a 30-second look around.'),
  TourStep('Give and Take: how business grows here', 'Take: you need something, so you post an ask and pick who helps. Give: you can help, so you answer asks that fit you. Do both, and your name and rank grow.', null, 'give-take'),
  TourStep('Leads for you', 'Asks that fit your business, picked for you every day. The number shows the new ones: tap to see them, and reply early.', 'today'),
  TourStep('Today in your area', "Rates, notices, tenders and events near you, new every morning, and a quick question. A gold ring means there's something new.", 'today-area'),
  TourStep('Show your work', "Post a photo of a job you finished or new stock. It stays up for 24 hours, and we'll tell you how many businesses saw it.", 'updates'),
  TourStep('This is an ask', 'Someone needs something: staff, a supplier, a buyer or space. Tap it to read the full ask.', 'first-ask'),
  TourStep('The essentials at a glance', "What it is, where (and how far from you), the budget and how soon it's needed. Tap a chip to find similar asks.", 'chips'),
  TourStep('Say "I can do this"', 'Reply opens with I can do this: add your price and when you can do it, so the asker can compare. A note or photo is optional.', 'reply'),
  TourStep('Know someone who can help?', 'Refer shares a contact from your phone book for this ask, so the right person gets the work.', 'refer'),
  TourStep('Find', 'Search members, businesses and asks by what they do and where.', 'nav-find'),
  TourStep('Need something yourself?', 'Tap Ask to post what you need. When you find someone, close your ask and pick who you chose: they hear they won the job.', 'nav-ask'),
  TourStep('Talk', 'Your chats and calls. Message @webwebai, the WebWeb AI assistant, for contacts or to post an ask for you.', 'nav-talk'),
  TourStep('Alerts, your week, and this tour', 'Set alerts for the asks you want first. Every Monday, Your week shows your leads, replies, jobs won and your rank. Find them here, with this tour.', 'account'),
];

/// "Take the app tour" in the account menu: the shell switches to Connect and starts the tour.
final tourRequest = ValueNotifier<int>(0);

const kAskTour = [
  TourStep('Post your first ask', "An ask tells nearby businesses and workers what you need. They answer with their contact, so you can call them directly. It's free."),
  TourStep('Write it as members will see it', 'This is your ask as it will look on Connect. Fill in each part.', 'ask-card'),
  TourStep('Say it in one line', 'For example: Need 5 CNC operators in Turbhe.', 'ask-title'),
  TourStep('Add the details', 'Quantity, quality, timing. The more specific you are, the better the answers.', 'ask-description'),
  TourStep('The category is picked for you', 'It follows your words and decides who gets your ask: job seekers for jobs, suppliers for supplies. Tap it to change it.', 'ask-category'),
  TourStep('Or start from an example', 'Tap one to fill in an example, then change the details to yours.', 'ask-templates'),
  TourStep('Where, when and budget', 'Set the area and how far your ask reaches, how soon you need it, and your budget. All optional.', 'ask-details'),
  TourStep('See who it reaches, then publish', 'This shows how many members your ask will reach. Responses appear on your ask and in your notifications.', 'ask-publish'),
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
    ('📣', 'You post an ask', 'Need 5 CNC operators in Turbhe'),
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

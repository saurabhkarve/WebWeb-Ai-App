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
  const TourStep(this.title, this.body, [this.target]);
}

/// Same steps and wording as the web (components/tour.tsx), so the translations are shared.
const kConnectTour = [
  TourStep('Welcome to WebWeb', 'Businesses and job seekers near you ask for what they need here, and others answer with a contact. Here is a 30-second look around.'),
  TourStep('Updates', '24-hour updates from people near you: new stock, openings and offers. Tap a circle to view one.', 'updates'),
  TourStep('This is an ask', 'Someone needs something: staff, a supplier, a buyer or space. Tap it to read the full ask.', 'first-ask'),
  TourStep('The essentials at a glance', "What it is, where (and how far from you), the budget and how soon it's needed. Tap a chip to find similar asks.", 'chips'),
  TourStep('Answer in one tap', 'Reply shares your contact, a photo or a note with the person who asked. Only they see what you share.', 'reply'),
  TourStep('Know someone who can help?', 'Refer shares a contact from your phone book for this ask, so the right person gets the work.', 'refer'),
  TourStep('Need something yourself?', 'Tap Ask to post what you need. Members who fit get it on their phone, and answers come with contact numbers.', 'nav-ask'),
];

const kAskTour = [
  TourStep('Post your first ask', "An ask tells nearby businesses and workers what you need. They answer with their contact, so you can call them directly. It's free."),
  TourStep('Write it as members will see it', 'This is your ask as it will look on Connect. Fill in each part.', 'ask-card'),
  TourStep('Say it in one line', 'For example: Need 5 CNC operators in Turbhe.', 'ask-title'),
  TourStep('Add the details', 'Quantity, quality, timing. The more specific you are, the better the answers.', 'ask-description'),
  TourStep('The type is picked for you', 'It follows your words and decides who gets your ask: job seekers for jobs, suppliers for supplies. Tap it to change it.', 'ask-category'),
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
          markDone();
          _log = _log?.then((l) => {...l, id: {'status': status, 'lastStep': step}});
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
            child: TweenAnimationBuilder<Rect?>(
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

import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme.dart';

/// What shows while a search is on its way (instead of "no results"): the AI mark breathing, a line that says what it is
/// doing now and changes every second or so (with dots for the steps), and three rows that shimmer where the results will land.
class SearchLoader extends StatefulWidget {
  /// a new search starts the steps over
  final String query;

  /// results are already showing: one slim line, no placeholder rows, so nothing is pushed down or hidden by the keyboard
  final bool compact;
  const SearchLoader({super.key, required this.query, this.compact = false});
  @override
  State<SearchLoader> createState() => _SearchLoaderState();
}

class _SearchLoaderState extends State<SearchLoader> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  Timer? _tick;
  int _i = 0;

  List<String> get _steps => [
        t('Reading your search…'),
        t('Checking your contacts…'),
        t('Looking nearby…'),
        t('Looking for who can help…'),
        t('Ranking who can help…'),
      ];

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _i = 0;
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 1300), (_) {
      if (mounted && _i < _steps.length - 1) setState(() => _i++);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(SearchLoader old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) setState(_start);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final steps = _steps;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: widget.compact ? 6 : 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          AnimatedBuilder(
            animation: _c,
            builder: (_, __) => Container(
              width: widget.compact ? 26 : 34,
              height: widget.compact ? 26 : 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: kGoldGradient,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: kGold.withValues(alpha: .25 + .3 * _c.value), blurRadius: 8 + 12 * _c.value)],
              ),
              child: Transform.scale(scale: .9 + .25 * _c.value, child: Icon(Icons.auto_awesome_rounded, size: widget.compact ? 14 : 17, color: kInk)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (w, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, .3), end: Offset.zero).animate(a), child: w)),
                child: Align(
                  key: ValueKey(_i),
                  alignment: Alignment.centerLeft,
                  child: Text(steps[_i], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 6),
              Row(children: [
                for (var k = 0; k < steps.length; k++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    margin: const EdgeInsets.only(right: 4),
                    width: k <= _i ? 20 : 8,
                    height: 4,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: k <= _i ? kGold : p.text.withValues(alpha: .15)),
                  ),
              ]),
            ]),
          ),
        ]),
        if (!widget.compact) const SizedBox(height: 12),
        if (!widget.compact)
        for (var k = 0; k < 2; k++)
          Opacity(
            opacity: 1 - k * .22,
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) {
                final a = .08 + .07 * ((_c.value + k * .2) % 1);
                Widget bar(double w, double h, double al) => FractionallySizedBox(widthFactor: w, child: Container(height: h, decoration: BoxDecoration(color: p.text.withValues(alpha: al), borderRadius: BorderRadius.circular(8))));
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(children: [
                    Container(width: 44, height: 44, decoration: BoxDecoration(shape: BoxShape.circle, color: p.text.withValues(alpha: a))),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [bar(.4, 12, a), const SizedBox(height: 8), bar(.75, 10, a * .75)])),
                  ]),
                );
              },
            ),
          ),
      ]),
    );
  }
}

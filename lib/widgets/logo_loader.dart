import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../logo_paths.dart';

/// How much of the W is drawn (all 0..1). The gold ball and the ® are always there.
class _W {
  final double arm1, arm2, dotOpacity, dotScale, slash, fade;
  const _W(this.arm1, this.arm2, this.dotOpacity, this.dotScale, this.slash, [this.fade = 1]);
  static const full = _W(1, 1, 1, 1, 1);
}

double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);
final _out = Curves.easeOut.transform;
final _inOut = Curves.easeInOut.transform;

/// CSS `logo-w-loop` (globals.css), one 1.8 s cycle: the two "\" strokes draw in (0-11 %, 11-22 %),
/// the dot pops to 1.5x and settles (25-37 %), both "/" fade in (40-57 %), everything holds, then fades (89-100 %).
_W _loop(double t) {
  final fade = t < .89 ? 1.0 : 1 - _out(_seg(t, .89, 1));
  double dotO, dotS;
  if (t < .25) {
    dotO = 0;
    dotS = 0;
  } else if (t < .33) {
    final k = _out(_seg(t, .25, .33));
    dotO = k;
    dotS = 1.5 * k;
  } else if (t < .37) {
    dotO = 1;
    dotS = 1.5 - .5 * _out(_seg(t, .33, .37));
  } else {
    dotO = 1;
    dotS = 1;
  }
  return _W(_out(_seg(t, 0, .11)), _out(_seg(t, .11, .22)), dotO, dotS, _inOut(_seg(t, .40, .57)), fade);
}

/// CSS `logo-w` (one play, 1.02 s): arm 1 0-0.2 s, arm 2 0.2-0.4 s, dot 0.45-0.67 s (pops to 1.5x at 70 %),
/// slashes fade in 0.72-1.02 s.
_W _once(double s) {
  final u = _seg(s, .45, .67);
  final dotO = u < .7 ? _out(u / .7) : 1.0;
  final dotS = u < .7 ? 1.5 * _out(u / .7) : 1.5 - .5 * _out((u - .7) / .3);
  return _W(_out(_seg(s, 0, .2)), _out(_seg(s, .2, .4)), u == 0 ? 0 : dotO, u == 0 ? 0 : dotS, _inOut(_seg(s, .72, 1.02)));
}

/// Pull-to-refresh: the W draws in step with the pull distance (p = 0..1).
_W _progress(double p) {
  final d = _seg(p, .5, .75);
  final dotS = d < .7 ? 1.5 * (d / .7) : 1.5 - .5 * ((d - .7) / .3);
  return _W(_seg(p, 0, .3), _seg(p, .25, .55), d == 0 ? 0 : (d / .7).clamp(0.0, 1.0), d == 0 ? 0 : dotS, _seg(p, .7, 1));
}

/// The golden WebWeb mark with its W animation (web/src/components/logo-mark.tsx).
/// - default: fully drawn, still;
/// - [playKey] > 0: plays the build once every time the key changes (tap the header logo);
/// - [loop]: keeps drawing itself (loaders);
/// - [progress]: drawn up to that fraction (pull-to-refresh).
class AnimatedLogo extends StatefulWidget {
  final double size;
  final bool loop;
  final int playKey;
  final double? progress;
  const AnimatedLogo({super.key, this.size = 32, this.loop = false, this.playKey = 0, this.progress});
  @override
  State<AnimatedLogo> createState() => _AnimatedLogoState();
}

class _AnimatedLogoState extends State<AnimatedLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);

  // layers are parsed once; per frame only their clip / opacity / scale change
  late Widget _base, _arm1, _arm2, _s3, _s4, _dot;

  @override
  void initState() {
    super.initState();
    _layers();
    _start();
  }

  void _layers() {
    Widget l(String svg) => SvgPicture.string(svg, width: widget.size, height: widget.size * 82 / 84);
    _base = l(logoBaseSvg);
    _arm1 = l(logoArm1Svg);
    _arm2 = l(logoArm2Svg);
    _s3 = l(logoSlash3Svg);
    _s4 = l(logoSlash4Svg);
    _dot = l(logoDotSvg);
  }

  void _start() {
    if (widget.loop) {
      _c.duration = const Duration(milliseconds: 1800);
      _c.repeat();
    } else if (widget.playKey > 0) {
      _c.duration = const Duration(milliseconds: 1020);
      _c.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(AnimatedLogo old) {
    super.didUpdateWidget(old);
    if (old.size != widget.size) _layers();
    if (old.loop != widget.loop || (old.playKey != widget.playKey && widget.playKey > 0)) {
      _c.stop();
      _start();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  _W get _state {
    if (widget.progress != null) return _progress(widget.progress!);
    if (widget.loop) return _loop(_c.value);
    if (widget.playKey > 0 && _c.isAnimating) return _once(_c.value * 1.02);
    return _W.full;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.size, h = widget.size * 82 / 84;
    return SizedBox(
      width: w,
      height: h,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final s = _state;
          // clip-path: inset() on an SVG path uses the path's own box, so each arm reveals from its own top
          Widget arm(Widget layer, double reveal, double top, double bottom) => Opacity(
                opacity: s.fade,
                child: ClipRect(clipper: _TopReveal(reveal, top / 82, bottom / 82), child: layer),
              );
          return Stack(children: [
            _base,
            arm(_arm1, s.arm1, 24.1, 57.9),
            arm(_arm2, s.arm2, 24.0, 57.8),
            Opacity(opacity: (s.slash * s.fade).clamp(0.0, 1.0), child: Stack(children: [_s3, _s4])),
            Opacity(
              opacity: (s.dotOpacity * s.fade).clamp(0.0, 1.0),
              child: Transform.scale(
                scale: s.dotScale,
                alignment: const Alignment(64.7605 / 84 * 2 - 1, 29.6996 / 82 * 2 - 1),
                child: _dot,
              ),
            ),
          ]);
        },
      ),
    );
  }
}

/// Reveals a layer from the top of its own box downwards (CSS `clip-path: inset(0 0 (1-p)*100% 0)`).
class _TopReveal extends CustomClipper<Rect> {
  final double p, top, bottom; // top / bottom of the path box as fractions of the height
  _TopReveal(this.p, this.top, this.bottom);
  @override
  Rect getClip(Size s) => p >= 1 ? Offset.zero & s : Rect.fromLTWH(0, 0, s.width, s.height * (top + (bottom - top) * p));
  @override
  bool shouldReclip(_TopReveal old) => old.p != p;
}

/// The web's in-page loader (Spinner): the W drawing itself in a loop.
class LogoLoader extends StatelessWidget {
  final double size;
  const LogoLoader({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) => AnimatedLogo(size: size, loop: true);
}

/// Centred loader for full-page / list loading states.
class PageLoader extends StatelessWidget {
  final double size;
  const PageLoader({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 48), child: Center(child: LogoLoader(size: size)));
}

/// Pull-to-refresh with the WebWeb mark: pulling down draws the W in step with the finger; past the
/// threshold a light haptic tick, and on release the mark keeps looping (the web loader) until
/// [onRefresh] completes. The [child] must be a vertical scrollable; this forces bouncing physics so the
/// pull feels the same on Android and iOS.
class LogoRefresh extends StatefulWidget {
  final Future<void> Function() onRefresh;
  final Widget child;
  const LogoRefresh({super.key, required this.onRefresh, required this.child});
  @override
  State<LogoRefresh> createState() => _LogoRefreshState();
}

class _LogoRefreshState extends State<LogoRefresh> {
  static const _threshold = 84.0;
  static const _slot = 64.0;
  double _pull = 0;
  bool _armed = false;
  bool _refreshing = false;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    if (n is ScrollUpdateNotification || n is OverscrollNotification) {
      final pull = (-n.metrics.pixels + n.metrics.minScrollExtent).clamp(0.0, 400.0);
      final dragging = (n is ScrollUpdateNotification && n.dragDetails != null) || (n is OverscrollNotification && n.dragDetails != null);
      if (!_refreshing) {
        if (dragging) {
          final armed = pull >= _threshold;
          if (armed && !_armed) HapticFeedback.lightImpact();
          _armed = armed;
        } else if (_armed) {
          _armed = false;
          _run();
        }
      }
      if (pull != _pull) setState(() => _pull = pull);
    } else if (n is ScrollEndNotification && _armed && !_refreshing) {
      _armed = false;
      _run();
    }
    return false;
  }

  Future<void> _run() async {
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = (_pull / _threshold).clamp(0.0, 1.0);
    return Stack(children: [
      Column(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          height: _refreshing ? _slot : 0,
          alignment: Alignment.center,
          child: _refreshing ? const LogoLoader(size: 34) : null,
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: ScrollConfiguration(
              behavior: const _Bouncy(),
              child: widget.child,
            ),
          ),
        ),
      ]),
      // while pulling: the mark sits in the gap above the list and draws itself
      if (!_refreshing && _pull > 4)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: _pull,
          child: Center(
            child: Opacity(
              opacity: (p * 1.6).clamp(0.0, 1.0),
              child: Transform.scale(scale: .6 + .4 * p, child: AnimatedLogo(size: 34, progress: p)),
            ),
          ),
        ),
    ]);
  }
}

/// iOS-style bounce on every platform, so the pull reveals the mark the same way on Android.
class _Bouncy extends ScrollBehavior {
  const _Bouncy();
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics());
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
}

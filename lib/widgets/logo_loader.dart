import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../logo_paths.dart';

/// The web app's loading animation: the W is drawn arm by arm on the gold ball, the dot pops in,
/// the slashes fade up, then everything fades out and repeats (CSS `logo-w-loop`, 1.6 s).
class LogoLoader extends StatefulWidget {
  final double size;
  const LogoLoader({super.key, this.size = 56});
  @override
  State<LogoLoader> createState() => _LogoLoaderState();
}

class _LogoLoaderState extends State<LogoLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  // layers are built once; only their clip / opacity / scale change per frame
  late final Widget _base = _layer(logoBaseSvg);
  late final Widget _arm1 = _layer(logoArm1Svg);
  late final Widget _arm2 = _layer(logoArm2Svg);
  late final Widget _s3 = _layer(logoSlash3Svg);
  late final Widget _s4 = _layer(logoSlash4Svg);
  late final Widget _dot = _layer(logoDotSvg);

  Widget _layer(String svg) => SvgPicture.string(svg, width: widget.size, height: widget.size * 82 / 84);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// 0..1 progress of t inside [a, b], eased out like the CSS (`ease-out`).
  static double _seg(double t, double a, double b, [Curve curve = Curves.easeOut]) =>
      curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  /// Everything holds until 80 % of the loop, then fades out by 94 %.
  static double _out(double t) => t < .80 ? 1 : (t < .94 ? 1 - (t - .80) / .14 : 0);

  @override
  Widget build(BuildContext context) {
    final h = widget.size * 82 / 84;
    return SizedBox(
      width: widget.size,
      height: h,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          final fade = _out(t);
          Widget arm(Widget w, double reveal) => Opacity(opacity: fade, child: ClipRect(clipper: _TopReveal(reveal), child: w));

          // dot: scale 0 -> 1.5 (29-38 %), settles to 1 (38-44 %)
          final dotScale = t < .29 ? 0.0 : (t < .38 ? 1.5 * _seg(t, .29, .38) : 1.5 - .5 * _seg(t, .38, .44));
          final dotOpacity = (t < .29 ? 0.0 : _seg(t, .29, .38)) * fade;
          final slash = _seg(t, .46, .67, Curves.easeInOut) * fade;

          return Stack(children: [
            _base,
            arm(_arm1, _seg(t, 0, .13)),
            arm(_arm2, _seg(t, .13, .27)),
            Opacity(opacity: slash, child: _s3),
            Opacity(opacity: slash, child: _s4),
            Opacity(
              opacity: dotOpacity.clamp(0.0, 1.0),
              child: Transform.scale(scale: dotScale, alignment: const Alignment(64.7605 / 84 * 2 - 1, 29.6996 / 82 * 2 - 1), child: _dot),
            ),
          ]);
        },
      ),
    );
  }
}

/// Reveals a layer from the top downwards (CSS `clip-path: inset(0 0 (1-p) 0)`).
class _TopReveal extends CustomClipper<Rect> {
  final double p;
  _TopReveal(this.p);
  @override
  Rect getClip(Size s) => Rect.fromLTWH(0, 0, s.width, s.height * p);
  @override
  bool shouldReclip(_TopReveal old) => old.p != p;
}

/// Centered loader for full-page / list loading states.
class PageLoader extends StatelessWidget {
  final double size;
  const PageLoader({super.key, this.size = 64});
  @override
  Widget build(BuildContext context) => Center(child: LogoLoader(size: size));
}

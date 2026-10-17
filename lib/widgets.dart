import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInputFormatter;
import 'package:flutter_svg/flutter_svg.dart';

import 'api.dart';
import 'icons.dart';
export 'icons.dart';
import 'models.dart' show Option;
import 'theme.dart';
import 'widgets/logo_loader.dart';
export 'widgets/logo_loader.dart';

// ---------- logo ----------

/// The original WebWeb logo (SVG copied from the web app).
class LogoMark extends StatelessWidget {
  final double size;
  const LogoMark({super.key, this.size = 46});
  @override
  Widget build(BuildContext context) => SvgPicture.asset('assets/logo_mark.svg', width: size, height: size * 82 / 84);
}
/// Mark + "WEBWEB" + "AI +" pill, stacked (as in the web side bar).
class LogoStack extends StatelessWidget {
  final double size;
  const LogoStack({super.key, this.size = 56});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      LogoMark(size: size),
      const SizedBox(height: 6),
      Text.rich(TextSpan(children: [
        TextSpan(text: 'WEB', style: TextStyle(color: p.text)),
        const TextSpan(text: 'WEB', style: TextStyle(color: kGold)),
      ]), style: TextStyle(fontSize: size * .24, fontWeight: FontWeight.w900, letterSpacing: .3)),
      const SizedBox(height: 3),
      Container(
        padding: EdgeInsets.symmetric(horizontal: size * .14, vertical: 1),
        decoration: BoxDecoration(color: kGold.withValues(alpha: .85), borderRadius: BorderRadius.circular(8)),
        child: Text('AI +', style: TextStyle(fontSize: size * .17, fontWeight: FontWeight.w900, color: const Color(0xFF1E1E1E))),
      ),
    ]);
  }
}

/// The WebWeb AI lockup from the web header (BrandLockup, stacked): circular mark, two-tone WEBWEB
/// wordmark (Akash 900) and the small AI pill underneath. Like the web, every tap replays the W build
/// on the mark and spins the AI star; [onTap] runs as well (the header uses it to go home).
class LogoInline extends StatefulWidget {
  final double size; // type scale (web: size 36, mark 44 in the phone header)
  final double? markSize;
  final VoidCallback? onTap;
  /// AI pill under the wordmark (app header, sign-in); false puts it beside the wordmark (web Logo withText)
  final bool stacked;
  const LogoInline({super.key, this.size = 36, this.markSize, this.onTap, this.stacked = true});
  @override
  State<LogoInline> createState() => _LogoInlineState();
}

class _LogoInlineState extends State<LogoInline> with SingleTickerProviderStateMixin {
  int _play = 0;
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
  static const _curve = Cubic(0.34, 1.3, 0.64, 1);

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  void _replay() {
    setState(() => _play++);
    _spin.forward(from: 0);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final size = widget.size;
    final word = (size * .5).roundToDouble();
    final pillH = (size * (widget.stacked ? .36 : .5)).roundToDouble();
    final pillFont = math.max(8, (size * (widget.stacked ? .24 : .28)).round()).toDouble();
    final goldWord = p.dark
        ? const LinearGradient(colors: [Color(0xFFFFD84A), Color(0xFFFFC700), Color(0xFFE0AD00)], stops: [0, .5, 1], begin: Alignment.topLeft, end: Alignment.bottomRight)
        : const LinearGradient(colors: [Color(0xFF7A5B00), Color(0xFFD9B53A), Color(0xFF9A7B00)], stops: [0, .45, 1], begin: Alignment.topLeft, end: Alignment.bottomRight);
    final starColor = p.dark ? '#ffd84a' : '#1e1e1e';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _replay,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        DecoratedBox(
          decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFF9B9542).withValues(alpha: .35), blurRadius: 6, offset: const Offset(0, 2))]),
          child: AnimatedLogo(size: widget.markSize ?? size, playKey: _play),
        ),
        const SizedBox(width: 8),
        Flex(direction: widget.stacked ? Axis.vertical : Axis.horizontal, mainAxisSize: MainAxisSize.min, crossAxisAlignment: widget.stacked ? CrossAxisAlignment.start : CrossAxisAlignment.center, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text('WEB', style: TextStyle(fontSize: word, fontWeight: FontWeight.w900, height: 1, letterSpacing: word * .02, color: p.text)),
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (r) => goldWord.createShader(r),
              child: Text('WEB', style: TextStyle(fontSize: word, fontWeight: FontWeight.w900, height: 1, letterSpacing: word * .02, color: Colors.white)),
            ),
          ]),
          SizedBox(height: widget.stacked ? 3 : 0, width: widget.stacked ? 0 : 4),
          Container(
            height: pillH,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(pillH),
              gradient: p.dark
                  ? const LinearGradient(colors: [Color(0xFF34322B), Color(0xFF1E1E1E)], begin: Alignment.topCenter, end: Alignment.bottomCenter)
                  : const LinearGradient(colors: [Color(0xFFFFE27A), Color(0xFFFFC700), Color(0xFFE6AC00)], stops: [0, .55, 1], begin: Alignment.topLeft, end: Alignment.bottomRight),
              border: Border.all(color: p.dark ? kGold.withValues(alpha: .6) : const Color(0xFFC9AE24).withValues(alpha: .7)),
              boxShadow: [BoxShadow(color: p.dark ? Colors.black.withValues(alpha: .4) : const Color(0xFF9A7B00).withValues(alpha: .35), blurRadius: 3, offset: const Offset(0, 1))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('AI', style: TextStyle(fontSize: pillFont, fontWeight: FontWeight.w700, height: 1, letterSpacing: pillFont * .06, color: p.dark ? const Color(0xFFFFD84A) : kInk)),
              const SizedBox(width: 3),
              // ai-spin: 0 -> 400deg at 1.25x (60 %), settles at 360deg / 1x
              AnimatedBuilder(
                animation: _spin,
                builder: (_, child) {
                  final t = _spin.value;
                  double turns = 0, scale = 1;
                  if (_spin.isAnimating) {
                    if (t < .6) {
                      final k = _curve.transform(t / .6);
                      turns = 400 / 360 * k;
                      scale = 1 + .25 * k;
                    } else {
                      final k = _curve.transform((t - .6) / .4);
                      turns = (400 - 40 * k) / 360;
                      scale = 1.25 - .25 * k;
                    }
                  }
                  return Transform.rotate(angle: turns * 2 * math.pi, child: Transform.scale(scale: scale, child: child));
                },
                child: SvgPicture.string(
                  '<svg viewBox="0 0 10 10" xmlns="http://www.w3.org/2000/svg"><path d="M5 0l1.2 3.8L10 5 6.2 6.2 5 10 3.8 6.2 0 5l3.8-1.2z" fill="$starColor"/></svg>',
                  width: pillFont - 1,
                  height: pillFont - 1,
                ),
              ),
            ]),
          ),
        ]),
      ]),
    );
  }
}

// ---------- small building blocks ----------

/// Room the floating island takes at the bottom; scrolling tab screens pad their lists by this much.
double islandSpace(BuildContext context) => 100 + MediaQuery.of(context).padding.bottom;

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts[0].substring(0, math.min(2, parts[0].length)).toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

/// "5m ago", "3h ago", "2d ago". Accepts a DateTime or an ISO-8601 string.
String timeAgo(Object when) {
  final d = when is DateTime ? when : DateTime.tryParse('$when')?.toLocal();
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
/// Same as the web's formatDistance.
String formatDistance(num m) {
  if (m <= 0) return '<1 km';
  if (m < 1000) return '${(m / 50).round() * 50} m';
  final km = m / 1000;
  return '${km < 10 ? km.toStringAsFixed(1) : km.round()} km';
}

/// Short ink pill at the bottom (web "flash" notes); red for errors.
void toast(BuildContext context, String msg, {bool error = false}) {
  final p = Pal.of(context);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg, textAlign: TextAlign.center, style: TextStyle(color: error ? Colors.white : p.onInk, fontWeight: FontWeight.w700, fontSize: 13)),
      backgroundColor: error ? p.danger : p.ink,
      duration: const Duration(seconds: 2),
      margin: const EdgeInsets.fromLTRB(40, 0, 40, 100),
    ));
}

/// The web's displayName: businesses show their company, job seekers their own name.
String displayName(String userType, String name, String company) => userType == 'entrepreneur' && company.isNotEmpty ? company : name;

/// Circle avatar like the web: cream fill with initials, optional gold "update" ring, and a small
/// type badge (briefcase = business, person = job seeker) on the 45 degree edge.
class Avatar extends StatelessWidget {
  final String name;
  final double size;
  final bool ring;
  final String? type; // 'entrepreneur' | 'job_seeker'
  final String? photoUrl;
  /// badge box size (web `badge` prop, default 16)
  final double badge;
  const Avatar({super.key, required this.name, this.size = 40, this.ring = false, this.type, this.photoUrl, this.badge = 16});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final ini = Text(initials(name), style: TextStyle(fontSize: size * .34, fontWeight: FontWeight.w700, color: p.muted));
    Widget face = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: p.chip),
      clipBehavior: Clip.antiAlias,
      child: (photoUrl ?? '').isNotEmpty
          ? NetImg(photoUrl!, width: size, height: size, fallback: ini)
          : ini,
    );
    if (ring) {
      face = Container(
        padding: const EdgeInsets.all(2.5),
        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: kGoldGradient),
        child: Container(padding: const EdgeInsets.all(2), decoration: BoxDecoration(shape: BoxShape.circle, color: p.card), child: face),
      );
    }
    if (type == null) return face;
    final outer = size + (ring ? 9 : 0);
    final b = (badge * .8).roundToDouble();
    final c = outer * .854;
    return SizedBox(
      width: outer,
      height: outer,
      child: Stack(clipBehavior: Clip.none, children: [
        face,
        Positioned(
          left: c - b / 2 - 2,
          top: c - b / 2 - 2,
          child: Container(
            width: b + 4,
            height: b + 4,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: p.typeBadge, border: Border.all(color: p.canvas, width: 2)),
            child: WIcon(type == 'entrepreneur' ? WI.business : WI.user, size: (badge * .62).roundToDouble(), color: p.onInk, strokeWidth: 2.2),
          ),
        ),
      ]),
    );
  }
}

/// Verification badges from the web (verified-badge.tsx): 1 green check circle (mobile verified),
/// 2 blue seal (documents), 3 gold seal with a star (owner verified, premium). Nothing for 0.
class VerifiedBadge extends StatelessWidget {
  final int level;
  final double size;
  const VerifiedBadge({super.key, this.level = 1, this.size = 16});
  static const _seal =
      'M12.00 0.85L12.72 0.97L13.41 1.32L14.03 1.80L14.59 2.32L15.13 2.77L15.69 3.08L16.31 3.26L17.01 3.32L17.78 3.35L18.56 3.45L19.29 3.69L19.88 4.12L20.31 4.71L20.55 5.44L20.65 6.22L20.68 6.99L20.74 7.69L20.92 8.31L21.23 8.87L21.68 9.41L22.20 9.97L22.68 10.59L23.03 11.28L23.15 12.00L23.03 12.72L22.68 13.41L22.20 14.03L21.68 14.59L21.23 15.13L20.92 15.69L20.74 16.31L20.68 17.01L20.65 17.78L20.55 18.56L20.31 19.29L19.88 19.88L19.29 20.31L18.56 20.55L17.78 20.65L17.01 20.68L16.31 20.74L15.69 20.92L15.13 21.23L14.59 21.68L14.03 22.20L13.41 22.68L12.72 23.03L12.00 23.15L11.28 23.03L10.59 22.68L9.97 22.20L9.41 21.68L8.87 21.23L8.31 20.92L7.69 20.74L6.99 20.68L6.22 20.65L5.44 20.55L4.71 20.31L4.12 19.88L3.69 19.29L3.45 18.56L3.35 17.78L3.32 17.01L3.26 16.31L3.08 15.69L2.77 15.13L2.32 14.59L1.80 14.03L1.32 13.41L0.97 12.72L0.85 12.00L0.97 11.28L1.32 10.59L1.80 9.97L2.32 9.41L2.77 8.87L3.08 8.31L3.26 7.69L3.32 6.99L3.35 6.22L3.45 5.44L3.69 4.71L4.12 4.12L4.71 3.69L5.44 3.45L6.22 3.35L6.99 3.32L7.69 3.26L8.31 3.08L8.87 2.77L9.41 2.32L9.97 1.80L10.59 1.32L11.28 0.97Z';
  @override
  Widget build(BuildContext context) {
    final body = switch (level) {
      1 => '<circle cx="12" cy="12" r="10" fill="#2f9e6b"/><path d="M7.6 12.3l3 3 5.8-6.2" fill="none" stroke="#fff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>',
      2 => '<path d="$_seal" fill="#0077E6"/><path d="M7.8 12.2l2.9 2.9 5.5-5.9" fill="none" stroke="#fff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>',
      3 => '<defs><linearGradient id="g" x1="3" y1="2" x2="21" y2="22" gradientUnits="userSpaceOnUse"><stop stop-color="#ffd84a"/><stop offset="1" stop-color="#e0ad00"/></linearGradient></defs>'
          '<path d="$_seal" fill="url(#g)" stroke="#b38600" stroke-width="0.8"/><path d="M12 6.6l1.5 3.2 3.5.4-2.6 2.4.7 3.5-3.1-1.8-3.1 1.8.7-3.5L7 10.2l3.5-.4L12 6.6z" fill="#fff" stroke="#fff" stroke-width="0.6" stroke-linejoin="round"/>',
      _ => null,
    };
    if (body == null) return const SizedBox.shrink();
    return SvgPicture.string('<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">$body</svg>', width: size, height: size);
  }
}

/// Meta chip under an ask (web Meta): rounded pill on the muted fill, small muted icon, semibold text.
class InfoPill extends StatelessWidget {
  final WI? wi;
  final String text;
  final VoidCallback? onTap;
  /// compact, for the feed card's chip row
  final bool small;
  const InfoPill({super.key, this.wi, required this.text, this.onTap, this.small = false});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final chip = Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 8 : 10, vertical: small ? 3 : 4),
      decoration: BoxDecoration(color: p.field, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (wi != null) ...[WIcon(wi!, size: small ? 12 : 14, color: p.muted), const SizedBox(width: 4)],
        // compact chips sit in a sideways-scrolling row (unbounded width), so no Flexible there
        if (small)
          Text(text, maxLines: 1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.text.withValues(alpha: .8)))
        else
          Flexible(child: Text(text, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.text.withValues(alpha: .8)))),
      ]),
    );
    return onTap == null ? chip : GestureDetector(onTap: onTap, child: chip);
  }
}

/// "✦ Same industry" match tag (web: rounded-full bg-gold/25, 11px bold, deep gold text).
class GoldTag extends StatelessWidget {
  final String text;
  final bool spark;
  const GoldTag(this.text, {super.key, this.spark = true});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: p.tagBg, borderRadius: BorderRadius.circular(20)),
      child: Text(spark ? '✦ $text' : text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.tagText)),
    );
  }
}

/// Web Button: gold gradient pill (default) or the cream "secondary" pill ([outlined]).
/// lucide Loader2 with animate-spin: a 3/4 ring turning once a second.
class Spinner extends StatefulWidget {
  final double size;
  final Color? color;
  const Spinner({super.key, this.size = 16, this.color});
  @override
  State<Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<Spinner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
        turns: _c,
        child: CustomPaint(size: Size.square(widget.size), painter: _ArcPainter(widget.color ?? Pal.of(context).text)),
      );
}

class _ArcPainter extends CustomPainter {
  final Color color;
  _ArcPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / 24 * 2; // lucide stroke 2 on a 24 grid
    final r = Rect.fromLTWH(0, 0, size.width, size.height).deflate(size.width * 3 / 24);
    canvas.drawArc(r, -math.pi / 2 + .45, math.pi * 1.6, false, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.color != color;
}

class GoldButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final WI? wi;
  final bool outlined;
  /// web sizes: sm 32, default 40, lg 48
  final double height;
  const GoldButton({super.key, required this.label, this.onPressed, this.loading = false, this.wi, this.outlined = false, this.height = 48});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final enabled = onPressed != null && !loading;
    final fg = outlined ? p.text : kInk;
    return Opacity(
      opacity: onPressed == null && !loading ? .5 : 1,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          height: height,
          decoration: BoxDecoration(
            gradient: outlined ? null : kGoldGradient,
            color: outlined ? p.chip : null,
            border: outlined ? Border.all(color: p.border.withValues(alpha: .7)) : null,
            borderRadius: BorderRadius.circular(height),
            boxShadow: outlined ? null : const [BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1))],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(height),
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: height >= 48 ? 24 : (height >= 40 ? 20 : 12)),
              child: Center(
                // web Button: a spinning Loader2 takes the icon's place, the label stays
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (loading) ...[Spinner(size: 16, color: fg), const SizedBox(width: 8)]
                  else if (wi != null) ...[WIcon(wi!, size: height >= 48 ? 20 : 16, color: fg, strokeWidth: 1.9), const SizedBox(width: 8)],
                  Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: height >= 48 ? 16 : 14, fontWeight: FontWeight.w700, color: fg))),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Filled, borderless text field matching the web inputs.
class AppField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hint, label, prefixText, errorText;
  /// small muted line under the field (web Field hint)
  final String? helper;
  final int maxLines;
  final TextInputType? keyboard;
  final ValueChanged<String>? onChanged, onSubmitted;
  final Widget? suffix, prefixIcon;
  final bool autofocus, enabled;
  final TextCapitalization caps;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  const AppField({
    super.key, this.controller, this.hint, this.label, this.prefixText, this.errorText, this.helper, this.maxLines = 1, this.keyboard,
    this.onChanged, this.onSubmitted, this.suffix, this.prefixIcon, this.autofocus = false, this.enabled = true,
    this.caps = TextCapitalization.none, this.maxLength, this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    OutlineInputBorder b(Color c) => OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (label != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(label!, style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 14))),
      TextField(
        controller: controller,
        autofocus: autofocus,
        enabled: enabled,
        maxLines: maxLines,
        maxLength: maxLength,
        inputFormatters: inputFormatters,
        keyboardType: keyboard,
        textCapitalization: caps,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: p.muted, fontWeight: FontWeight.w400),
          prefixText: prefixText,
          prefixIcon: prefixIcon,
          suffixIcon: suffix,
          counterText: '',
          errorText: errorText,
          filled: true,
          fillColor: p.card,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          border: b(p.border),
          enabledBorder: b(p.border),
          disabledBorder: b(p.border),
          focusedBorder: b(p.text),
          errorBorder: b(p.danger),
          focusedErrorBorder: b(p.danger),
        ),
      ),
      if (helper != null && errorText == null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(helper!, style: TextStyle(fontSize: 12, color: p.muted))),
    ]);
  }
}

/// Section title from the feed (web SectionTitle): icon, 13px semibold label, then a hairline that
/// fades from gold through the border colour to nothing.
class RuleHeading extends StatelessWidget {
  final WI icon;
  final String text;
  const RuleHeading(this.icon, this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Row(children: [
      WIcon(icon, size: 16, color: p.text),
      const SizedBox(width: 8),
      Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text)),
      const SizedBox(width: 8),
      Expanded(child: Container(height: 1, decoration: BoxDecoration(gradient: LinearGradient(colors: [kGold.withValues(alpha: .6), p.border, p.border.withValues(alpha: 0)])))),
    ]);
  }
}

/// Dashed outline card (empty states, "add photos").
class DashedBox extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;
  const DashedBox({super.key, required this.child, this.radius = 14, this.padding = const EdgeInsets.all(14), this.onTap, this.color});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: _DashPainter(color ?? p.border, radius),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  final Color color;
  final double r;
  _DashPainter(this.color, this.r);
  @override
  void paint(Canvas c, Size s) {
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(r)));
    final paint = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.2;
    for (final m in path.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        c.drawPath(m.extractPath(d, d + 5), paint);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

/// Network image that also draws SVGs (seed images on the site are SVG), with a quiet fallback.
class NetImg extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final double? width, height;
  final Alignment alignment;
  /// shown while loading and when the image fails (default: the plain chip fill)
  final Widget? fallback;
  const NetImg(this.url, {super.key, this.fit = BoxFit.cover, this.width, this.height, this.alignment = Alignment.center, this.fallback});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final u = mediaUrl(url);
    final fallback = this.fallback ?? Container(width: width, height: height, color: p.chip);
    if (Uri.tryParse(u)?.path.toLowerCase().endsWith('.svg') ?? false) {
      return SvgPicture.network(u, fit: fit, width: width, height: height, alignment: alignment, placeholderBuilder: (_) => fallback, errorBuilder: (_, __, ___) => fallback);
    }
    return Image.network(u, fit: fit, width: width, height: height, alignment: alignment, errorBuilder: (_, __, ___) => fallback,
        frameBuilder: (_, child, frame, sync) => sync || frame != null ? child : fallback);
  }
}

/// The web's EmptyState: logo mark, a title and an optional hint, centred.
class EmptyState extends StatelessWidget {
  final String title;
  final String? hint;
  const EmptyState({super.key, required this.title, this.hint});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Opacity(opacity: .9, child: LogoMark(size: 56)),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        if (hint != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(hint!, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: p.muted))),
      ]),
    );
  }
}

/// Ink / cream chip used for scopes and filters (web: rounded-full px-4 py-2 text-sm font-bold,
/// bg-ink when active, bg-secondary + muted text otherwise). [square] gives the web Chips look.
class ScopeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final WI? icon;
  final bool square;
  const ScopeChip({super.key, required this.label, required this.selected, required this.onTap, this.icon, this.square = false});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final fg = selected ? p.onInk : (square ? p.text : p.muted);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(horizontal: square ? 12 : 16, vertical: square ? 6 : 8),
        decoration: BoxDecoration(color: selected ? p.ink : p.chip, borderRadius: BorderRadius.circular(square ? 10 : 30)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[WIcon(icon!, size: 16, color: fg), const SizedBox(width: 6)],
          Text(label, style: TextStyle(fontSize: 14, height: 1.43, fontWeight: square ? FontWeight.w600 : FontWeight.w700, color: fg)),
        ]),
      ),
    );
  }
}

/// The web's native <select> as a pill: shows the choice (or the placeholder) with a chevron and
/// opens the options in a bottom sheet, like a phone's own picker.
class SelectPill extends StatelessWidget {
  final String value;
  final String placeholder;
  final List<Option> options;
  final ValueChanged<String> onChanged;
  final double height;
  final bool rounded;
  const SelectPill({super.key, required this.value, required this.placeholder, required this.options, required this.onChanged, this.height = 40, this.rounded = true});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    String label(String v) => options.firstWhere((o) => o.value == v, orElse: () => Option(v, v)).label;
    return GestureDetector(
      onTap: () async {
        final picked = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          backgroundColor: p.canvas,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
          builder: (ctx) => ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .7),
            child: ListView(shrinkWrap: true, padding: EdgeInsets.fromLTRB(8, 12, 8, MediaQuery.of(ctx).padding.bottom + 12), children: [
              for (final o in [Option('', placeholder), ...options])
                ListTile(
                  dense: true,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  title: Text(o.label, style: TextStyle(fontSize: 15, fontWeight: o.value == value ? FontWeight.w700 : FontWeight.w500)),
                  trailing: o.value == value ? WIcon(WI.check, size: 18, color: p.text, strokeWidth: 2) : null,
                  onTap: () => Navigator.pop(ctx, o.value),
                ),
            ]),
          ),
        );
        if (picked != null) onChanged(picked);
      },
      child: Container(
        height: height,
        padding: const EdgeInsets.only(left: 14, right: 10),
        decoration: BoxDecoration(color: p.card, border: Border.all(color: p.border), borderRadius: BorderRadius.circular(rounded ? height : 10)),
        child: Row(children: [
          Expanded(child: Text(value.isEmpty ? placeholder : label(value), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.text))),
          WIcon(WI.chevronDown, size: 16, color: p.muted),
        ]),
      ),
    );
  }
}

/// Default cover for members without a banner (web cover-pattern.ts): the gold gradient with one of
/// six soft line patterns picked from [seed], plus a white glow from the top right.
class CoverPattern extends StatelessWidget {
  final String seed;
  final Widget? child;
  const CoverPattern({super.key, required this.seed, this.child});
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _CoverPainter(seed), child: child ?? const SizedBox.expand());
}

class _CoverPainter extends CustomPainter {
  final int kind;
  _CoverPainter(String seed) : kind = _hash(seed) % 6;
  static int _hash(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0xFFFFFFFF;
    }
    return h;
  }

  @override
  void paint(Canvas c, Size s) {
    final r = Offset.zero & s;
    c.save();
    c.clipRect(r);
    c.drawRect(r, Paint()..shader = kGoldGradient.createShader(r));
    const ink = Color(0xFF1E1E1E);
    Paint stroke(double o, double w) => Paint()
      ..color = ink.withValues(alpha: o)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;
    Paint fill(double o) => Paint()..color = ink.withValues(alpha: o);
    final (tw, th) = switch (kind) { 0 => (22.0, 22.0), 1 => (32.0, 32.0), 2 => (24.0, 24.0), 3 => (60.0, 20.0), 4 => (48.0, 48.0), _ => (40.0, 20.0) };
    for (double y = 0; y < s.height; y += th) {
      for (double x = 0; x < s.width; x += tw) {
        c.save();
        c.translate(x, y);
        c.clipRect(Rect.fromLTWH(0, 0, tw, th));
        switch (kind) {
          case 0:
            c.drawCircle(const Offset(3, 3), 1.6, fill(.16));
          case 1:
            c.drawPath(Path()..moveTo(0, .5)..lineTo(32, .5)..moveTo(.5, 0)..lineTo(.5, 32), stroke(.1, 1));
          case 2:
            c.drawPath(Path()..moveTo(-6, 6)..lineTo(6, -6)..moveTo(0, 24)..lineTo(24, 0)..moveTo(18, 30)..lineTo(30, 18), stroke(.11, 3));
          case 3:
            c.drawPath(Path()..moveTo(0, 10)..quadraticBezierTo(15, 0, 30, 10)..quadraticBezierTo(45, 20, 60, 10), stroke(.14, 2));
          case 4:
            c.drawCircle(const Offset(24, 24), 14, stroke(.12, 2));
            c.drawCircle(const Offset(24, 24), 5, fill(.1));
          default:
            c.drawPath(Path()..moveTo(0, 20)..lineTo(20, 0)..lineTo(40, 20), stroke(.12, 2));
        }
        c.restore();
      }
    }
    // radial-gradient(120% 140% at 85% -20%, rgba(255,255,255,.35), transparent 55%)
    c.save();
    c.translate(s.width * .85, -s.height * .2);
    c.scale(s.width * 1.2, s.height * 1.4);
    c.drawCircle(Offset.zero, .55, Paint()..shader = RadialGradient(colors: [Colors.white.withValues(alpha: .35), Colors.white.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: Offset.zero, radius: .55)));
    c.restore();
    c.restore();
  }

  @override
  bool shouldRepaint(_CoverPainter old) => old.kind != kind;
}

/// A page pushed on top of the tabs: the app header's cream bar with a back chevron and a title
/// (the web keeps its header on these pages; the phone needs a way back).
class SubPage extends StatelessWidget {
  final String? title;
  final Widget? titleWidget;
  final List<Widget> actions;
  final Widget body;
  final Widget? bottom;
  const SubPage({super.key, this.title, this.titleWidget, this.actions = const [], required this.body, this.bottom});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: p.canvas,
      bottomNavigationBar: bottom,
      body: Column(children: [
        Container(
          padding: EdgeInsets.only(top: top),
          decoration: BoxDecoration(
            color: p.chip,
            boxShadow: [
              BoxShadow(
                color: p.dark ? Colors.black.withValues(alpha: .6) : const Color(0xFF1E1E1E).withValues(alpha: .2),
                offset: Offset(0, p.dark ? 8 : 6),
                blurRadius: p.dark ? 16 : 14,
                spreadRadius: -8,
              ),
            ],
          ),
          child: SizedBox(
            height: 56,
            child: Row(children: [
              const SizedBox(width: 4),
              Semantics(
                button: true,
                label: 'Back',
                child: InkResponse(
                  onTap: () => Navigator.maybePop(context),
                  radius: 22,
                  child: SizedBox(width: 44, height: 44, child: Center(child: WIcon(WI.back, size: 28, color: p.text))),
                ),
              ),
              Expanded(child: titleWidget ?? Text(title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
              ...actions,
              const SizedBox(width: 8),
            ]),
          ),
        ),
        Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: body)),
      ]),
    );
  }
}

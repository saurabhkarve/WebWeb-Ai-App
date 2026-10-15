import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInputFormatter;
import 'package:flutter_svg/flutter_svg.dart';

import 'api.dart';
import 'theme.dart';
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
        decoration: BoxDecoration(color: kGold.withOpacity(.85), borderRadius: BorderRadius.circular(8)),
        child: Text('AI +', style: TextStyle(fontSize: size * .17, fontWeight: FontWeight.w900, color: const Color(0xFF1E1E1E))),
      ),
    ]);
  }
}

/// Logo row for headers.
class LogoInline extends StatelessWidget {
  const LogoInline({super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const LogoMark(size: 32),
      const SizedBox(width: 8),
      Text.rich(TextSpan(children: [
        TextSpan(text: 'WEB', style: TextStyle(color: p.text)),
        const TextSpan(text: 'WEB', style: TextStyle(color: kGold)),
      ]), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      const SizedBox(width: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: kGold.withOpacity(.85), borderRadius: BorderRadius.circular(8)),
        child: const Text('AI +', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF1E1E1E))),
      ),
    ]);
  }
}

// ---------- small building blocks ----------

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
void toast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), backgroundColor: error ? Colors.red.shade700 : const Color(0xFF2B2B2B), duration: const Duration(seconds: 2)));
}

/// Round avatar with initials; [ring] draws the gold story ring, [type] adds the small corner badge.
class Avatar extends StatelessWidget {
  final String name;
  final double size;
  final bool ring;
  final String? type; // 'entrepreneur' | 'job_seeker'
  final String? photoUrl;
  const Avatar({super.key, required this.name, this.size = 48, this.ring = false, this.type, this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: p.field,
            border: ring ? Border.all(color: kGold, width: 3) : null,
          ),
          child: (photoUrl ?? '').isNotEmpty
              ? ClipOval(
                  child: Image.network(mediaUrl(photoUrl!), width: size, height: size, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Text(initials(name), style: TextStyle(fontSize: size * .32, fontWeight: FontWeight.w800, color: p.muted))),
                )
              : Text(initials(name), style: TextStyle(fontSize: size * .32, fontWeight: FontWeight.w800, color: p.muted)),
        ),
        if (type != null)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: size * .34,
              height: size * .34,
              decoration: BoxDecoration(color: const Color(0xFFF4F2EC), shape: BoxShape.circle, border: Border.all(color: p.canvas, width: 2)),
              child: Icon(type == 'entrepreneur' ? Icons.business_center_outlined : Icons.person_outline, size: size * .2, color: const Color(0xFF1E1E1E)),
            ),
          ),
      ]),
    );
  }
}

class VerifiedBadge extends StatelessWidget {
  final bool premium;
  const VerifiedBadge({super.key, this.premium = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Icon(Icons.verified, size: 16, color: kGreen),
      );
}

class PremiumBadge extends StatelessWidget {
  const PremiumBadge({super.key});
  @override
  Widget build(BuildContext context) =>
      const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.wb_sunny_rounded, size: 14, color: kGold));
}

/// Little rounded info chip: icon + text.
class InfoPill extends StatelessWidget {
  final IconData? icon;
  final String text;
  const InfoPill({super.key, this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(20), border: Border.all(color: p.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 15, color: p.muted), const SizedBox(width: 6)],
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
      ]),
    );
  }
}

/// Gold gradient "Near you" tag.
class GoldTag extends StatelessWidget {
  final String text;
  const GoldTag(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: p.tagBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: kGold.withOpacity(.35))),
      child: Text('✦ $text', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: p.dark ? kGold : const Color(0xFF8A6500))),
    );
  }
}

class GoldButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final bool outlined;
  const GoldButton({super.key, required this.label, this.onPressed, this.loading = false, this.icon, this.outlined = false});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final enabled = onPressed != null && !loading;
    return Opacity(
      opacity: onPressed == null && !loading ? .5 : 1,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          height: 52,
          decoration: BoxDecoration(
            gradient: outlined ? null : kGoldGradient,
            color: outlined ? p.chip : null,
            borderRadius: BorderRadius.circular(30),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(30),
            onTap: enabled ? onPressed : null,
            child: Center(
              child: loading
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: outlined ? p.text : p.onGold))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      if (icon != null) ...[Icon(icon, size: 18, color: outlined ? p.text : p.onGold), const SizedBox(width: 8)],
                      Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: outlined ? p.text : p.onGold)),
                    ]),
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
  final int maxLines;
  final TextInputType? keyboard;
  final ValueChanged<String>? onChanged, onSubmitted;
  final Widget? suffix, prefixIcon;
  final bool autofocus, enabled;
  final TextCapitalization caps;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  const AppField({
    super.key, this.controller, this.hint, this.label, this.prefixText, this.errorText, this.maxLines = 1, this.keyboard,
    this.onChanged, this.onSubmitted, this.suffix, this.prefixIcon, this.autofocus = false, this.enabled = true,
    this.caps = TextCapitalization.none, this.maxLength, this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    OutlineInputBorder b(Color c) => OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (label != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(label!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
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
        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: p.muted, fontWeight: FontWeight.w500),
          prefixText: prefixText,
          prefixIcon: prefixIcon,
          suffixIcon: suffix,
          counterText: '',
          errorText: errorText,
          filled: true,
          fillColor: p.field,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          border: b(p.border),
          enabledBorder: b(p.border),
          disabledBorder: b(p.border),
          focusedBorder: b(kGold),
          errorBorder: b(Colors.redAccent),
          focusedErrorBorder: b(Colors.redAccent),
        ),
      ),
    ]);
  }
}

/// Section heading with the thin gold rule used above Updates / Asks.
class RuleHeading extends StatelessWidget {
  final IconData icon;
  final String text;
  const RuleHeading(this.icon, this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Row(children: [
      Icon(icon, size: 16, color: p.muted),
      const SizedBox(width: 6),
      Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .8, color: p.muted)),
      const SizedBox(width: 10),
      Expanded(child: Container(height: 1, decoration: BoxDecoration(gradient: LinearGradient(colors: [kGold.withOpacity(.7), kGold.withOpacity(0)])))),
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

/// Image from the backend (or a placeholder icon).
class NetImage extends StatelessWidget {
  final String? path;
  final double size;
  final IconData fallback;
  const NetImage(this.path, {super.key, this.size = 56, this.fallback = Icons.image_outlined});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: size,
        height: size,
        color: p.field,
        child: (path ?? '').isEmpty
            ? Icon(fallback, color: p.muted)
            : Image.network(mediaUrl(path!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(fallback, color: p.muted)),
      ),
    );
  }
}


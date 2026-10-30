import 'package:flutter/material.dart';

import '../card_colors.dart';
import '../i18n.dart';
import '../theme.dart';

/// Under the ask's preview: the layout and the colour of its card, one tap each (web card-look.tsx).
class CardLookPicker extends StatelessWidget {
  final String color, style;
  final ValueChanged<String> onColor, onStyle;
  const CardLookPicker({super.key, required this.color, required this.style, required this.onColor, required this.onStyle});

  /// A tiny drawing of a layout, in the chosen colour, so the choice can be seen before it is made.
  Widget _thumb(Pal p, String s) {
    final tint = kCardColors[color]!;
    final solid = solidOf(color);
    Widget line(double w, {double a = .35}) => Container(width: w, height: 3, decoration: BoxDecoration(color: p.text.withValues(alpha: a), borderRadius: BorderRadius.circular(2)));
    final gold = Container(width: 18, height: 8, decoration: BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(4)));
    final poster = s == 'poster';
    Widget body;
    switch (s) {
      case 'banner':
        body = Column(children: [
          Container(height: 14, color: solid),
          Expanded(child: Padding(padding: const EdgeInsets.all(6), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [line(40), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [line(20, a: .2), gold])]))),
        ]);
      case 'poster':
        body = Padding(
          padding: const EdgeInsets.all(6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.center, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Container(width: 24, height: 3, color: Colors.white70),
            Container(width: 44, height: 4, color: Colors.white),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Container(width: 36, height: 8, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .85), borderRadius: BorderRadius.circular(3))), Container(width: 16, height: 8, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)))]),
          ]),
        );
      case 'badge':
        body = Padding(
          padding: const EdgeInsets.all(6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Container(width: 14, height: 14, decoration: BoxDecoration(color: solid, borderRadius: BorderRadius.circular(4))), const SizedBox(width: 4), line(28)]),
            const SizedBox(height: 6),
            line(44),
            const Spacer(),
            Container(height: 1, color: p.text.withValues(alpha: .12)),
            const SizedBox(height: 3),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [line(20, a: .2), gold]),
          ]),
        );
      default:
        body = Padding(padding: const EdgeInsets.all(6), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [line(24, a: .2), line(44), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [line(20, a: .2), gold])]));
    }
    return Container(
      width: 72,
      height: 52,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: poster
            ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(solid, Colors.white, .18)!, solid])
            : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tint.withValues(alpha: .28), tint.withValues(alpha: 0)]),
        border: Border.all(color: poster ? Colors.transparent : tint.withValues(alpha: .4)),
      ),
      child: body,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p.chip.withValues(alpha: .5), borderRadius: BorderRadius.circular(16), border: Border.all(color: p.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t('Card style'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted)),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final s in kCardStyles)
              Semantics(
                button: true,
                selected: style == s,
                label: t(kCardStyleLabels[s]!),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onStyle(s),
                  child: Container(
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: style == s ? kGold.withValues(alpha: .2) : Colors.transparent, borderRadius: BorderRadius.circular(12), border: Border.all(color: style == s ? kGold : Colors.transparent, width: 2)),
                    child: Column(children: [
                      _thumb(p, s),
                      const SizedBox(height: 4),
                      Text(t(kCardStyleLabels[s]!), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Text(t('Card colour'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted)),
          const SizedBox(width: 10),
          for (final e in kCardColors.entries)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onColor(e.key),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(color: e.value, shape: BoxShape.circle, border: Border.all(color: color == e.key ? p.text : Colors.transparent, width: 2)),
                  child: color == e.key ? const Icon(Icons.check, size: 13, color: Colors.white) : null,
                ),
              ),
            ),
        ]),
      ]),
    );
  }
}

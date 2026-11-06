import '../icons.dart';
import 'package:flutter/material.dart';

import '../card_colors.dart';
import '../theme.dart';
import '../i18n.dart' show t;

/// The layout and colour a deck's first card wears (card_colors.dart: classic, banner, poster, badge), the same as an
/// ask's headline card, with what to do on a reply: the card's one call to action (web DeckLook).
class DeckLook extends InheritedWidget {
  final String style, color;
  final String? emoji;
  final VoidCallback? onReply;
  /// the link the post carries: its preview is the deck's last card
  final String? link;
  const DeckLook({super.key, required this.style, required this.color, this.emoji, this.onReply, this.link, required super.child});

  static DeckLook? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<DeckLook>();

  @override
  bool updateShouldNotify(DeckLook old) => style != old.style || color != old.color || emoji != old.emoji || link != old.link;
}

/// A steady pick of layout from an id, the same on every screen (cardStyleOf for things that are not an ask).
String styleOfId(String id) {
  var h = 7;
  for (final u in id.codeUnits) {
    h = (h * 33 + u) & 0xFFFFFFFF;
  }
  return kCardStyles[h % kCardStyles.length];
}

/// A steady pick of colour from an id.
String colorOfId(String id) {
  var h = 0;
  for (final u in id.codeUnits) {
    h = (h * 31 + u) & 0xFFFFFFFF;
  }
  return kCardColors.keys.elementAt(h % kCardColors.length);
}

/// The gold pill on a card: "I can help" on an ask, "Reply" on a WEBWEB post. One look for every card.
class CardCta extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final double scale;
  final bool fill;
  /// a gold outline, no fill: the second button beside the main one (Talk)
  final bool outlined;
  const CardCta({super.key, required this.label, required this.onTap, this.scale = 1, this.fill = false, this.outlined = false});

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      height: (30 * scale).clamp(30.0, 36.0),
      constraints: BoxConstraints(minWidth: outlined ? 0 : (96 * scale).clamp(96.0, 120.0)),
      padding: EdgeInsets.symmetric(horizontal: outlined ? 14 : 18),
      alignment: Alignment.center,
      decoration: outlined ? BoxDecoration(border: Border.all(color: kGold, width: 1.5), borderRadius: BorderRadius.circular(20)) : BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Color(0x141E1E1E), blurRadius: 3, offset: Offset(0, 1))]),
      child: outlined
          ? Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              WIcon(WI.talk, size: 18, color: Pal.of(context).text),
              const SizedBox(width: 5),
              Flexible(child: Text(t(label), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: (13 * scale).clamp(12.5, 14.5), fontWeight: FontWeight.w700, color: Pal.of(context).text))),
            ])
          : Text(t(label), style: TextStyle(fontSize: (13 * scale).clamp(12.5, 14.5), fontWeight: FontWeight.w700, color: kInk)),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(height: 40, child: Align(alignment: fill ? Alignment.center : Alignment.centerLeft, child: fill ? SizedBox(width: double.infinity, child: pill) : IntrinsicWidth(child: pill))),
    );
  }
}

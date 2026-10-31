import 'package:flutter/material.dart';

import '../card_colors.dart';
import '../theme.dart';
import 'card_cta.dart';

/// Each WEBWEB house account's face, as on its cards.
const _face = {
  'webwebai': '✨',
  'webwebbazaar': '📊',
  'webwebtenders': '📄',
  'webwebtips': '💡',
  'webwebnews': '📰',
  'webwebquiz': '🧠',
  'webwebsourcing': '🛒',
  'webwebevents': '📅',
  'webwebjobs': '👷',
  'webwebspotlight': '🏆',
  'webwebfacts': '📊',
  'webwebdirectory': '📒',
};

bool isHouseHandle(String? handle) => handle != null && handle.startsWith('webweb');

/// A house account's text update as a card: one of the four layouts (classic, banner, poster, badge) in one of the
/// card colours, a steady pick from the update's id, so every account's tiles differ and look the same on every
/// screen (web HouseUpdateTile). [big] is the card in the feed and on the post page; small is the Updates tab's tile.
class HouseUpdateTile extends StatelessWidget {
  final String id, handle;
  final String? text;
  final bool big;
  const HouseUpdateTile({super.key, required this.id, required this.handle, this.text, this.big = false});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final color = colorOfId(id);
    final style = styleOfId(id);
    final tint = kCardColors[color]!;
    final solid = solidOf(color);
    final onSolid = onSolidOf(color);
    final emoji = _face[handle] ?? '✨';
    final radius = BorderRadius.circular(big ? 16 : 8);
    final pad = big ? 20.0 : 8.0;
    final poster = style == 'poster';
    final body = Text(
      text ?? '',
      maxLines: big ? null : (poster ? 6 : 5),
      overflow: big ? TextOverflow.visible : TextOverflow.ellipsis,
      textAlign: poster ? TextAlign.center : TextAlign.start,
      style: TextStyle(fontSize: big ? 17 : 11, fontWeight: FontWeight.w700, height: 1.3, color: poster ? onSolid : p.text),
    );
    final tinted = BoxDecoration(
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tint.withValues(alpha: .28), tint.withValues(alpha: 0)], stops: const [0, .8]),
      borderRadius: radius,
      border: Border.all(color: tint.withValues(alpha: .4)),
    );
    Widget card;
    if (poster) {
      card = Container(
        clipBehavior: Clip.antiAlias,
        padding: EdgeInsets.all(pad),
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [solid, Color.lerp(solid, Colors.black, .25)!]), borderRadius: radius),
        child: Stack(alignment: Alignment.center, children: [
          Positioned(right: -8, top: -8, child: Opacity(opacity: .2, child: Text(emoji, style: TextStyle(fontSize: big ? 96 : 60, height: 1)))),
          Center(child: body),
        ]),
      );
    } else if (style == 'banner') {
      card = Container(
        clipBehavior: Clip.antiAlias,
        decoration: tinted,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(height: big ? 36 : 28, color: solid, padding: EdgeInsets.symmetric(horizontal: big ? 16 : 8), alignment: Alignment.centerLeft, child: Text(emoji, style: TextStyle(fontSize: big ? 18 : 14, height: 1))),
          Expanded(child: Padding(padding: EdgeInsets.all(big ? 16 : 8), child: Align(alignment: Alignment.centerLeft, child: body))),
        ]),
      );
    } else if (style == 'badge') {
      card = Container(
        clipBehavior: Clip.antiAlias,
        padding: EdgeInsets.all(pad),
        decoration: tinted,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: big ? 44 : 32, height: big ? 44 : 32, alignment: Alignment.center, decoration: BoxDecoration(color: solid, borderRadius: BorderRadius.circular(12)), child: Text(emoji, style: TextStyle(fontSize: big ? 24 : 16, height: 1))),
          SizedBox(height: big ? 10 : 6),
          Expanded(child: Align(alignment: Alignment.topLeft, child: body)),
        ]),
      );
    } else {
      card = Container(
        clipBehavior: Clip.antiAlias,
        padding: EdgeInsets.all(pad),
        decoration: tinted,
        child: Stack(children: [
          Positioned(right: -4, top: -4, child: Opacity(opacity: .08, child: Text(emoji, style: TextStyle(fontSize: big ? 72 : 48, height: 1)))),
          Align(alignment: Alignment.centerLeft, child: body),
        ]),
      );
    }
    return big ? ConstrainedBox(constraints: const BoxConstraints(minHeight: 210), child: IntrinsicHeight(child: card)) : card;
  }
}

/// A house account's text post as a card at the width of the page, with the card's one button, Reply.
class HouseTextCard extends StatelessWidget {
  final String id, handle;
  final String? text;
  final VoidCallback onOpen, onReply;
  const HouseTextCard({super.key, required this.id, required this.handle, this.text, required this.onOpen, required this.onReply});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          GestureDetector(onTap: onOpen, child: HouseUpdateTile(id: id, handle: handle, text: text, big: true)),
          const SizedBox(height: 4),
          CardCta(label: 'Reply', onTap: onReply),
        ]),
      );
}

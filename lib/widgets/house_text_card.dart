import 'package:flutter/material.dart';

import '../card_colors.dart';
import '../theme.dart';
import '../i18n.dart' show t;
import '../links.dart' show openExternal;
import 'card_cta.dart';
import 'swipe_deck.dart';

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
  /// the post's own colour and layout, when it has them (else a steady pick from its id)
  final String? cardColor, cardStyle;
  const HouseUpdateTile({super.key, required this.id, required this.handle, this.text, this.big = false, this.cardColor, this.cardStyle});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final color = kCardColors.containsKey(cardColor) ? cardColor! : colorOfId(id);
    final style = kCardStyles.contains(cardStyle) ? cardStyle! : styleOfId(id);
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

const _kind = {
  'webwebai': 'From WEBWEB AI',
  'webwebbazaar': 'Facts & figures',
  'webwebtenders': 'Tenders and schemes',
  'webwebtips': 'Tip for your business',
  'webwebnews': 'Business news',
  'webwebquiz': 'Quiz',
  'webwebsourcing': 'Sourcing',
  'webwebevents': 'Events near you',
  'webwebjobs': 'Jobs and hiring',
  'webwebspotlight': 'Doing well near you',
  'webwebfacts': 'Facts & figures',
  'webwebdirectory': 'From the Directory',
};

/// The pieces of a house post's text: its headline, what follows in short cards, and its link (web textCards).
({String head, List<String> more, String? url, String? source}) textCards(String text) {
  final link = RegExp(r'https?://[^\s)]+');
  final paras = text.split(RegExp(r'\n{2,}')).map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
  String? url, source;
  final keep = <String>[];
  for (final p in paras) {
    if (RegExp(r'^Source:', caseSensitive: false).hasMatch(p)) {
      url = link.firstMatch(p)?.group(0);
      final s = p.replaceFirst(RegExp(r'^Source:\s*', caseSensitive: false), '').replaceAll(RegExp(r'https?://\S+'), '').trim();
      source = s.isEmpty ? null : s;
    } else {
      keep.add(p);
    }
  }
  url ??= link.firstMatch(text)?.group(0);
  var head = keep.isEmpty ? text : keep.first;
  final rest = keep.length > 1 ? keep.sublist(1) : <String>[];
  // one long paragraph: its first sentence is the headline, the rest follows on the next card
  if (rest.isEmpty && head.length > 120) {
    final m = RegExp(r'^(.{40,140}?[.!?])\s+([\s\S]+)$').firstMatch(head);
    if (m != null) {
      head = m.group(1)!;
      rest.add(m.group(2)!);
    }
  }
  final more = <String>[];
  for (final p in rest) {
    if (more.isNotEmpty && more.last.length + p.length < 260) {
      more[more.length - 1] = '${more.last}\n\n$p';
    } else {
      more.add(p);
    }
  }
  return (head: head, more: [for (final m in more.take(3)) m.replaceAll(RegExp(r'https?://\S+'), '').trim()].where((x) => x.isNotEmpty).toList(), url: url, source: source);
}

/// A house account's text post as swipeable cards: the headline first (complete on its own, with Reply), then what
/// follows in short cards, and last what to do (open the link, Reply). The first card in the post's own layout and colour.
class HouseTextCard extends StatefulWidget {
  final String id, handle;
  final String? text, cardColor, cardStyle;
  final VoidCallback onReply;
  const HouseTextCard({super.key, required this.id, required this.handle, this.text, this.cardColor, this.cardStyle, required this.onReply});
  @override
  State<HouseTextCard> createState() => _HouseTextCardState();
}

class _HouseTextCardState extends State<HouseTextCard> {
  final _ctl = DeckController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final c = textCards(widget.text ?? '');
    final color = kCardColors.containsKey(widget.cardColor) ? widget.cardColor! : colorOfId(widget.id);
    final emoji = _face[widget.handle] ?? '✨';
    final host = c.url == null ? '' : (Uri.tryParse(c.url!)?.host ?? '').replaceFirst('www.', '');
    final label = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.text.withValues(alpha: .6));
    final deckH = deckHeight(context);
    final cards = <Widget>[
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(c.head, maxLines: 5, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: deckH * .1, fontWeight: FontWeight.w800, height: 1.15, letterSpacing: -.3)),
        const Spacer(),
        Row(children: [
          CardCta(label: 'Reply', onTap: widget.onReply),
          if (c.more.isNotEmpty || c.url != null) ...[
            const SizedBox(width: 12),
            Flexible(child: Text('${t('Swipe for more')} →', maxLines: 1, overflow: TextOverflow.ellipsis, style: label)),
          ],
        ]),
      ]),
      for (var i = 0; i < c.more.length; i++)
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t(i == 0 ? 'In short' : 'More'), style: label),
          const SizedBox(height: 8),
          Text(c.more[i], maxLines: 8, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, height: 1.45)),
        ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('What next'), style: label),
        const SizedBox(height: 12),
        if (c.url != null) ...[
          CardCta(label: 'Read more', fill: true, onTap: () => openExternal(context, c.url!)),
          const SizedBox(height: 8),
        ],
        CardCta(label: 'Reply', fill: true, onTap: widget.onReply),
        const Spacer(),
        if (c.url != null) Text('🔗 ${t('Source')}: ${c.source ?? host}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.muted)),
      ]),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: DeckLook(
        style: kCardStyles.contains(widget.cardStyle) ? widget.cardStyle! : styleOfId(widget.id),
        color: color,
        emoji: emoji,
        child: SwipeDeck(cards: cards, tint: kCardColors[color]!, label: '$emoji ${t(_kind[widget.handle] ?? 'From WEBWEB')}', controller: _ctl),
      ),
    );
  }
}

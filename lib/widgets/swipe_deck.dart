import 'package:flutter/material.dart';

import '../card_colors.dart';
import '../theme.dart';
import '../links.dart' show LinkPreviewCard;
import 'card_cta.dart';

/// Lets the cards of a deck jump to another card.
class DeckController {
  final page = PageController(viewportFraction: .9);
  void go(int i) => page.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  void dispose() => page.dispose();
}

/// The height of a deck's cards (web --deck-h).
double deckHeight(BuildContext context) => (MediaQuery.sizeOf(context).height * .34).clamp(272.0, 340.0);

/// A swipeable deck of small cards, the same as the cards of an ask: a row above with a label on the left and small
/// dots (five at a time) on the right, one card at a time with the next peeking in. Used by the WEBWEB house posts and
/// the Facts posts (web swipe-deck.tsx).
class SwipeDeck extends StatefulWidget {
  final List<Widget> cards;
  final Color tint;
  final String label;
  final DeckController controller;
  const SwipeDeck({super.key, required this.cards, required this.tint, required this.label, required this.controller});
  @override
  State<SwipeDeck> createState() => _SwipeDeckState();
}

class _SwipeDeckState extends State<SwipeDeck> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    // a post's link is the last card: the page's picture, title and a Visit button (as on an ask)
    final link = DeckLook.of(context)?.link;
    final cards = [...widget.cards, if (link != null) LinkPreviewCard(link, key: ValueKey('deck-link-$link'), visit: true, flat: true, margin: EdgeInsets.zero)];
    final tint = widget.tint;
    final n = cards.length;
    final i = _i.clamp(0, n - 1);
    final start = (i - 2).clamp(0, (n - 5).clamp(0, n));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(child: Text(widget.label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.2, color: p.link))),
          if (n > 1)
            for (var k = start; k < n && k < start + 5; k++)
              GestureDetector(
                onTap: () => widget.controller.go(k),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 2),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: ((k == start && start > 0) || (k == start + 4 && start + 4 < n - 1)) ? 4 : 6,
                    height: ((k == start && start > 0) || (k == start + 4 && start + 4 < n - 1)) ? 4 : 6,
                    decoration: BoxDecoration(color: k == i ? p.text : p.text.withValues(alpha: .25), shape: BoxShape.circle),
                  ),
                ),
              ),
        ]),
      ),
      SizedBox(
        height: deckHeight(context),
        child: PageView.builder(
          controller: widget.controller.page,
          padEnds: false,
          itemCount: n,
          onPageChanged: (k) => setState(() => _i = k),
          itemBuilder: (_, k) => Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _DeckCard(tint: tint, first: k == 0, flush: link != null && k == n - 1, look: DeckLook.of(context), child: cards[k]),
          ),
        ),
      ),
    ]);
  }
}

/// One card of a deck: the same size and tint as an ask's cards; the first one in the deck's layout (classic, banner,
/// poster or badge) when the deck has one (web DeckCard).
class _DeckCard extends StatelessWidget {
  final Color tint;
  final bool first, flush;
  final DeckLook? look;
  final Widget child;
  const _DeckCard({required this.tint, required this.first, this.flush = false, required this.look, required this.child});

  @override
  Widget build(BuildContext context) {
    final style = first && look != null ? look!.style : 'classic';
    final solid = look == null ? tint : solidOf(look!.color);
    final emoji = look?.emoji;
    final poster = style == 'poster';
    final radius = BorderRadius.circular(16);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tint.withValues(alpha: poster ? .5 : .28), tint.withValues(alpha: poster ? .12 : 0)],
          stops: const [0, .8],
        ),
        borderRadius: radius,
        border: Border.all(color: tint.withValues(alpha: .4)),
      ),
      child: Stack(children: [
        if (style == 'banner') Positioned(left: 0, right: 0, top: 0, height: 10, child: ColoredBox(color: solid)),
        if (poster && emoji != null) Positioned(right: -6, top: -10, child: Opacity(opacity: .2, child: Text(emoji, style: const TextStyle(fontSize: 96, height: 1)))),
        if (style == 'badge' && emoji != null)
          Positioned(
            right: 12,
            top: 12,
            child: Container(width: 44, height: 44, alignment: Alignment.center, decoration: BoxDecoration(color: solid, borderRadius: BorderRadius.circular(14)), child: Text(emoji, style: const TextStyle(fontSize: 24, height: 1))),
          ),
        if (flush) Positioned.fill(child: child) else Padding(padding: EdgeInsets.fromLTRB(16, style == 'banner' ? 22 : 16, 16, 16), child: child),
      ]),
    );
  }
}

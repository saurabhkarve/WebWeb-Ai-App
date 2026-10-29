import 'package:flutter/material.dart';

import '../theme.dart';

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
    final cards = widget.cards;
    final tint = widget.tint;
    final n = cards.length;
    final i = _i.clamp(0, n - 1);
    final start = (i - 2).clamp(0, (n - 5).clamp(0, n));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(child: Text(widget.label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .4, color: p.link))),
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
            child: Container(
              padding: const EdgeInsets.all(16),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tint.withValues(alpha: .28), tint.withValues(alpha: 0)], stops: const [0, .8]),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: tint.withValues(alpha: .4)),
              ),
              child: cards[k],
            ),
          ),
        ),
      ),
    ]);
  }
}

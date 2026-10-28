import 'package:flutter/material.dart';
import '../card_colors.dart';
import '../i18n.dart';
import '../icons.dart';
import '../models.dart';
import '../theme.dart';
import 'area_map.dart' show askTimeLeft;

enum DeckKind { headline, photos, details, glance, act }

/// An ask as a short deck of cards you swipe (web ask-deck.tsx): the headline with its essentials, the photos, the
/// details, a glance at budget, place and timing, and a last card that asks "Can you help?". One swipe moves one card.
/// Used by the ask composer as a live preview: every card is there (empty ones invite you to fill them) and a tap on
/// a card goes to the part of the form that makes it.
class AskDeck extends StatefulWidget {
  final Post post;
  final List<ImageProvider> images;
  final String? reachLabel;
  final void Function(DeckKind kind)? onCardTap;
  const AskDeck({super.key, required this.post, this.images = const [], this.reachLabel, this.onCardTap});
  @override
  State<AskDeck> createState() => _AskDeckState();
}

class _AskDeckState extends State<AskDeck> {
  final _page = PageController(viewportFraction: .88);
  int _i = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final post = widget.post;
    final tint = kCardColors[cardColorOf(post)]!;
    const kinds = DeckKind.values;
    return Column(children: [
      SizedBox(
        height: 236,
        child: PageView.builder(
          controller: _page,
          padEnds: false,
          itemCount: kinds.length,
          onPageChanged: (i) => setState(() => _i = i),
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onCardTap?.call(kinds[i]),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tint.withValues(alpha: .28), tint.withValues(alpha: 0)], stops: const [0, .8]),
                  border: Border.all(color: tint.withValues(alpha: .4)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _card(p, kinds[i]),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var k = 0; k < kinds.length; k++)
          GestureDetector(
            onTap: () => _page.animateToPage(k, duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
              child: AnimatedContainer(duration: const Duration(milliseconds: 200), width: k == _i ? 20 : 6, height: 6, decoration: BoxDecoration(color: k == _i ? kGold : p.border, borderRadius: BorderRadius.circular(3))),
            ),
          ),
      ]),
    ]);
  }

  Widget _label(Pal p, String s) => Text(s.toUpperCase(), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .4, color: p.muted));

  Widget _chip(Pal p, WI icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: p.canvas.withValues(alpha: .7), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          WIcon(icon, size: 13, color: p.muted, still: true),
          const SizedBox(width: 4),
          Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.text.withValues(alpha: .8)))),
        ]),
      );

  Widget _card(Pal p, DeckKind kind) {
    final post = widget.post;
    final left = askTimeLeft(post);
    switch (kind) {
      case DeckKind.headline:
        final cat = post.categoryText;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              WIcon(categoryIcon(post.category), size: 14, color: p.link, still: true),
              const SizedBox(width: 6),
              Flexible(child: Text(t(cat).toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .4, color: p.link))),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                (post.title ?? '').isEmpty ? t('Your title shows here') : post.title!,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 21, height: 1.2, fontWeight: FontWeight.w800, color: (post.title ?? '').isEmpty ? p.muted : p.text),
              ),
            ),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if ((post.locationPref ?? '').isNotEmpty) _chip(p, WI.pin, t(post.locationPref!)),
              if (left != null) _chip(p, WI.clock, left),
              if ((post.budget ?? '').isNotEmpty) _chip(p, WI.rupee, post.budget!),
              if (widget.reachLabel != null) _chip(p, WI.locate, widget.reachLabel!),
            ]),
          ]),
        );
      case DeckKind.photos:
        return _photos(p);
      case DeckKind.details:
        final d = (post.description ?? '').trim();
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label(p, t('What is needed')),
            const SizedBox(height: 8),
            Expanded(child: Text(d.isEmpty ? t('Add the details: quantity, quality, timing.') : d, maxLines: 6, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15.5, height: 1.45, color: d.isEmpty ? p.muted : p.text))),
            Text('${t('Read the full ask')} →', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.link)),
          ]),
        );
      case DeckKind.glance:
        final none = (post.budget ?? '').isEmpty && (post.locationPref ?? '').isEmpty && left == null && post.radiusM == null;
        Widget tile(WI icon, String label, String value, [String? sub]) => Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: p.canvas.withValues(alpha: .7), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 20, height: 20, alignment: Alignment.center, decoration: BoxDecoration(color: kGold.withValues(alpha: .25), shape: BoxShape.circle), child: WIcon(icon, size: 12, color: p.text, still: true)),
                  const SizedBox(width: 6),
                  Flexible(child: Text(label.toUpperCase(), maxLines: 1, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: .3, color: p.muted))),
                ]),
                const SizedBox(height: 6),
                Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.2)),
                if (sub != null) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.muted)),
              ]),
            );
        final tiles = [
          if ((post.budget ?? '').isNotEmpty) tile(WI.rupee, t('Budget'), post.budget!),
          if ((post.locationPref ?? '').isNotEmpty) tile(WI.pin, t('Where'), t(post.locationPref!)),
          if (left != null) tile(WI.clock, t('When'), left),
          if (widget.reachLabel != null) tile(WI.locate, t('Reach'), widget.reachLabel!, t('around the place')),
        ];
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label(p, t('At a glance')),
            const SizedBox(height: 10),
            if (none) Text(t('Add where, when and budget so members can decide quickly.'), style: TextStyle(fontSize: 14, color: p.muted)),
            Expanded(
              child: GridView.count(crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.9, physics: const NeverScrollableScrollPhysics(), padding: EdgeInsets.zero, children: tiles),
            ),
          ]),
        );
      case DeckKind.act:
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label(p, t('Can you help?')),
            const SizedBox(height: 8),
            Row(children: [
              WIcon(WI.talk, size: 16, color: p.link, still: true),
              const SizedBox(width: 6),
              Text(t('No replies yet · be the first'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ]),
            const Spacer(),
            Container(
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(20)),
              child: Text(t('I can help'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
            ),
          ]),
        );
    }
  }

  /// 1 photo full; 2 side by side; 3 one tall and two stacked; 4 in a grid. Empty: a dashed invitation.
  Widget _photos(Pal p) {
    final imgs = widget.images.take(4).toList();
    if (imgs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(border: Border.all(color: p.border, width: 2), borderRadius: BorderRadius.circular(12)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('📷', style: TextStyle(fontSize: 30)),
            const SizedBox(height: 4),
            Text(t('Add photos'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.muted)),
            Text(t('Asks with photos get more replies'), style: TextStyle(fontSize: 12, color: p.muted)),
          ]),
        ),
      );
    }
    Widget img(ImageProvider i) => Image(image: i, fit: BoxFit.cover, width: double.infinity, height: double.infinity, errorBuilder: (_, __, ___) => ColoredBox(color: p.chip));
    const gap = 2.0;
    Widget body;
    if (imgs.length == 1) {
      body = img(imgs[0]);
    } else if (imgs.length == 2) {
      body = Row(children: [Expanded(child: img(imgs[0])), const SizedBox(width: gap), Expanded(child: img(imgs[1]))]);
    } else if (imgs.length == 3) {
      body = Row(children: [
        Expanded(child: img(imgs[0])),
        const SizedBox(width: gap),
        Expanded(child: Column(children: [Expanded(child: img(imgs[1])), const SizedBox(height: gap), Expanded(child: img(imgs[2]))])),
      ]);
    } else {
      body = Column(children: [
        Expanded(child: Row(children: [Expanded(child: img(imgs[0])), const SizedBox(width: gap), Expanded(child: img(imgs[1]))])),
        const SizedBox(height: gap),
        Expanded(child: Row(children: [Expanded(child: img(imgs[2])), const SizedBox(width: gap), Expanded(child: img(imgs[3]))])),
      ]);
    }
    return Stack(fit: StackFit.expand, children: [
      body,
      if (widget.images.length > 1)
        Positioned(
          left: 8,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xA61E1E1E), borderRadius: BorderRadius.circular(20)),
            child: Text(t('{n} photos', {'n': widget.images.length}), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ),
    ]);
  }
}

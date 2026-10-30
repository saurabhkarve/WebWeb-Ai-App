import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ask_types.dart';
import '../auth_provider.dart';
import '../card_events.dart';
import '../card_colors.dart';
import '../links.dart';
import 'hashtag_text.dart';
import '../i18n.dart';
import '../icons.dart';
import '../models.dart';
import '../theme.dart';
import '../location.dart' show kNodeCoords;
import 'area_map.dart' show AreaMap, askDeadline, askTimeLeft, showAreaViewer;
import 'image_grid.dart' show openImageViewer;
import 'poll_vote.dart';

enum DeckKind { headline, poll, photos, morePhotos, details, budget, link, map, glance, act }

/// An ask as a short deck of cards you swipe (web ask-deck.tsx): the headline with its essentials, the photos, the
/// details, a glance at budget, place and timing, and a last card that asks "Can you help?". One swipe moves one card.
/// Two uses:
/// - the feed (default): the cards the ask has (no empty ones), a tap opens the ask, "I can help" opens the reply
///   sheet, a poll is voted on in place, and how far members read is logged (card events);
/// - the composer's live preview ([preview]): every card is there (empty ones invite you to fill them) and a tap on a
///   card goes to the part of the form that makes it.
class AskDeck extends StatefulWidget {
  final Post post;
  final bool preview;
  /// the composer's local photos (the feed draws the ask's own)
  final List<ImageProvider> images;
  final String? reachLabel;
  final void Function(DeckKind kind)? onCardTap;
  final bool mine;
  final VoidCallback? onOpen, onReply;
  /// "View replies" on the last card: the ask, on its replies
  final VoidCallback? onReplies;
  /// double tap on the photos: the quick reaction
  final VoidCallback? onQuickReact;
  final void Function(Post voted)? onVoted;

  /// the feed card pins the ask type above the deck, so the first card does not repeat it
  final bool typeAbove;
  /// the row above the cards: the ask type and why you see it on the left, the dots on its right
  final Widget? lead;
  const AskDeck({super.key, required this.post, this.preview = false, this.images = const [], this.reachLabel, this.onCardTap, this.mine = false, this.onOpen, this.onReply, this.onReplies, this.onQuickReact, this.onVoted, this.typeAbove = false, this.lead});
  @override
  State<AskDeck> createState() => _AskDeckState();
}

class _AskDeckState extends State<AskDeck> {
  var _page = PageController(viewportFraction: .88);
  double _fr = .88;
  /// in the feed the swipe runs edge to edge (into the page's side margin, or a repost's frame) and the next card
  /// peeks in at the right, so it is clear there is more to swipe; the preview in the ask form stays inside its box
  static const _bleed = 16.0;
  int _i = 0;
  Timer? _look;

  Post get _post => widget.post;
  bool get _log => !widget.preview && !widget.mine;

  /// the cards this ask has: the feed leaves out the ones with nothing on them
  /// where the ask is, for the map card: its own point, else the centre of the place it names
  ({double lat, double lng})? get _mapPoint {
    final post = _post;
    if (post.lat != null && post.lng != null) return (lat: post.lat!, lng: post.lng!);
    final c = kNodeCoords[post.locationPref];
    return c == null ? null : (lat: c[0], lng: c[1]);
  }

  /// The cards' height follows the screen (about a third of it); the headline and the buttons follow the cards.
  double get _deckH => (MediaQuery.sizeOf(context).height * .34).clamp(272.0, 340.0);
  double get _scale => _deckH / 240;

  List<DeckKind> get _kinds {
    final post = _post;
    final left = askTimeLeft(post);
    return [
      DeckKind.headline,
      if (post.pollOptions.length > 1) DeckKind.poll,
      // a card for each photo (up to five), each with the ask's title; the composer's preview has one to invite adding photos
      if ((widget.preview ? widget.images.length : post.images.length) > 0) ...[
        for (var q = 0; q < (widget.preview ? widget.images.length : post.images.length) && q < 3; q++) DeckKind.photos,
        // more than three: the others share one card, "See all n photos" opens them in the lightbox
        if ((widget.preview ? widget.images.length : post.images.length) > 3) DeckKind.morePhotos,
      ] else if (widget.preview) DeckKind.photos,
      if (widget.preview || (post.description ?? '').trim().isNotEmpty) DeckKind.details,
      if ((post.budget ?? '').isNotEmpty) DeckKind.budget,
      // the preview of a link in the ask (picture, title, the site, a Visit button) is a card of its own
      if (post.fact == null && firstLink([post.title, post.description]) != null) DeckKind.link,
      if (_mapPoint != null) DeckKind.map,
      if (widget.preview || (post.locationPref ?? '').isNotEmpty || left != null || post.radiusM != null) DeckKind.glance,
      DeckKind.act,
    ];
  }

  @override
  void initState() {
    super.initState();
    _looked(0);
  }

  /// a card on screen for a moment counts as read; a move to another card is a swipe; the last one, "complete"
  void _looked(int i) {
    _look?.cancel();
    if (!_log) return;
    final n = _kinds.length;
    final api = context.read<AuthProvider>().api;
    _look = Timer(const Duration(milliseconds: 700), () {
      CardEvents.log(api, _post.id, 'view', i, n);
      if (i > 0) CardEvents.log(api, _post.id, 'swipe', i, n);
      if (i == n - 1) CardEvents.log(api, _post.id, 'complete', i, n);
    });
  }

  void _tap(DeckKind kind, int i) {
    if (widget.preview) return widget.onCardTap?.call(kind);
    // the map card opens the map, view only: drag and zoom, nothing to change
    if (kind == DeckKind.map && _mapPoint != null) {
      final pt = _mapPoint!;
      final pl = _post.locationPref ?? '';
      return unawaited(showAreaViewer(context, lat: pt.lat, lng: pt.lng, radiusM: (_post.radiusM ?? 10000).toDouble(), label: pl.isEmpty ? null : t(pl)));
    }
    if (_log) CardEvents.log(context.read<AuthProvider>().api, _post.id, 'cta', i, _kinds.length);
    widget.onOpen?.call();
  }

  @override
  void dispose() {
    _look?.cancel();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final post = widget.post;
    final tint = kCardColors[cardColorOf(post)]!;
    final kinds = _kinds;
    final bleed = widget.preview ? 0.0 : _bleed;
    // small dots, five at a time as in a photo carousel: the card you are on dark, the ends of the window smaller
    final dots = Builder(builder: (_) {
            final n = kinds.length;
            final start = (_i - 2).clamp(0, (n - 5).clamp(0, n));
            return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var k = start; k < n && k < start + 5; k++)
                GestureDetector(
                  onTap: () => _page.animateToPage(k, duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 2),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: ((k == start && start > 0) || (k == start + 4 && start + 4 < n - 1)) ? 4 : 6,
                      height: ((k == start && start > 0) || (k == start + 4 && start + 4 < n - 1)) ? 4 : 6,
                      decoration: BoxDecoration(color: k == _i ? p.text : p.text.withValues(alpha: .25), shape: BoxShape.circle),
                    ),
                  ),
                ),
            ]);
          });
    return Column(children: [
      if (widget.lead != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [Expanded(child: widget.lead!), dots])),
      SizedBox(
        height: _deckH,
        child: LayoutBuilder(builder: (context, box) {
        final v = box.maxWidth + 2 * bleed;
        final f = (.88 * box.maxWidth + bleed) / v;
        if ((f - _fr).abs() > .002) {
          final old = _page;
          _page = PageController(viewportFraction: f, initialPage: _i);
          _fr = f;
          WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
        }
        return OverflowBox(
        minWidth: v,
        maxWidth: v,
        child: SizedBox(width: v, child: PageView.builder(
          key: ValueKey(_fr),
          controller: _page,
          padEnds: false,
          itemCount: kinds.length,
          onPageChanged: (i) {
            setState(() => _i = i);
            _looked(i);
          },
          itemBuilder: (_, i) => Padding(
            padding: EdgeInsets.only(left: bleed, right: 10),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _tap(kinds[i], i),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  gradient: kinds[i] == DeckKind.headline && cardStyleOf(post) == 'poster'
                      ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(solidOf(cardColorOf(post)), Colors.white, .18)!, solidOf(cardColorOf(post))])
                      : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tint.withValues(alpha: .28), tint.withValues(alpha: 0)], stops: const [0, .8]),
                  border: Border.all(color: kinds[i] == DeckKind.headline && cardStyleOf(post) == 'poster' ? Colors.transparent : tint.withValues(alpha: .4)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _card(p, kinds[i], kinds.take(i).where((x) => x == DeckKind.photos).length),
              ),
            ),
          ),
        )),
        );
        }),
      ),
      if (widget.lead == null) ...[const SizedBox(height: 2), dots],
    ]);
  }

  Widget _label(Pal p, String s) => Text(s.toUpperCase(), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.2, color: p.muted));

  Widget _chip(Pal p, WI icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: p.canvas.withValues(alpha: .7), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          WIcon(icon, size: 13, color: p.muted, still: true),
          const SizedBox(width: 4),
          Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.text.withValues(alpha: .8)))),
        ]),
      );

  Widget _card(Pal p, DeckKind kind, [int photoAt = 0]) {
    final post = widget.post;
    final left = askTimeLeft(post);
    switch (kind) {
      case DeckKind.headline:
        final type = askTypeDef(askTypeOf(post)) ?? kAskTypes.last;
        final cat = askLabel(post);
        final sentence = askSentence(post);
        final thumbs = !widget.preview && post.images.isNotEmpty;
        final visitHref = post.askType == 'visit' ? firstLink([post.title, post.description]) : null;
        // the photos sit at the card's top right: the first lines keep clear of them
        final thumbPad = thumbs ? post.images.length.clamp(1, 4) * 48.0 + 12 : 0.0;
        // the layout the asker chose (card_colors.dart: classic, banner, poster, badge): same size and colours, arranged differently
        final style = cardStyleOf(post);
        final colorName = cardColorOf(post);
        final solid = solidOf(colorName);
        final onSolid = onSolidOf(colorName);
        final poster = style == 'poster', banner = style == 'banner';
        final fgTitle = poster ? onSolid : p.text;
        final fgSub = poster ? onSolid.withValues(alpha: .9) : p.text.withValues(alpha: .6);
        final fgLabel = poster || banner ? onSolid.withValues(alpha: .92) : p.link;
        Widget labelRow(double rightPad) => Row(mainAxisSize: poster ? MainAxisSize.min : MainAxisSize.max, children: [
              WIcon(categoryIcon(type.icon), size: 14, color: fgLabel, still: true),
              const SizedBox(width: 6),
              Flexible(child: Padding(padding: EdgeInsets.only(right: rightPad), child: Text(cat.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.2, color: fgLabel)))),
            ]);
        // who wants what, in a line: the idea of the ask before its details
        Widget sentenceRow({bool emoji = true, double rightPad = 0, bool center = false}) => Row(mainAxisAlignment: center ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
              if (emoji) ...[Text(type.emoji, style: const TextStyle(fontSize: 16)), const SizedBox(width: 6)],
              Flexible(child: Padding(padding: EdgeInsets.only(right: rightPad), child: Text(t(sentence.key, {...sentence.vars, if (sentence.vars['what'] != null) 'what': t(sentence.vars['what']!)}), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fgSub)))),
            ]);
        // as many lines as the space holds (at most 4), the last ending in "…": a long title never runs into the chips
        Widget titleW(double size, {double rightPad = 0, bool center = false}) => Padding(
              padding: EdgeInsets.only(right: rightPad),
              child: LayoutBuilder(builder: (context, c) {
                final line = size * _scale * 1.15 * MediaQuery.textScalerOf(context).scale(1);
                final lines = c.maxHeight.isFinite ? (c.maxHeight / line).floor().clamp(1, 4) : 4;
                return HashtagText(
                  (post.title ?? '').isEmpty ? t('Your title shows here') : post.title!,
                  maxLines: lines,
                  overflow: TextOverflow.ellipsis,
                  textAlign: center ? TextAlign.center : TextAlign.start,
                  style: TextStyle(fontSize: size * _scale, height: 1.15, letterSpacing: -.4, fontWeight: FontWeight.w700, color: (post.title ?? '').isEmpty ? (poster ? onSolid.withValues(alpha: .7) : p.muted) : fgTitle),
                );
              }),
            );
        final chips = Wrap(spacing: 6, runSpacing: 6, children: [
          if ((post.locationPref ?? '').isNotEmpty) _chip(p, WI.pin, t(post.locationPref!)),
          if (left != null) _chip(p, WI.clock, askDeadline(post) != null ? '$left · ${askDeadline(post)}' : left),
          if ((post.budget ?? '').isNotEmpty) _chip(p, WI.rupee, post.budget!),
          if (widget.reachLabel != null) _chip(p, WI.locate, widget.reachLabel!),
        ]);
        Widget? cta() {
          if (widget.preview || (visitHref == null && widget.mine)) return null;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_log) CardEvents.log(context.read<AuthProvider>().api, post.id, 'cta', 0, _kinds.length);
              if (visitHref != null) {
                openExternal(context, visitHref);
              } else {
                widget.onReply?.call();
              }
            },
            child: Container(
              height: (40 * _scale).clamp(38.0, 46.0),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              alignment: Alignment.center,
              decoration: BoxDecoration(gradient: poster ? null : kGoldGradient, color: poster ? p.canvas : null, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Color(0x331E1E1E), blurRadius: 6, offset: Offset(0, 2))]),
              child: Text(t(visitHref != null ? 'Visit website' : 'I can help'), style: TextStyle(fontSize: (14 * _scale).clamp(13.0, 16.0), fontWeight: FontWeight.w700, color: poster ? p.text : kInk)),
            ),
          );
        }
        // the chips across the card's full width, then (when the ask is not yours) "I can help" as a full-width button
        Widget foot({bool tray = false}) {
          final c = cta();
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            tray ? Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: p.canvas.withValues(alpha: .9), borderRadius: BorderRadius.circular(16)), child: chips) : chips,
            if (c != null) ...[const SizedBox(height: 10), c],
          ]);
        }

        final Widget card;
        if (banner) {
          card = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              color: solid,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (!widget.typeAbove) ...[labelRow(thumbs ? 118 : 0), const SizedBox(height: 6)],
                sentenceRow(rightPad: thumbPad),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: titleW(26)), const SizedBox(height: 8), foot()]),
              ),
            ),
          ]);
        } else if (poster) {
          card = Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (!widget.typeAbove) ...[Center(child: labelRow(0)), const SizedBox(height: 4)],
              sentenceRow(center: true),
              Expanded(child: Center(child: titleW(30, center: true))),
              foot(tray: true),
            ]),
          );
        } else if (style == 'badge') {
          card = Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 48, height: 48, alignment: Alignment.center, decoration: BoxDecoration(color: solid, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Color(0x261E1E1E), blurRadius: 4, offset: Offset(0, 1))]), child: Text(type.emoji, style: const TextStyle(fontSize: 26, height: 1))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (!widget.typeAbove) ...[labelRow(thumbs ? 118 : 0), const SizedBox(height: 4)],
                    sentenceRow(emoji: false, rightPad: thumbPad),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              Expanded(child: titleW(24, rightPad: 0)),
              Container(height: 1, color: p.text.withValues(alpha: .1), margin: const EdgeInsets.only(bottom: 10)),
              foot(),
            ]),
          );
        } else {
          card = Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (!widget.typeAbove) ...[labelRow(thumbs ? 118 : 0), const SizedBox(height: 8)],
              sentenceRow(rightPad: thumbPad),
              const SizedBox(height: 8),
              Expanded(child: titleW(26, rightPad: thumbPad)),
              const SizedBox(height: 8),
              foot(),
            ]),
          );
        }
        if (!thumbs) return card;
        // the photos, small: a tap opens them big, a double tap is the quick reaction
        final urls = post.images;
        return Stack(children: [
          card,
          Positioned(
            right: 12,
            top: 12,
            child: Row(children: [
              for (var k = 0; k < urls.length && k < 3; k++)
                Padding(
                  padding: EdgeInsets.only(left: k == 0 ? 0 : 4),
                  child: GestureDetector(
                    onTap: () => openImageViewer(context, urls, k, shareUrl: post.webUrl, shareRef: post.id),
                    onDoubleTap: widget.mine ? null : widget.onQuickReact,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white.withValues(alpha: .25)), color: p.chip),
                      clipBehavior: Clip.antiAlias,
                      child: Image.network(urls[k], fit: BoxFit.cover, errorBuilder: (_, __, ___) => ColoredBox(color: p.chip)),
                    ),
                  ),
                ),
              // the 4th tile: the next picture dimmed under "+N", it opens them all
              if (urls.length > 3)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: GestureDetector(
                    onTap: () => openImageViewer(context, urls, 3, shareUrl: post.webUrl, shareRef: post.id),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white.withValues(alpha: .25)), color: p.chip),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(fit: StackFit.expand, children: [
                        Image.network(urls[3], fit: BoxFit.cover, errorBuilder: (_, __, ___) => ColoredBox(color: p.chip)),
                        Container(color: kInk.withValues(alpha: .6), alignment: Alignment.center, child: Text('+${urls.length - 3}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white))),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ]);
      case DeckKind.poll:
        if (!widget.preview) {
          // vote right on the card; the bars show what members chose once you have (or on your own poll)
          return SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
            child: PollVote(post: post, mine: widget.mine, onVoted: (v) => widget.onVoted?.call(v)),
          );
        }
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label(p, t('Choose one option')),
            const SizedBox(height: 8),
            for (var k = 0; k < post.pollOptions.length; k++)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: p.canvas.withValues(alpha: .7), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const OptionMark(OptionState.open),
                  const SizedBox(width: 8),
                  Expanded(child: Text(post.pollOptions[k], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                ]),
              ),
          ]),
        );
      case DeckKind.photos:
        return _photos(p, photoAt);
      case DeckKind.morePhotos:
        return _morePhotos(p);
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
      case DeckKind.budget:
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label(p, t('Budget')),
            const Spacer(),
            Text(post.budget ?? '', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, height: 1.15, letterSpacing: -.3)),
            if (left != null) Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [WIcon(WI.clock, size: 14, color: p.muted, still: true), const SizedBox(width: 4), Text(left, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.muted))])),
          ]),
        );
      case DeckKind.link:
        return LinkPreviewCard(firstLink([post.title, post.description])!, key: ValueKey('deck-${post.id}'), visit: true, margin: EdgeInsets.zero, flat: true);
      case DeckKind.map:
        final pt = _mapPoint!;
        final place = (post.locationPref ?? '').isEmpty ? t('Where') : t(post.locationPref!);
        return Stack(fit: StackFit.expand, children: [
          AreaMap(lat: pt.lat, lng: pt.lng, radiusM: (post.radiusM ?? 10000).toDouble()),
          Positioned(
            left: 10,
            top: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: const Color(0xBF1E1E1E), borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const WIcon(WI.pin, size: 14, color: Colors.white, still: true),
                const SizedBox(width: 4),
                Text(post.radiusM != null && widget.reachLabel != null ? '$place · ${widget.reachLabel}' : place, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
              ]),
            ),
          ),
        ]);
      case DeckKind.glance:
        final none = (post.locationPref ?? '').isEmpty && left == null && post.radiusM == null;
        Widget tile(WI icon, String label, String value, [String? sub]) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: p.canvas.withValues(alpha: .7), borderRadius: BorderRadius.circular(12)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 20, height: 20, alignment: Alignment.center, decoration: BoxDecoration(color: kGold.withValues(alpha: .25), shape: BoxShape.circle), child: WIcon(icon, size: 12, color: p.text, still: true)),
                  const SizedBox(width: 6),
                  Flexible(child: Text(label.toUpperCase(), maxLines: 1, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.15, color: p.muted))),
                ]),
                const SizedBox(height: 4),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.2)),
                if (sub != null) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.muted)),
              ]),
            );
        final tiles = [
          if ((post.locationPref ?? '').isNotEmpty) tile(WI.pin, t('Where'), t(post.locationPref!)),
          if (left != null) tile(WI.clock, t('When'), left),
          if (widget.reachLabel != null) tile(WI.locate, t('Reach'), widget.reachLabel!, t('around the place')),
        ];
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label(p, t('At a glance')),
            const SizedBox(height: 8),
            if (none) Text(t('Add where, when and budget so members can decide quickly.'), style: TextStyle(fontSize: 14, color: p.muted)),
            Expanded(
              child: GridView(gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8, mainAxisExtent: 76), physics: const NeverScrollableScrollPhysics(), padding: EdgeInsets.zero, children: tiles),
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
              Flexible(child: Text(post.sharesCount == 0 ? t('No replies yet · be the first') : t(post.sharesCount == 1 ? '{n} reply so far' : '{n} replies so far', {'n': post.sharesCount}), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
            ]),
            if (post.sharesCount > 0 && !widget.preview && widget.onReplies != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onReplies,
                  child: Text('${t('View replies')} →', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.link)),
                ),
              ),
            if (post.viewsCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  WIcon(WI.views, size: 14, color: p.muted, still: true),
                  const SizedBox(width: 6),
                  Text(t(post.viewsCount == 1 ? '{n} member has seen it' : '{n} members have seen it', {'n': post.viewsCount}), style: TextStyle(fontSize: 12, color: p.muted)),
                ]),
              ),
            const Spacer(),
            if (!widget.preview && post.closed)
              Text(t('This ask is closed'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.muted))
            else
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // the reply sheet right here: one tap to answer, no trip to the ask first
                onTap: widget.preview
                    ? null
                    : () {
                        if (_log) CardEvents.log(context.read<AuthProvider>().api, post.id, 'cta', _kinds.length - 1, _kinds.length);
                        // a Visit ask: the button is its link, opened away from WEBWEB
                        final visit = post.askType == 'visit' ? firstLink([post.title, post.description]) : null;
                        if (visit != null) {
                          openExternal(context, visit);
                          return;
                        }
                        (widget.mine ? widget.onOpen : widget.onReply)?.call();
                      },
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(18)),
                  child: Text(t(post.askType == 'visit' && firstLink([post.title, post.description]) != null ? 'Visit website' : (widget.mine ? 'Review responses' : 'I can help')), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
                ),
              ),
              ),
          ]),
        );
    }
  }

  /// 1 photo full; 2 side by side; 3 one tall and two stacked; 4 in a grid. Empty: a dashed invitation.
  /// The card after the third photo: the others as tiles under one "See all n photos", which opens them all big.
  Widget _morePhotos(Pal p) {
    final all = widget.preview ? widget.images : [for (final u in _post.images) NetworkImage(u) as ImageProvider];
    final rest = all.skip(3).take(4).toList();
    Widget tile(ImageProvider i) => Image(image: i, fit: BoxFit.cover, width: double.infinity, height: double.infinity, errorBuilder: (_, __, ___) => ColoredBox(color: p.chip));
    const gap = 2.0;
    Widget grid;
    if (rest.length == 1) {
      grid = tile(rest[0]);
    } else if (rest.length == 2) {
      grid = Row(children: [Expanded(child: tile(rest[0])), const SizedBox(width: gap), Expanded(child: tile(rest[1]))]);
    } else if (rest.length == 3) {
      grid = Row(children: [
        Expanded(child: tile(rest[0])),
        const SizedBox(width: gap),
        Expanded(child: Column(children: [Expanded(child: tile(rest[1])), const SizedBox(height: gap), Expanded(child: tile(rest[2]))])),
      ]);
    } else {
      grid = Column(children: [
        Expanded(child: Row(children: [Expanded(child: tile(rest[0])), const SizedBox(width: gap), Expanded(child: tile(rest[1]))])),
        const SizedBox(height: gap),
        Expanded(child: Row(children: [Expanded(child: tile(rest[2])), const SizedBox(width: gap), Expanded(child: tile(rest[3]))])),
      ]);
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.preview ? null : () => openImageViewer(context, _post.images, 3, shareUrl: _post.webUrl, shareRef: _post.id),
      child: Stack(fit: StackFit.expand, children: [
        grid,
        Container(color: const Color(0x731E1E1E), alignment: Alignment.center, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: Text(t('See all {n} photos', {'n': all.length}), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
        )),
      ]),
    );
  }

  Widget _photos(Pal p, int at) {
    final all = widget.preview ? widget.images : [for (final u in _post.images) NetworkImage(u) as ImageProvider];
    if (all.isEmpty) {
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
    // one photo on its own card, the ask's title along the foot
    final i = at.clamp(0, all.length - 1);
    final w = Image(image: all[i], fit: BoxFit.cover, width: double.infinity, height: double.infinity, errorBuilder: (_, __, ___) => ColoredBox(color: p.chip));
    final title = (_post.title ?? '').trim();
    return Stack(fit: StackFit.expand, children: [
      widget.preview
          ? w
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              // a tap opens the photos big; a double tap is the quick reaction
              onTap: () => openImageViewer(context, _post.images, i, shareUrl: _post.webUrl, shareRef: _post.id),
              onDoubleTap: widget.mine ? null : widget.onQuickReact,
              child: w,
            ),
      if (title.isNotEmpty)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 36, 16, 12),
              decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x001E1E1E), Color(0xCC1E1E1E)])),
              child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, height: 1.3, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ),
      if (all.length > 1)
        Positioned(
          right: 8,
          top: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xA61E1E1E), borderRadius: BorderRadius.circular(20)),
            child: Text('${i + 1} / ${all.length}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white, fontFeatures: [FontFeature.tabularFigures()])),
          ),
        ),
    ]);
  }
}

import 'package:flutter/material.dart';

import '../ask_types.dart';
import '../card_colors.dart';
import '../i18n.dart';
import '../location.dart' show kNodeCoords;
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'area_map.dart' show AreaMap, askTimeLeft, showAreaViewer;
import '../links.dart';
import 'hashtag_text.dart';
import 'image_grid.dart';

/// The ask's own page in the same card UI as the deck, all the cards open one under the other (nothing to swipe): the
/// headline with its chips, the details, the photos, then budget, timing, place and reach as tiles, and the map
/// (web ask-deck.tsx AskCards).
class AskCards extends StatelessWidget {
  final Post post;
  /// the closed / "why you see this" chip, top right of the headline
  final Widget? chip;
  /// the essentials as chips (they open Find on a tap)
  final Widget? chips;
  const AskCards({super.key, required this.post, this.chip, this.chips});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final type = askTypeDef(askTypeOf(post)) ?? kAskTypes.last;
    final tone = kCardColors[cardColorOf(post)]!;
    final s = askSentence(post);
    final left = askTimeLeft(post);
    final c = post.locationPref == null ? null : kNodeCoords[post.locationPref];
    final point = post.lat != null && post.lng != null ? (lat: post.lat!, lng: post.lng!) : (c == null ? null : (lat: c[0], lng: c[1]));
    Widget card(Widget child, {EdgeInsets pad = const EdgeInsets.all(16)}) => Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: pad,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tone.withValues(alpha: .38)),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tone.withValues(alpha: .26), tone.withValues(alpha: .08), Colors.transparent]),
          ),
          child: child,
        );
    Widget label(String s) => Text(s.toUpperCase(), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .4, color: p.muted));
    Widget tile(WI icon, String name, String value, [String? sub]) => Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: p.canvas.withValues(alpha: .7), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 20, height: 20, alignment: Alignment.center, decoration: BoxDecoration(color: kGold.withValues(alpha: .25), shape: BoxShape.circle), child: WIcon(icon, size: 12, color: p.text, still: true)),
              const SizedBox(width: 6),
              Flexible(child: Text(name.toUpperCase(), maxLines: 1, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: .3, color: p.muted))),
            ]),
            const SizedBox(height: 6),
            Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.2)),
            if (sub != null) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.muted)),
          ]),
        );
    final tiles = [
      if ((post.budget ?? '').isNotEmpty) tile(WI.rupee, t('Budget'), post.budget!),
      if (left != null) tile(WI.clock, t('When'), left, t('Posted {t}', {'t': timeAgo(post.createdAt)})),
      if ((post.locationPref ?? '').isNotEmpty) tile(WI.pin, t('Where'), t(post.locationPref!), post.distanceM == null ? null : t('{d} from you', {'d': formatDistance(post.distanceM!)})),
      if ((post.radiusM ?? 0) > 0) tile(WI.locate, t('Reach'), formatDistance(post.radiusM!), t('around the place')),
    ];
    final place = (post.locationPref ?? '').isEmpty ? t('Where') : t(post.locationPref!);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          WIcon(categoryIcon(type.icon), size: 14, color: p.link, still: true),
          const SizedBox(width: 6),
          Expanded(child: Text(askLabel(post).toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .4, color: p.link))),
          if (chip != null) ...[const SizedBox(width: 8), Flexible(child: chip!)],
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Text(type.emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Expanded(child: Text(t(s.key, {...s.vars, if (s.vars['what'] != null) 'what': t(s.vars['what']!)}), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.text.withValues(alpha: .75)))),
        ]),
        const SizedBox(height: 6),
        HashtagText(askText(post.askType, post.title), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -.3)),
        if (chips != null) ...[const SizedBox(height: 12), chips!],
      ])),
      if (askText(post.askType, post.description).trim().isNotEmpty)
        card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          label(t('What is needed')),
          const SizedBox(height: 8),
          HashtagText(askText(post.askType, post.description), selectable: true, style: TextStyle(fontSize: 15, height: 1.4, color: p.text.withValues(alpha: .85))),
        ])),
      if (post.askType == 'visit' && firstLink([post.title, post.description]) != null)
        LinkPreviewCard(firstLink([post.title, post.description])!, key: ValueKey(post.id), visit: true, margin: EdgeInsets.zero),
      if (post.images.isNotEmpty) card(ImageGrid(post.images, shareUrl: post.webUrl, shareRef: post.id), pad: const EdgeInsets.all(8)),
      if (tiles.isNotEmpty)
        card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          label(t('At a glance')),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (context, box) {
            final w = (box.maxWidth - 8) / 2;
            return Wrap(spacing: 8, runSpacing: 8, children: [for (final x in tiles) SizedBox(width: w, child: x)]);
          }),
        ])),
      if (point != null)
        card(
          GestureDetector(
            onTap: () => showAreaViewer(context, lat: point.lat, lng: point.lng, radiusM: (post.radiusM ?? 10000).toDouble(), label: (post.locationPref ?? '').isEmpty ? null : t(post.locationPref!)),
            child: SizedBox(
            height: 176,
            child: Stack(fit: StackFit.expand, children: [
              AreaMap(lat: point.lat, lng: point.lng, radiusM: (post.radiusM ?? 10000).toDouble()),
              Positioned(
                left: 10,
                top: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: const Color(0xBF1E1E1E), borderRadius: BorderRadius.circular(99)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const WIcon(WI.pin, size: 14, color: Colors.white, still: true),
                    const SizedBox(width: 4),
                    Text((post.radiusM ?? 0) > 0 ? '$place · ${formatDistance(post.radiusM!)}' : place, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                  ]),
                ),
              ),
            ]),
          )),
          pad: EdgeInsets.zero,
        ),
    ]);
  }
}

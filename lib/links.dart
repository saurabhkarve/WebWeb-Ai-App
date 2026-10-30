import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'auth_provider.dart';
import 'i18n.dart';
import 'icons.dart';
import 'theme.dart';

/// Links in what members write (asks, updates, replies): found in the text, drawn as links, the first one shown as a
/// preview card, and opened only after the "You're leaving WEBWEB" check (web lib/links.ts, external-link.tsx).

/// http(s)://… or www.… up to the next space; trailing punctuation is trimmed by [linkTokens].
final _urlRe = RegExp(r'\b(?:https?://|www\.)[^\s<>"\x27`]+', caseSensitive: false);

/// The link a match points to: www.x.com becomes https://www.x.com; null for anything that isn't a web address.
String? hrefOf(String raw) {
  final s = raw.toLowerCase().startsWith('www.') ? 'https://$raw' : raw;
  final u = Uri.tryParse(s);
  if (u == null || (u.scheme != 'http' && u.scheme != 'https') || !u.host.contains('.')) return null;
  return u.toString();
}

/// Links in a text with where they sit: "see https://x.com." gives https://x.com (the full stop stays text).
List<(int, int, String)> linkTokens(String text) {
  final out = <(int, int, String)>[];
  for (final m in _urlRe.allMatches(text)) {
    var raw = m.group(0)!;
    // a sentence's punctuation, and a closing bracket that has no opening one in the link
    while (raw.isNotEmpty && RegExp(r'''[.,;:!?'")\]}>]$''').hasMatch(raw)) {
      if (raw.endsWith(')') && '('.allMatches(raw).length >= ')'.allMatches(raw).length) break;
      raw = raw.substring(0, raw.length - 1);
    }
    final href = hrefOf(raw);
    if (href != null) out.add((m.start, m.start + raw.length, href));
  }
  return out;
}

/// The first link in any of the texts (the one that gets a preview card).
String? firstLink(List<String?> texts) {
  for (final t in texts) {
    if (t == null) continue;
    final l = linkTokens(t);
    if (l.isNotEmpty) return l.first.$3;
  }
  return null;
}

/// The text of a Visit ask without its address: the link shows as a preview card (picture, title, the site) with a Visit
/// button, not as a long URL. A line left holding only a label ("Link:") goes with it.
String stripLinks(String text) {
  var out = text;
  for (final (s, e, _) in linkTokens(text).reversed) {
    out = out.substring(0, s) + out.substring(e);
  }
  return out
      .split('\n')
      .where((l) => !RegExp(r'^\s*(link|website|site|url)\s*[:\-]?\s*$', caseSensitive: false).hasMatch(l))
      .join('\n')
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .trim();
}

/// What to draw of an ask's title or details: a Visit ask has its link taken out (see [stripLinks]).
String askText(String? askType, String? text) => text ?? '';

/// "skyq.tech" from https://www.skyq.tech/about
String hostOf(String href) {
  final h = Uri.tryParse(href)?.host ?? '';
  return h.isEmpty ? href : h.replaceFirst(RegExp(r'^www\.'), '');
}

/// "You're leaving WEBWEB": the site and the full address first, so a look-alike link can be spotted; Open link opens
/// it in the browser, outside the app.
Future<void> openExternal(BuildContext context, String href) async {
  final p = Pal.of(context);
  final go = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: p.canvas,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: kGold.withValues(alpha: .2)),
            child: WIcon(WI.globe, size: 24, color: p.tagText),
          ),
          const SizedBox(height: 12),
          Text(t("You're leaving WEBWEB"), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(t('This link goes to another website. Open it only if you trust it.'), style: TextStyle(fontSize: 14, color: p.muted)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(hostOf(href), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(href, style: TextStyle(fontSize: 12, color: p.muted)),
            ]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: Text(t('Cancel'), style: TextStyle(fontWeight: FontWeight.w700, color: p.text)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx, true),
                child: Container(
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(12)),
                  child: Text(t('Open link'), style: const TextStyle(fontWeight: FontWeight.w700, color: kInk)),
                ),
              ),
            ),
          ]),
        ]),
      ),
    ),
  );
  if (go == true) await launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication).catchError((_) => false);
}

class _Preview {
  final String? title, description, image, siteName;
  const _Preview({this.title, this.description, this.image, this.siteName});
}

// one request per link per app run, shared by every card showing it
final _cache = <String, Future<_Preview?>>{};
Future<_Preview?> _load(Api api, String href) => _cache[href] ??= api.get('/links/preview', {'url': href}).then((d) {
      final p = (d as Map)['preview'];
      if (p is! Map || (p['title'] ?? '').toString().isEmpty) return null;
      return _Preview(title: p['title'] as String?, description: p['description'] as String?, image: p['image'] as String?, siteName: p['siteName'] as String?);
    }).catchError((_) => null);

/// The preview card of a link a member wrote, like social apps show: the page's picture, site, title and description
/// (Open Graph, read by the API). Nothing shows while it loads or when the page has no preview; a tap opens the
/// "You're leaving WEBWEB" check. [compact] (in replies): a small picture beside the text instead of above it.
class LinkPreviewCard extends StatefulWidget {
  final String href;
  final bool compact;

  /// A Visit ask: only the domain is named (never the address) and a Visit button shows, even with no preview data.
  final bool visit;

  /// Inside a card of the ask's deck: no border of its own, the picture takes the height left.
  final bool flat;
  final EdgeInsets margin;
  const LinkPreviewCard(this.href, {super.key, this.compact = false, this.visit = false, this.flat = false, this.margin = const EdgeInsets.only(top: 8)});
  @override
  State<LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends State<LinkPreviewCard> {
  _Preview? _p;
  bool _imgOk = true;

  @override
  void initState() {
    super.initState();
    _load(context.read<AuthProvider>().api, widget.href).then((x) {
      if (mounted) setState(() => _p = x);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null && !widget.visit) return const SizedBox.shrink();
    final pal = Pal.of(context);
    final site = widget.visit || (p?.siteName ?? '').isEmpty ? hostOf(widget.href) : p!.siteName!;
    final c = widget.compact;
    final picture = (p?.image ?? '').isNotEmpty && _imgOk
        ? Image.network(p!.image!, fit: BoxFit.cover, errorBuilder: (_, __, ___) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _imgOk) setState(() => _imgOk = false);
            });
            return const SizedBox.shrink();
          })
        : null;
    final text = Padding(
      padding: c ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8) : const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(site.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.2, color: pal.muted)),
        if ((p?.title ?? '').isNotEmpty) Text(p!.title!, maxLines: c ? 1 : 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: c ? 13 : 15, fontWeight: FontWeight.w700, height: 1.3)),
        if ((p?.description ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(p!.description!, maxLines: c ? 1 : 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: c ? 12 : 13, color: pal.muted, height: 1.35)),
          ),
      ]),
    );
    final words = widget.visit
        ? Row(children: [
            Expanded(child: text),
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(18)),
              child: Text('${t('Visit')} →', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
            ),
          ])
        : text;
    return Padding(
      padding: widget.margin,
      child: Material(
        color: widget.flat ? Colors.transparent : pal.canvas,
        clipBehavior: Clip.antiAlias,
        shape: widget.flat ? const RoundedRectangleBorder() : RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: pal.border)),
        child: InkWell(
          onTap: () => openExternal(context, widget.href),
          child: c
              ? IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (picture != null) SizedBox(width: 88, child: ColoredBox(color: pal.chip, child: picture)),
                    Expanded(child: words),
                  ]),
                )
              : widget.flat
                  ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(child: picture != null ? ColoredBox(color: pal.chip, child: picture) : const SizedBox.shrink()),
                      words,
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (picture != null) AspectRatio(aspectRatio: 1.91, child: ColoredBox(color: pal.chip, child: picture)),
                      words,
                    ]),
        ),
      ),
    );
  }
}

/// Text with only its links made live (a chat message): each opens the "You're leaving WEBWEB" check, then the browser.
class LinkedText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  const LinkedText(this.text, {super.key, this.style});
  @override
  State<LinkedText> createState() => _LinkedTextState();
}

class _LinkedTextState extends State<LinkedText> {
  final _taps = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _taps) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final links = linkTokens(text);
    if (links.isEmpty) return Text(text, style: widget.style);
    for (final r in _taps) {
      r.dispose();
    }
    _taps.clear();
    final spans = <InlineSpan>[];
    var last = 0;
    for (final (s, e, href) in links) {
      if (s > last) spans.add(TextSpan(text: text.substring(last, s)));
      final tap = TapGestureRecognizer()..onTap = () => openExternal(context, href);
      _taps.add(tap);
      spans.add(TextSpan(text: text.substring(s, e), recognizer: tap, style: const TextStyle(fontWeight: FontWeight.w700, decoration: TextDecoration.underline)));
      last = e;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}

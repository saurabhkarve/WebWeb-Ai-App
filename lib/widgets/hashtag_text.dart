import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../links.dart';
import '../screens/find.dart';
import '../screens/profile.dart';
import '../theme.dart';

/// A #hashtag: letters, digits, marks (Devanagari and Gujarati vowel signs) and _, 2 to 40 long, not glued to a word
/// or a link before it (so "a#b" and "/page#top" stay text). Same rule as the web's hashtag-text.tsx.
final _tag = RegExp(r'(^|[^\p{L}\p{N}\p{M}_&/#])#([\p{L}\p{M}\p{N}_]{2,40})', unicode: true);

/// An @mention: a member handle (letters and digits, 3 to 30), not glued to a word before it (so an email stays text)
/// and not running on into more word characters. Same rule as the web.
final _mention = RegExp(r'(^|[^\p{L}\p{N}\p{M}_&/@.])@([A-Za-z0-9]{3,30})(?![\p{L}\p{N}\p{M}_])', unicode: true);

/// Text with its #hashtags drawn as links to Find, showing the asks that carry them, its @mentions as links to the
/// member's page (in the brand's ink-gold, so a person reads apart from a topic), and its web links as links that open
/// after the "You're leaving WEBWEB" check (links.dart).
class HashtagText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  /// SelectableText (the ask page and the asker's log) instead of Text
  final bool selectable;
  const HashtagText(this.text, {super.key, this.style, this.maxLines, this.overflow, this.selectable = false});

  @override
  State<HashtagText> createState() => _HashtagTextState();
}

class _HashtagTextState extends State<HashtagText> {
  final _taps = <TapGestureRecognizer>[];

  void _clear() {
    for (final r in _taps) {
      r.dispose();
    }
    _taps.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  void _open(String tag) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => FindScreen(standalone: true, initialQuery: '#$tag', initialScope: 'asks')),
      );

  void _profile(String handle) => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: handle)));

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    // (start, end, kind, value) for every link, #tag and @mention, in order; a link comes first where they overlap
    final matches = <(int, int, _Kind, String)>[
      for (final (start, end, href) in linkTokens(text)) (start, end, _Kind.url, href),
      for (final m in _tag.allMatches(text)) (m.start + m.group(1)!.length, m.end, _Kind.tag, m.group(2)!),
      for (final m in _mention.allMatches(text)) (m.start + m.group(1)!.length, m.end, _Kind.mention, m.group(2)!.toLowerCase()),
    ]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$3.index.compareTo(b.$3.index));
    if (matches.isEmpty) {
      return widget.selectable
          ? SelectableText(text, style: widget.style, maxLines: widget.maxLines)
          : Text(text, style: widget.style, maxLines: widget.maxLines, overflow: widget.overflow);
    }
    _clear();
    final p = Pal.of(context);
    final link = TextStyle(fontWeight: FontWeight.w700, color: p.link);
    final person = TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFFFD84A) : const Color(0xFF7A5A00));
    final spans = <InlineSpan>[];
    var last = 0;
    final web = link.copyWith(fontWeight: FontWeight.w600, decoration: TextDecoration.underline, decorationColor: p.link.withValues(alpha: .5));
    for (final (start, end, kind, value) in matches) {
      if (start < last) continue;
      if (start > last) spans.add(TextSpan(text: text.substring(last, start)));
      final tap = TapGestureRecognizer()
        ..onTap = () => switch (kind) {
              _Kind.url => openExternal(context, value),
              _Kind.mention => _profile(value),
              _Kind.tag => _open(value),
            };
      _taps.add(tap);
      spans.add(TextSpan(text: text.substring(start, end), style: switch (kind) { _Kind.url => web, _Kind.mention => person, _Kind.tag => link }, recognizer: tap));
      last = end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    final span = TextSpan(style: widget.style, children: spans);
    return widget.selectable
        ? SelectableText.rich(span, maxLines: widget.maxLines)
        : Text.rich(span, maxLines: widget.maxLines, overflow: widget.overflow);
  }
}

enum _Kind { url, tag, mention }

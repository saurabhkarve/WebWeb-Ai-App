import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../screens/find.dart';
import '../screens/profile.dart';
import '../theme.dart';

/// A #hashtag: letters, digits, marks (Devanagari and Gujarati vowel signs) and _, 2 to 40 long, not glued to a word
/// or a link before it (so "a#b" and "/page#top" stay text). Same rule as the web's hashtag-text.tsx.
final _tag = RegExp(r'(^|[^\p{L}\p{N}\p{M}_&/#])#([\p{L}\p{M}\p{N}_]{2,40})', unicode: true);

/// An @mention: a member handle (letters and digits, 3 to 30), not glued to a word before it (so an email stays text)
/// and not running on into more word characters. Same rule as the web.
final _mention = RegExp(r'(^|[^\p{L}\p{N}\p{M}_&/@.])@([A-Za-z0-9]{3,30})(?![\p{L}\p{N}\p{M}_])', unicode: true);

/// Text with its #hashtags drawn as links to Find, showing the asks that carry them, and its @mentions as links to the
/// member's page (in the brand's ink-gold, so a person reads apart from a topic).
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
    // (start, end, isMention, value) for every #tag and @mention, in order
    final matches = <(int, int, bool, String)>[
      for (final m in _tag.allMatches(text)) (m.start + m.group(1)!.length, m.end, false, m.group(2)!),
      for (final m in _mention.allMatches(text)) (m.start + m.group(1)!.length, m.end, true, m.group(2)!.toLowerCase()),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
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
    for (final (start, end, mention, value) in matches) {
      if (start < last) continue;
      if (start > last) spans.add(TextSpan(text: text.substring(last, start)));
      final tap = TapGestureRecognizer()..onTap = () => mention ? _profile(value) : _open(value);
      _taps.add(tap);
      spans.add(TextSpan(text: text.substring(start, end), style: mention ? person : link, recognizer: tap));
      last = end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    final span = TextSpan(style: widget.style, children: spans);
    return widget.selectable
        ? SelectableText.rich(span, maxLines: widget.maxLines)
        : Text.rich(span, maxLines: widget.maxLines, overflow: widget.overflow);
  }
}

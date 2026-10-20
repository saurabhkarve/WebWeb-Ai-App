import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../screens/find.dart';
import '../theme.dart';

/// A #hashtag: letters, digits, marks (Devanagari and Gujarati vowel signs) and _, 2 to 40 long, not glued to a word
/// or a link before it (so "a#b" and "/page#top" stay text). Same rule as the web's hashtag-text.tsx.
final _tag = RegExp(r'(^|[^\p{L}\p{N}\p{M}_&/#])#([\p{L}\p{M}\p{N}_]{2,40})', unicode: true);

/// Text with its #hashtags drawn as links to Find, showing the asks that carry them.
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

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final matches = _tag.allMatches(text).toList();
    if (matches.isEmpty) {
      return widget.selectable
          ? SelectableText(text, style: widget.style, maxLines: widget.maxLines)
          : Text(text, style: widget.style, maxLines: widget.maxLines, overflow: widget.overflow);
    }
    _clear();
    final link = TextStyle(fontWeight: FontWeight.w700, color: Pal.of(context).link);
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in matches) {
      final start = m.start + m.group(1)!.length;
      if (start > last) spans.add(TextSpan(text: text.substring(last, start)));
      final tag = m.group(2)!;
      final tap = TapGestureRecognizer()..onTap = () => _open(tag);
      _taps.add(tap);
      spans.add(TextSpan(text: '#$tag', style: link, recognizer: tap));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    final span = TextSpan(style: widget.style, children: spans);
    return widget.selectable
        ? SelectableText.rich(span, maxLines: widget.maxLines)
        : Text.rich(span, maxLines: widget.maxLines, overflow: widget.overflow);
  }
}

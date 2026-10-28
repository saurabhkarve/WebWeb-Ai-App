import 'dart:math';
import 'package:flutter/material.dart';
import 'models.dart';

/// The colours an ask's card can take (web card-colors.ts): the member picks one, a random one is chosen for them.
const kCardColors = <String, Color>{
  'gold': Color(0xFFFFC700),
  'emerald': Color(0xFF10B981),
  'sky': Color(0xFF0EA5E9),
  'violet': Color(0xFF8B5CF6),
  'rose': Color(0xFFF43F5E),
  'orange': Color(0xFFF97316),
  'teal': Color(0xFF14B8A6),
  'slate': Color(0xFF64748B),
};

String randomCardColor() => kCardColors.keys.elementAt(Random().nextInt(kCardColors.length));

/// The ask's colour; older asks have none, so theirs is a steady pick from the id (the same as on the web).
String cardColorOf(Post post) {
  final c = post.cardColor;
  if (c != null && kCardColors.containsKey(c)) return c;
  var h = 0;
  for (final u in post.id.codeUnits) {
    h = (h * 31 + u) & 0xFFFFFFFF;
  }
  return kCardColors.keys.elementAt(h % kCardColors.length);
}

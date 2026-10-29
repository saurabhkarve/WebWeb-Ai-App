import 'package:flutter_test/flutter_test.dart';
import 'package:webweb_app/widgets.dart';

void main() {
  test('one emoji is big, text and several are not', () {
    for (final s in ['👍', '👍🏽', '🇮🇳', '👨‍👩‍👧', '❤️', '1️⃣', '😀 ']) {
      expect(isSingleEmoji(s), true, reason: s);
    }
    for (final s in ['hi', '👍👍', 'a👍', '', '12', '🇮']) {
      expect(isSingleEmoji(s), false, reason: s);
    }
  });
}

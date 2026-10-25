import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webweb_app/widgets.dart';

/// Five controls of the given widths in a row [width] wide; returns each control's laid-out width and whether the
/// row can scroll.
Future<(List<double>, bool)> layout(WidgetTester tester, double width, List<double> sizes) async {
  await tester.pumpWidget(MaterialApp(
    home: Center(
      child: SizedBox(
        width: width,
        child: FitRow(children: [for (var i = 0; i < sizes.length; i++) SizedBox(key: ValueKey(i), width: sizes[i], height: 40)]),
      ),
    ),
  ));
  final widths = [for (var i = 0; i < sizes.length; i++) tester.getSize(find.byKey(ValueKey(i)).first).width];
  final pos = tester.state<ScrollableState>(find.byType(Scrollable)).position;
  return (widths, pos.maxScrollExtent > 0);
}

void main() {
  testWidgets('equal widths across the row when the widest fits', (tester) async {
    final (w, scrolls) = await layout(tester, 400, [50, 60, 70, 50, 60]);
    expect(scrolls, isFalse);
    for (final x in w) {
      expect(x, closeTo((400 - 4 * 6) / 5, .01));
    }
  });

  testWidgets('own widths, room shared out, when equal widths would not fit (no scrolling)', (tester) async {
    // widest 120 x 5 + gaps = 624 > 400, but 50+60+120+50+60 + 24 = 364 fits
    final (w, scrolls) = await layout(tester, 400, [50, 60, 120, 50, 60]);
    expect(scrolls, isFalse);
    expect(w[2] - w[0], closeTo(70, .01));
    expect(w.reduce((a, b) => a + b) + 24, closeTo(400, .01));
  });

  testWidgets('scrolls only when even its own widths are too wide', (tester) async {
    final (_, scrolls) = await layout(tester, 300, [80, 80, 80, 80, 80]);
    expect(scrolls, isTrue);
  });
}

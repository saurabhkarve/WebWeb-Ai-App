import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webweb_app/theme.dart';
import 'package:webweb_app/widgets/tour.dart';

void main() {
  test('the tour has the idea cards first, then the tabs; business owners get one more card', () {
    final customer = phonebookTour(business: false);
    final owner = phonebookTour(business: true);
    expect(owner.length, customer.length + 1);
    expect(customer.take(3).every((s) => s.target == null && (s.visual ?? '').startsWith('pb-')), isTrue);
    expect(customer.skip(3).every((s) => s.target != null), isTrue);
    expect(owner.where((s) => s.visual == 'pb-business').length, 1);
  });

  for (final kind in ['pb-search', 'pb-facts', 'pb-connect', 'pb-business']) {
    for (final w in [320.0, 390.0]) {
      testWidgets('$kind fits $w px and keeps looping', (tester) async {
        tester.view.physicalSize = Size(w, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: PbTourVisual(kind)))));
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 1900));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}

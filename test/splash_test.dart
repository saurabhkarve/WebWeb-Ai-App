import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webweb_app/theme.dart';
import 'package:webweb_app/widgets.dart' show LogoInline;
import 'package:webweb_app/widgets/splash_screen.dart';

void main() {
  // small phone, tall phone, tablet, landscape: the logo group and "from SKYQ" always fit, apart, with no overflow
  for (final (w, h) in [(320.0, 568.0), (390.0, 844.0), (430.0, 932.0), (820.0, 1180.0), (844.0, 390.0)]) {
    testWidgets('splash fits ${w.toInt()}x${h.toInt()}', (tester) async {
      tester.view.physicalSize = Size(w, h);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: const SplashScreen()));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      final title = tester.getRect(find.byType(LogoInline));
      final from = tester.getRect(find.text('SkyQ'));
      expect(title.bottom, lessThan(from.top));
      expect(from.bottom, lessThanOrEqualTo(h));
    });
  }
}

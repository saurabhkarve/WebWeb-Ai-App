import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:webweb_app/i18n.dart';
import 'package:webweb_app/icons.dart';
import 'package:webweb_app/permissions.dart';
import 'package:webweb_app/theme.dart';

void main() {
  // the three-step picture on the contacts screens must fit the narrowest phones and the largest text
  for (final w in [320.0, 390.0]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('ShareFlow fits $w px at text ${scale}x', (tester) async {
        tester.view.physicalSize = Size(w, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(ChangeNotifierProvider(
          create: (_) => I18n(),
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
            home: const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(20),
                child: ShareFlow(steps: [(WI.search, 'Finds service words on your phone'), (WI.send, 'Shares name, number and word'), (WI.check, 'Our team reviews each one')]),
              ),
            ),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 900));
        expect(tester.takeException(), isNull);
      });
    }
  }
}

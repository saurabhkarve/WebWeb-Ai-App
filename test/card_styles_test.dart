import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:webweb_app/auth_provider.dart';
import 'package:webweb_app/card_colors.dart';
import 'package:webweb_app/i18n.dart';
import 'package:webweb_app/models.dart';
import 'package:webweb_app/theme.dart';
import 'package:webweb_app/widgets/ask_deck.dart';
import 'package:webweb_app/widgets/card_look_picker.dart';

void main() {
  for (final style in kCardStyles) {
    for (final preview in [true, false]) {
      testWidgets('headline card: $style preview=$preview', (tester) async {
        tester.view.physicalSize = const Size(390 * 3, 844 * 3);
        tester.view.devicePixelRatio = 3;
        final post = Post(
          id: 'p1', kind: 'requirement', authorUid: 'u', authorName: 'Girish', authorCompany: 'Agarwal Labs', authorHandle: 'agarwal',
          title: 'Mobile apps from Agarwal Labs', description: 'We offer mobile apps in Kharghar and nearby.', category: 'services', askType: 'sell',
          cardColor: 'rose', cardStyle: style, locationPref: 'Kharghar', budget: '₹25,000', urgency: '30_days', createdAt: DateTime.now(),
        );
        await tester.pumpWidget(MultiProvider(
          providers: [ChangeNotifierProvider(create: (_) => AuthProvider()), ChangeNotifierProvider(create: (_) => I18n())],
          child: MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: ListView(padding: const EdgeInsets.all(16), children: [AskDeck(post: post, preview: preview, typeAbove: true, onReply: () {})]))),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('picker renders and reports taps', (tester) async {
    var got = '';
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: CardLookPicker(color: 'sky', style: 'banner', onColor: (_) {}, onStyle: (s) => got = s))));
    await tester.tap(find.text('Poster'));
    expect(got, 'poster');
    expect(tester.takeException(), isNull);
  });
}

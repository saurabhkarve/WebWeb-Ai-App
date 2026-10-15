import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Design tokens copied from the WebWeb Ai web app's CSS (biznet.webweb.ai), HSL values as in the site.
Color _hsl(double h, double s, double l) => HSLColor.fromAHSL(1, h, s / 100, l / 100).toColor();

const kGold = Color(0xFFFFC700); // --gold 47 100% 50% / the logo glow
final kGoldDeep = _hsl(44, 100, 38); // --gold-deep
const kGoldGradient = LinearGradient(colors: [Color(0xFFFFCB05), Color(0xFFE6AB00)], begin: Alignment.topLeft, end: Alignment.bottomRight);
const kGreen = Color(0xFF2FAE6B);

/// Font bundled from the web app (next/font "Akash", weights 300 / 500 / 700).
const kFont = 'Akash';

class Pal {
  final Color canvas, card, text, muted, border, field, chip, tagBg;
  final bool dark;
  const Pal._(this.dark, this.canvas, this.card, this.text, this.muted, this.border, this.field, this.chip, this.tagBg);

  // dark:  --background 0 0% 11.8%, --card 0 0% 14.5%, --foreground 45 25% 94%, --muted 0 0% 16%, --muted-foreground 40 6% 68%, --border 0 0% 24%
  static final _dark = Pal._(true, _hsl(0, 0, 11.8), _hsl(0, 0, 14.5), _hsl(45, 25, 94), _hsl(40, 6, 68), _hsl(0, 0, 24), _hsl(0, 0, 16), _hsl(0, 0, 16), const Color(0xFF3A2F08));
  // light: --background 45 40% 98.5%, --card white, --foreground 0 0% 11.8%, --muted 45 45% 96.5%, --muted-foreground 40 6% 40%, --border 42 22% 87%
  static final _light = Pal._(false, _hsl(45, 40, 98.5), Colors.white, _hsl(0, 0, 11.8), _hsl(40, 6, 40), _hsl(42, 22, 87), _hsl(45, 45, 96.5), _hsl(43, 26, 93), const Color(0xFFFFF1BF));

  static Pal of(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? _dark : _light;
  Color get onGold => const Color(0xFF1E1E1E);
  /// Selected pill (web --primary): cream on dark, ink on light.
  Color get selected => text;
  Color get onSelected => canvas;
}

ThemeData buildTheme(Brightness b) {
  final p = b == Brightness.dark ? Pal._dark : Pal._light;
  final base = ThemeData(brightness: b, useMaterial3: true, fontFamily: kFont);
  final text = base.textTheme.apply(fontFamily: kFont, bodyColor: p.text, displayColor: p.text);
  return base.copyWith(
    scaffoldBackgroundColor: p.canvas,
    canvasColor: p.card,
    textTheme: text,
    primaryTextTheme: text,
    colorScheme: ColorScheme.fromSeed(seedColor: kGold, brightness: b, primary: kGold, onPrimary: const Color(0xFF1E1E1E), surface: p.card),
    dividerColor: p.border,
    appBarTheme: AppBarTheme(backgroundColor: p.canvas, surfaceTintColor: Colors.transparent, elevation: 0, foregroundColor: p.text),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.card, surfaceTintColor: Colors.transparent),
    dialogTheme: DialogThemeData(backgroundColor: p.card, surfaceTintColor: Colors.transparent),
  );
}

/// System / Light / Dark, persisted.
class ThemeController extends ChangeNotifier {
  ThemeMode mode = ThemeMode.system;

  Future<void> init() async {
    final v = (await SharedPreferences.getInstance()).getString('theme');
    mode = ThemeMode.values.firstWhere((m) => m.name == v, orElse: () => ThemeMode.system);
    notifyListeners();
  }

  Future<void> set(ThemeMode m) async {
    mode = m;
    notifyListeners();
    (await SharedPreferences.getInstance()).setString('theme', m.name);
  }
}

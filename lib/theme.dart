import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Design tokens copied from the web app (web/src/app/globals.css), same HSL values.
Color _hsl(double h, double s, double l) => HSLColor.fromAHSL(1, h, s / 100, l / 100).toColor();

const kGold = Color(0xFFFFC700); // --gold 47 100% 50%
final kGoldDeep = _hsl(44, 100, 38); // --gold-deep
/// .bg-gold-gradient: linear-gradient(135deg, #ffd84a 0%, #ffc700 48%, #e0ad00 100%)
const kGoldGradient = LinearGradient(
  colors: [Color(0xFFFFD84A), Color(0xFFFFC700), Color(0xFFE0AD00)],
  stops: [0, .48, 1],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
const kGreen = Color(0xFF2F9E6B); // emerald-600-ish, used for "Reposted" and the mobile-verified badge
const kInk = Color(0xFF1E1E1E); // the brand "black"

/// Font bundled from the web app (Akash 300 / 500 / 700 / 900). Body weight is 500, like the site.
const kFont = 'Akash';

/// Palette per theme. Names follow the web's CSS variables.
class Pal {
  final bool dark;
  /// --background (page)
  final Color canvas;
  /// --card
  final Color card;
  /// --foreground
  final Color text;
  /// --muted-foreground (secondary text)
  final Color muted;
  /// --border
  final Color border;
  /// --muted (chip / meta pill fill)
  final Color field;
  /// --secondary (warm cream fill: header bar, buttons, counters)
  final Color chip;
  /// --link (handles, links, categories)
  final Color link;
  /// --ink / --ink-foreground (selected pills: island tab, filter chips)
  final Color ink, onInk;
  /// --destructive
  final Color danger;
  /// gold/25 tag text: #7a5a00 light, #ffc700 dark
  final Color tagText;
  const Pal._(this.dark, this.canvas, this.card, this.text, this.muted, this.border, this.field, this.chip, this.link, this.ink, this.onInk, this.danger, this.tagText);

  static final _light = Pal._(false, _hsl(45, 40, 98.5), Colors.white, _hsl(0, 0, 11.8), _hsl(40, 6, 40), _hsl(42, 22, 87), _hsl(45, 45, 96.5), _hsl(44, 48, 94),
      _hsl(42, 100, 26), _hsl(44, 58, 87), _hsl(0, 0, 11.8), _hsl(354, 80, 55), const Color(0xFF7A5A00));
  static final _dark = Pal._(true, _hsl(0, 0, 11.8), _hsl(0, 0, 14.5), _hsl(45, 25, 94), _hsl(40, 6, 68), _hsl(0, 0, 24), _hsl(0, 0, 16), _hsl(0, 0, 18.5),
      _hsl(47, 100, 60), _hsl(45, 25, 94), _hsl(0, 0, 11.8), _hsl(354, 80, 64), kGold);

  static Pal of(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? _dark : _light;
  Color get onGold => kInk;
  /// gold/25 background of match / "Your ask" tags
  Color get tagBg => kGold.withValues(alpha: .25);
  /// Type badge on avatars: ink in light mode, soft gold in dark (web: bg-ink, dark:bg-[hsl(44 58% 87%)]).
  Color get typeBadge => dark ? _hsl(44, 58, 87) : ink;
  /// My chat messages (web --bubble): the soft gold pill colour in light mode, a deep warm gold in dark
  Color get bubble => dark ? _hsl(43, 38, 24) : ink;
  Color get onBubble => dark ? text : onInk;
  Color get selected => ink;
  Color get onSelected => onInk;
}

/// Emoji in color everywhere (reactions ❤️ 👍 🙏, ratings, chat). Without naming them, the web renderer
/// draws ❤ from a black-and-white symbols font.
const kEmojiFonts = ['Apple Color Emoji', 'Noto Color Emoji'];

ThemeData buildTheme(Brightness b) {
  final p = b == Brightness.dark ? Pal._dark : Pal._light;
  final base = ThemeData(brightness: b, useMaterial3: true, fontFamily: kFont, fontFamilyFallback: kEmojiFonts);
  // Akash has no kerning: the site tightens tracking by -0.022em and uses weight 500 for body text.
  TextStyle? tune(TextStyle? s, {FontWeight? w}) =>
      s?.copyWith(fontFamily: kFont, fontFamilyFallback: kEmojiFonts, color: p.text, fontWeight: w ?? s.fontWeight, letterSpacing: -0.022 * (s.fontSize ?? 14));
  final t = base.textTheme;
  final text = TextTheme(
    displayLarge: tune(t.displayLarge, w: FontWeight.w700),
    displayMedium: tune(t.displayMedium, w: FontWeight.w700),
    displaySmall: tune(t.displaySmall, w: FontWeight.w700),
    headlineLarge: tune(t.headlineLarge, w: FontWeight.w700),
    headlineMedium: tune(t.headlineMedium, w: FontWeight.w700),
    headlineSmall: tune(t.headlineSmall, w: FontWeight.w700),
    titleLarge: tune(t.titleLarge, w: FontWeight.w700),
    titleMedium: tune(t.titleMedium, w: FontWeight.w700),
    titleSmall: tune(t.titleSmall, w: FontWeight.w700),
    bodyLarge: tune(t.bodyLarge, w: FontWeight.w500),
    bodyMedium: tune(t.bodyMedium, w: FontWeight.w500),
    bodySmall: tune(t.bodySmall, w: FontWeight.w500)?.copyWith(color: p.muted),
    labelLarge: tune(t.labelLarge, w: FontWeight.w700),
    labelMedium: tune(t.labelMedium, w: FontWeight.w500),
    labelSmall: tune(t.labelSmall, w: FontWeight.w500),
  );
  return base.copyWith(
    scaffoldBackgroundColor: p.canvas,
    canvasColor: p.card,
    textTheme: text,
    primaryTextTheme: text,
    iconTheme: IconThemeData(color: p.text),
    colorScheme: ColorScheme.fromSeed(seedColor: kGold, brightness: b, primary: kGold, onPrimary: kInk, surface: p.canvas, onSurface: p.text, error: p.danger),
    dividerColor: p.border,
    dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: p.canvas,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: p.text,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: kFont, fontSize: 18, fontWeight: FontWeight.w700, color: p.text, letterSpacing: -0.7),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.ink,
      contentTextStyle: TextStyle(fontFamily: kFont, color: p.onInk, fontWeight: FontWeight.w700, fontSize: 13),
      shape: const StadiumBorder(),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      showDragHandle: true,
      dragHandleColor: p.border,
    ),
    dialogTheme: DialogThemeData(backgroundColor: p.card, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    popupMenuTheme: PopupMenuThemeData(color: p.card, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: p.border))),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: kGold),
    textSelectionTheme: TextSelectionThemeData(cursorColor: p.text, selectionColor: kGold.withValues(alpha: .35), selectionHandleColor: kGold),
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

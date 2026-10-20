import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

/// Same i18n as the web (web/src/lib/i18n): English text is the key, so a missing translation shows
/// English, never a blank. The dictionaries in assets/i18n are exported from the web's hi.ts / mr.ts / gu.ts / kok.ts.
class Lang {
  final String code, name, native;
  const Lang(this.code, this.name, this.native);
}

const kLangs = [
  Lang('en', 'English', 'English'),
  Lang('hi', 'Hindi', 'हिन्दी'),
  Lang('mr', 'Marathi', 'मराठी'),
  Lang('gu', 'Gujarati', 'ગુજરાતી'),
  Lang('kok', 'Konkani', 'कोंकणी'),
];

Map<String, String> _dict = const {};
String _lang = 'en';
String get currentLang => _lang;

/// Translate an English string; `{name}` placeholders are filled from [vars].
String t(String en, [Map<String, Object>? vars]) {
  var out = _dict[en] ?? en;
  if (vars != null) {
    vars.forEach((k, v) => out = out.replaceAll('{$k}', '$v'));
  }
  return out;
}

class I18n extends ChangeNotifier {
  String get lang => _lang;

  Future<void> init() async {
    final saved = (await SharedPreferences.getInstance()).getString('lang');
    if (saved != null && saved != 'en') await _load(saved);
  }

  Future<void> set(String code) async {
    await _load(code);
    (await SharedPreferences.getInstance()).setString('lang', code);
  }

  Future<void> _load(String code) async {
    if (code == 'en') {
      _dict = const {};
    } else {
      try {
        _dict = Map<String, String>.from(jsonDecode(await rootBundle.loadString('assets/i18n/$code.json')) as Map);
      } catch (_) {
        return;
      }
    }
    _lang = code;
    notifyListeners();
  }
}

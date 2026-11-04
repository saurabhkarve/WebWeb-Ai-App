import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'i18n.dart';
import 'places.dart';

/// Approximate distance from where the search is to the place a contact is in, worked out on the phone from the places
/// list (their centres), with no map or distance service, so it works offline. A pair is worked out once and
/// remembered on the phone. A straight line between town centres: about, never exact.
class ApproxDistance {
  static const _kCache = 'distance_cache';
  static const _kHere = 'distance_here';
  static final Map<String, double> _mem = {};
  static bool _loaded = false;

  /// where the phone was last seen (kept, so a search offline is still measured from there)
  static ({double lat, double lng})? lastHere;

  static Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_kCache);
      if (raw != null) {
        (jsonDecode(raw) as Map).forEach((k, v) => _mem['$k'] = (v as num).toDouble());
      }
      final h = sp.getStringList(_kHere);
      if (h != null && h.length == 2) lastHere = (lat: double.parse(h[0]), lng: double.parse(h[1]));
    } catch (_) {}
  }

  static Future<void> rememberHere(double lat, double lng) async {
    lastHere = (lat: lat, lng: lng);
    try {
      (await SharedPreferences.getInstance()).setStringList(_kHere, ['$lat', '$lng']);
    } catch (_) {}
  }

  /// "Belapur, Navi Mumbai" or "Vashi": the place in the list that the text names (the whole text, then each part).
  static ({double lat, double lng})? _coords(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    for (final part in [name, ...name.split(RegExp(r'[,/·|-]'))]) {
      final p = findPlace(part);
      if (p?.lat != null && p?.lng != null) return (lat: p!.lat!, lng: p.lng!);
    }
    return null;
  }

  /// Where to measure from: the point picked, else the town chosen beside the box, else where the phone last was.
  static ({double lat, double lng})? base({({double lat, double lng})? at, String place = '', ({double lat, double lng})? here}) {
    if (at != null) return at;
    if (place.isNotEmpty) return _coords(place);
    return here ?? lastHere;
  }

  static double? km(({double lat, double lng})? from, String? where) {
    if (from == null || where == null || where.trim().isEmpty) return null;
    final key = '${from.lat.toStringAsFixed(2)},${from.lng.toStringAsFixed(2)}|${where.trim().toLowerCase()}';
    final hit = _mem[key];
    if (hit != null) return hit;
    final to = _coords(where);
    if (to == null) return null;
    final d = distanceKm(from.lat, from.lng, to.lat, to.lng);
    _mem[key] = d;
    _save();
    return d;
  }

  static Future<void> _save() async {
    try {
      final entries = _mem.entries.toList();
      final keep = entries.length > 600 ? entries.sublist(entries.length - 600) : entries;
      (await SharedPreferences.getInstance()).setString(_kCache, jsonEncode({for (final e in keep) e.key: e.value}));
    } catch (_) {}
  }

  /// "~3.5 km"
  static String label(double? km) {
    if (km == null) return '';
    final n = km < 1 ? '1' : (km < 10 ? km.toStringAsFixed(1) : '${km.round()}');
    return t('{n} km', {'n': '~$n'});
  }
}

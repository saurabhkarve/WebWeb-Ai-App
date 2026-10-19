import 'dart:math' as math;

import 'api.dart';
import 'places_data.dart';

/// Cities for location fields (web lib/places.ts): India's tier 1-3 cities with their centre and reach
/// (places_data.dart, generated from scripts/places-data.mjs), the Navi Mumbai areas WEBWEB started with, and
/// cities members added themselves (fetched once from the API).
class Place {
  final String name, state, stateName;

  /// 1-3 city tiers, 0 an area inside a city, -1 a city a member added
  final int tier;
  final double? lat, lng;
  final double radiusKm;
  const Place(this.name, this.state, this.stateName, this.tier, this.lat, this.lng, this.radiusKm);

  /// "Navi Mumbai, Maharashtra" for an area, the state for a city.
  String get subtitle => tier == 0 ? 'Navi Mumbai, $stateName' : stateName;
}

final List<Place> kPlaces = [
  for (final r in kPlaceRows)
    Place(r[0] as String, r[1] as String, kStateNames[r[1]] ?? r[1] as String, r[2] as int, (r[3] as num).toDouble(), (r[4] as num).toDouble(), (r[5] as num).toDouble()),
];

final Map<String, Place> _byKey = () {
  final m = {for (final p in kPlaces) p.name.toLowerCase(): p};
  kPlaceAliases.forEach((alias, name) {
    final p = m[name.toLowerCase()];
    if (p != null) m[alias.toLowerCase()] = p;
  });
  return m;
}();

List<Place> _custom = [];
Future<List<Place>>? _customLoad;

/// Cities members added that are not in the list (once per app run).
Future<List<Place>> loadCustomPlaces(Api api) => _customLoad ??= api.get('/places/custom').then((d) {
      return _custom = [
        for (final r in (d as List))
          if (!_byKey.containsKey('${r['name']}'.toLowerCase()))
            Place('${r['name']}', '', '', -1, (r['lat'] as num?)?.toDouble(), (r['lng'] as num?)?.toDouble(), 6),
      ];
    }).catchError((Object _) {
      _customLoad = null;
      return <Place>[];
    });

Place? findPlace(String? name) {
  if (name == null || name.trim().isEmpty) return null;
  final k = name.trim().toLowerCase();
  return _byKey[k] ?? _custom.where((p) => p.name.toLowerCase() == k).firstOrNull;
}

double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  double r(double d) => d * math.pi / 180;
  final h = math.pow(math.sin(r(lat2 - lat1) / 2), 2) + math.cos(r(lat1)) * math.cos(r(lat2)) * math.pow(math.sin(r(lng2 - lng1) / 2), 2);
  return 2 * 6371 * math.asin(math.sqrt(h));
}

/// Cities with a centre, nearest first, with their distance (up to [maxKm]).
List<({Place place, double km})> nearbyPlaces(double lat, double lng, {int limit = 8, double maxKm = 200}) {
  final list = [
    for (final p in [...kPlaces, ..._custom])
      if (p.lat != null && p.lng != null) (place: p, km: distanceKm(lat, lng, p.lat!, p.lng!)),
  ]..removeWhere((x) => x.km > maxKm);
  list.sort((a, b) => a.km.compareTo(b.km));
  return list.take(limit).toList();
}

/// The city a point is in: the smallest place whose reach covers it (an area before its city), else the
/// nearest city within 25 km; null when none is (the member names their town themselves).
Place? placeAt(double lat, double lng) {
  final near = nearbyPlaces(lat, lng, limit: 40, maxKm: 60);
  final inside = near.where((x) => x.km <= x.place.radiusKm).toList()..sort((a, b) => a.place.radiusKm.compareTo(b.place.radiusKm));
  if (inside.isNotEmpty) return inside.first.place;
  return near.isNotEmpty && near.first.km <= 25 ? near.first.place : null;
}

/// By name: starts with the text first, then a word starting with it, then containing it; bigger cities first.
List<Place> searchPlaces(String q, {int limit = 30}) {
  final k = q.trim().toLowerCase();
  if (k.isEmpty) return [];
  final first = k.split(RegExp(r'[\s,]+')).first;
  int score(Place p) {
    final n = p.name.toLowerCase();
    final words = n.split(RegExp(r'[\s-]+'));
    if (n == k) return 0;
    if (n.startsWith(k)) return 1;
    if (words.any((w) => w.startsWith(k))) return 2;
    if (n.contains(k)) return 3;
    if (p.stateName.toLowerCase().startsWith(k)) return 4;
    if (first.length >= 3 && first != k && words.any((w) => w.startsWith(first))) return 5;
    return 9;
  }

  int tierRank(int t) => t <= 0 ? 4 + (t == -1 ? 1 : 0) : t;
  final scored = [
    for (final p in [...kPlaces, ..._custom]) (p: p, s: score(p)),
  ]..removeWhere((x) => x.s >= 9);
  scored.sort((a, b) {
    final c = a.s.compareTo(b.s);
    if (c != 0) return c;
    final t = tierRank(a.p.tier).compareTo(tierRank(b.p.tier));
    return t != 0 ? t : a.p.name.compareTo(b.p.name);
  });
  final hits = [for (final x in scored) x.p];
  // an earlier name (Bangalore, Gurgaon) finds today's city
  kPlaceAliases.forEach((alias, name) {
    if (alias.toLowerCase().startsWith(k)) {
      final p = _byKey[name.toLowerCase()];
      if (p != null && !hits.contains(p)) hits.insert(0, p);
    }
  });
  return hits.take(limit).toList();
}

/// Tidies a typed town the way the API stores it (single spaces, capital first letters).
String tidyPlaceName(String raw) {
  var s = raw.replaceAll(RegExp(r"[^\p{L}\p{N} .,'()&/-]", unicode: true), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.length > 60) s = s.substring(0, 60);
  return s.replaceAllMapped(RegExp(r'\b(\p{Ll})(\p{L}*)', unicode: true), (m) => '${m[1]!.toUpperCase()}${m[2]}');
}

final kMetros = kPlaces.where((p) => p.tier == 1 && p.radiusKm >= 22).toList();

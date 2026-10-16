import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

/// Same node centres as web/src/lib/constants.ts (NODE_COORDS).
const kNodeCoords = <String, List<double>>{
  'Vashi': [19.0771, 72.9986],
  'Rabale': [19.1417, 73.001],
  'Turbhe': [19.0723, 73.0156],
  'Mahape': [19.113, 73.027],
  'Pawane': [19.1170, 73.0100],
  'Belapur': [19.023, 73.039],
  'Kharghar': [19.047, 73.069],
  'Panvel': [18.9894, 73.1175],
  'Kalamboli': [19.03, 73.1],
};

/// Nearest node within ~20 km, else "Other" (same rule as the web's nearestLocation).
String nearestLocation(double lat, double lng) {
  var best = 'Other';
  var bestKm = 20.0;
  kNodeCoords.forEach((name, c) {
    final dy = (c[0] - lat) * 111;
    final dx = (c[1] - lng) * 111 * math.cos(lat * math.pi / 180);
    final km = math.sqrt(dx * dx + dy * dy);
    if (km < bestKm) {
      bestKm = km;
      best = name;
    }
  });
  return best;
}

class Here {
  final double lat, lng;
  final String node;
  const Here(this.lat, this.lng, this.node);
}

/// Asks for location permission (only when needed) and returns the current position.
/// Throws a user-facing message when location is off or denied.
Future<Here> currentLocation() async {
  if (!await Geolocator.isLocationServiceEnabled()) throw 'Turn on location in your phone settings.';
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
  if (perm == LocationPermission.deniedForever) {
    await Geolocator.openAppSettings();
    throw 'Allow location for WebWeb Ai in Settings.';
  }
  if (perm == LocationPermission.denied) throw 'Location permission was not given.';
  final p = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 10)),
  ).catchError((_) async => await Geolocator.getLastKnownPosition() ?? (throw 'Could not get your location.'));
  return Here(p.latitude, p.longitude, nearestLocation(p.latitude, p.longitude));
}

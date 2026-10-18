import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import 'auth_provider.dart';
import 'i18n.dart';
import 'permissions.dart';

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

/// The person closed the permission pop-up without allowing it (the pop-up already said why);
/// callers simply stop, without another error message.
class PermissionNotGiven implements Exception {
  const PermissionNotGiven();
  @override
  String toString() => '';
}

/// The current position, for a feature the person is using right now (never in the background).
/// Checks the permission every time and explains it in a pop-up when it is off ([Permissions.ensure]),
/// then saves the reading as the member's last known location (PUT /me/location, private).
/// Throws [PermissionNotGiven] when not allowed, or a user-facing message when no fix could be had.
Future<Here> currentLocation(BuildContext context, {required String reason, required String source}) async {
  final api = context.read<AuthProvider>().api;
  if (!await Permissions.ensure(context, Need.location, reason: reason)) throw const PermissionNotGiven();
  Position p;
  try {
    p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 12)),
    );
  } catch (_) {
    final last = await Geolocator.getLastKnownPosition();
    if (last == null) throw t('Could not get your location. Step outside or near a window and try again.');
    p = last;
  }
  if (api.token() != null) {
    api.put('/me/location', {'lat': p.latitude, 'lng': p.longitude, 'accuracy': p.accuracy, 'source': source}).catchError((_) => null);
  }
  return Here(p.latitude, p.longitude, nearestLocation(p.latitude, p.longitude));
}

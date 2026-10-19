import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import 'auth_provider.dart';
import 'i18n.dart';
import 'permissions.dart';
import 'places.dart';

/// Centres of every city and area (places.dart), by name.
final Map<String, List<double>> kNodeCoords = {
  for (final p in kPlaces)
    if (p.lat != null) p.name: [p.lat!, p.lng!],
};

/// The city a point is in (places.dart placeAt), or '' when no city in the list is near (same as the web).
String nearestLocation(double lat, double lng) => placeAt(lat, lng)?.name ?? '';

class Here {
  final double lat, lng;
  /// the city it is in, '' when none in the list is near
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

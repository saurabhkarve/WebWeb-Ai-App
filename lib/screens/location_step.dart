import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../i18n.dart';
import '../location.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/city_picker.dart';
import '../widgets/pin_picker.dart';

/// Every member has a location: WEBWEB connects people who are near each other, so the point decides who sees their
/// asks and who they find. It is asked once, after sign-up (and from members who joined without one), and there are
/// two ways to give it: the phone's current location, or a pin set by hand on a map. Location Services is never
/// required (App Store guideline 5.1.5): saying no to it, or having it off, simply opens the map.
class LocationStep extends StatefulWidget {
  const LocationStep({super.key});
  @override
  State<LocationStep> createState() => _LocationStepState();
}

class _LocationStepState extends State<LocationStep> {
  bool _busy = false;
  String? _note;

  bool get _phone => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// The phone's position. This screen is the explanation, so the phone's own prompt shows straight away; no, or
  /// location switched off, goes to the map instead (never a dead end).
  Future<void> _useCurrent() async {
    setState(() {
      _busy = true;
      _note = null;
    });
    try {
      if (_phone) {
        if (!await Geolocator.isLocationServiceEnabled()) return await _toMap(t('Location is off on your phone. Set your location on the map instead.'));
        var s = await Permission.locationWhenInUse.status;
        if (s.isDenied) s = await Permission.locationWhenInUse.request();
        if (!(s.isGranted || s.isLimited)) return await _toMap(t('No problem. Set your location on the map instead.'));
      }
      Position pos;
      try {
        pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
      } catch (_) {
        final last = await Geolocator.getLastKnownPosition();
        if (last == null) return await _toMap(t('Could not get your location. Set it on the map instead.'));
        pos = last;
      }
      if (!mounted) return;
      await _save(pos.latitude, pos.longitude, accuracy: pos.accuracy);
    } catch (_) {
      return await _toMap(t('Could not get your location. Set it on the map instead.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toMap([String? note]) async {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _note = note;
    });
    final pt = await showPinPicker(context);
    if (pt == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _save(pt.lat, pt.lng);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Saves the point (private) and the area it is in (shown on the page). A place not in our list is named by the member.
  Future<void> _save(double lat, double lng, {double? accuracy}) async {
    final auth = context.read<AuthProvider>();
    var area = nearestLocation(lat, lng);
    if (area.isEmpty) {
      final c = await showCitySheet(context, near: (lat: lat, lng: lng));
      if (c == null || c.name.trim().length < 2 || !mounted) {
        if (mounted) setState(() => _note = t('Choose the name of your city or area to finish.'));
        return;
      }
      area = c.name;
    }
    try {
      await auth.api.put('/me/location', {'lat': lat, 'lng': lng, if (accuracy != null) 'accuracy': accuracy, 'source': 'onboarding'});
      await auth.updateProfile({'location': area, 'locationLat': lat, 'locationLng': lng});
    } catch (e) {
      if (mounted) setState(() => _note = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(gradient: kGoldGradient, shape: BoxShape.circle),
                  child: const WIcon(WI.pin, size: 30, color: kInk, strokeWidth: 1.8),
                ),
                const SizedBox(height: 20),
                Text(t('Where are you?'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.2)),
                const SizedBox(height: 10),
                Text(
                  t('WEBWEB connects you with businesses and people near you. Your location decides who sees your asks and who you find nearby, so every member sets one.'),
                  style: const TextStyle(fontSize: 15, height: 1.45),
                ),
                const SizedBox(height: 14),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.only(top: 2), child: WIcon(WI.lock, size: 14, color: p.muted)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(t('Only your area is shown to others, never the exact point. You can change it any time from your page.'),
                        style: TextStyle(fontSize: 13, color: p.muted, height: 1.4)),
                  ),
                ]),
                const SizedBox(height: 28),
                GoldButton(label: t('Use my current location'), wi: WI.pin, loading: _busy, onPressed: _busy ? null : _useCurrent),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _busy ? null : () => _toMap(),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: const StadiumBorder(),
                    side: BorderSide(color: p.border),
                    foregroundColor: p.text,
                  ),
                  child: Text(t('Set it on the map'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                if (_note != null) ...[
                  const SizedBox(height: 14),
                  Text(_note!, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.muted)),
                ],
                const SizedBox(height: 24),
                TextButton(onPressed: _busy ? null : context.read<AuthProvider>().logout, child: Text(t('Log out'))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

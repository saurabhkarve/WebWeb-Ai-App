import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'config.dart';

/// This install as one of the member's devices (web lib/device.ts):
/// - a random id kept on the phone, sent with push tokens and the live connection, so a push skips the device
///   showing the app while the member's other devices still get it, and sign-out can forget this device;
/// - a short report of the permissions the app has here (Admin > Devices), sent on every open;
/// - sign-out that always reaches the API: when the phone is offline it is kept and sent on the next start.
class Device {
  static const _idKey = 'device_id', _pendingKey = 'signout_pending';
  static String? _id;
  static DateTime? _reportedAt;

  /// The id, once [load] ran (it runs first thing at start).
  static String? get id => _id;

  static Future<String> load() async {
    if (_id != null) return _id!;
    final prefs = await SharedPreferences.getInstance();
    var v = prefs.getString(_idKey);
    if (v == null) {
      final r = Random.secure();
      v = 'a${List.generate(24, (_) => r.nextInt(36).toRadixString(36)).join()}';
      await prefs.setString(_idKey, v);
    }
    return _id = v;
  }

  static String _status(PermissionStatus s) => switch (s) {
        PermissionStatus.granted || PermissionStatus.provisional => 'granted',
        PermissionStatus.limited => 'limited',
        PermissionStatus.permanentlyDenied || PermissionStatus.restricted => 'blocked',
        PermissionStatus.denied => 'denied',
      };

  static Future<String> _check(Future<String> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return 'unsupported';
    }
  }

  /// Tells the API which app version runs here and what it may use. At most every 30 minutes unless [force].
  static Future<void> report(Api api, {bool force = false}) async {
    if (kIsWeb || api.token() == null) return;
    if (!force && _reportedAt != null && DateTime.now().difference(_reportedAt!) < const Duration(minutes: 30)) return;
    _reportedAt = DateTime.now();
    try {
      final id = await load();
      final android = Platform.isAndroid;
      final perms = <String, String>{
        'notifications': await _check(() async => _status(await Permission.notification.status)),
        'location': await _check(() async => _status(await Permission.locationWhenInUse.status)),
        'locationService': await _check(() async => await Geolocator.isLocationServiceEnabled() ? 'on' : 'off'),
        'contacts': await _check(() async => _status(await Permission.contacts.status)),
        'camera': await _check(() async => _status(await Permission.camera.status)),
        'microphone': await _check(() async => _status(await Permission.microphone.status)),
        if (android) 'fullScreenCalls': await _check(() async => await FlutterCallkitIncoming.canUseFullScreenIntent() ? 'on' : 'off'),
        if (android) 'battery': await _check(() async => _status(await Permission.ignoreBatteryOptimizations.status)),
      };
      final info = await PackageInfo.fromPlatform();
      await api.post('/app/device', {
        'deviceId': id,
        'platform': android ? 'android' : 'ios',
        'appVersion': '${info.version}+${info.buildNumber}',
        'os': _clip('${android ? 'Android' : 'iOS'} ${Platform.operatingSystemVersion}', 120),
        'permissions': perms,
      });
    } catch (e) {
      _reportedAt = null;
      debugPrint('device report failed: $e');
    }
  }

  static String _clip(String s, int n) => s.length > n ? s.substring(0, n) : s;

  /// Signing out here: the API forgets this device's push tokens. Offline, it is kept and sent on the next start.
  static Future<void> signOut(Api api, List<String> tokens) async {
    final id = await load();
    _reportedAt = null;
    final body = {'deviceId': id, 'tokens': tokens, 'at': DateTime.now().millisecondsSinceEpoch};
    try {
      await api.post('/app/signout', body);
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final list = (prefs.getStringList(_pendingKey) ?? [])..add(jsonEncode(body));
      await prefs.setStringList(_pendingKey, list.length > 5 ? list.sublist(list.length - 5) : list);
    }
  }

  /// Sends sign-outs that could not reach the API before (no session needed: the device id and tokens are the proof).
  static Future<void> flushSignOuts() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_pendingKey) ?? const [];
    if (list.isEmpty) return;
    final left = <String>[];
    for (final body in list) {
      try {
        final r = await http
            .post(Uri.parse('$apiUrl/app/signout'), headers: {'Content-Type': 'application/json'}, body: body)
            .timeout(const Duration(seconds: 15));
        if (r.statusCode >= 500) left.add(body);
      } catch (_) {
        left.add(body);
      }
    }
    await prefs.setStringList(_pendingKey, left);
  }
}

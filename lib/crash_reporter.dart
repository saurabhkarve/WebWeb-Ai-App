import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'notifications.dart' show initFirebase;

/// Automatic crash and error reports, to two places:
/// - Firebase Crashlytics (phones): also native Android / iOS crashes, symbolicated, with crash-free stats.
/// - our own API (POST /crash; Admin > Crashes groups them), next to the website's errors.
/// Catches what Flutter catches: build / layout / paint errors (FlutterError.onError) and every uncaught
/// async error (PlatformDispatcher.onError). Reports are queued on the phone first, so a crash while
/// offline, or one that closes the app, is sent on the next start. Each distinct error is sent once per
/// run and at most 10 per run; nothing is sent from debug builds. No message text, contacts or other
/// personal content is collected: only the error, its stack and the app / OS version.
class CrashReporter {
  static const _key = 'crash_queue_v1';
  static Api? _api;
  static String _version = '';
  static final Set<String> _seen = {};
  static int _count = 0;
  static Timer? _flushTimer;
  static bool _flushing = false;

  static bool _crashlytics = false;
  static bool get _phone => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// Signed in: crashes in Crashlytics carry the member id (no name or number), so a report can be traced.
  static void setUser(String? uid) {
    if (_crashlytics) FirebaseCrashlytics.instance.setUserIdentifier(uid ?? '').catchError((_) {});
  }

  static void init(Api api) {
    _api = api;
    if (_phone) {
      initFirebase().then((_) async {
        await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);
        _crashlytics = true;
      }).catchError((_) {});
    }
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      if (details.silent) return;
      if (_crashlytics) FirebaseCrashlytics.instance.recordFlutterError(details).catchError((_) {});
      report(details.exception, details.stack, context: {
        if (details.library != null) 'library': details.library!,
        if (details.context != null) 'while': details.context.toString().replaceAll('\n', ' '),
      });
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      if (_crashlytics) FirebaseCrashlytics.instance.recordError(error, stack, fatal: true).catchError((_) {});
      report(error, stack, fatal: true);
      return true; // handled: logged and reported, the app keeps running where it can
    };
    PackageInfo.fromPlatform().then((i) => _version = '${i.version}+${i.buildNumber}', onError: (_) => '');
    // whatever an earlier run could not send (offline, or the app closed right after the crash)
    Future.delayed(const Duration(seconds: 8), flush);
  }

  static void report(Object error, StackTrace? stack, {bool fatal = false, Map<String, String> context = const {}}) {
    if (kDebugMode) return;
    try {
      final message = '${error.runtimeType}: $error'.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (_isNoise(message)) return;
      final trace = (stack ?? StackTrace.empty).toString();
      final firstFrame = trace.split('\n').firstWhere((l) => l.contains('package:'), orElse: () => '');
      if (!_seen.add('$message|$firstFrame') || _count >= 10) return;
      _count++;
      _enqueue({
        'message': message.length > 2000 ? message.substring(0, 2000) : message,
        if (trace.isNotEmpty) 'stack': trace.length > 12000 ? trace.substring(0, 12000) : trace,
        'fatal': fatal,
        'context': context.map((k, v) => MapEntry(k, v.length > 500 ? v.substring(0, 500) : v)),
        'at': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {
      // reporting must never cause another error
    }
  }

  /// Network blips and the like are not bugs: the app already shows "Waiting for network".
  static bool _isNoise(String m) => RegExp(
        r'SocketException|HandshakeException|ClientException|Connection (closed|reset|refused)|Failed host lookup|TimeoutException|WebSocketChannelException|ApiException',
      ).hasMatch(m);

  static Future<void> _enqueue(Map<String, dynamic> r) async {
    final prefs = await SharedPreferences.getInstance();
    final q = prefs.getStringList(_key) ?? [];
    q.add(jsonEncode(r));
    await prefs.setStringList(_key, q.length > 20 ? q.sublist(q.length - 20) : q);
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(seconds: 3), flush);
  }

  static Future<void> flush() async {
    final api = _api;
    if (api == null || _flushing) return;
    _flushing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final q = prefs.getStringList(_key) ?? [];
      if (q.isEmpty) return;
      final batch = q.take(10).toList();
      await api.post('/crash', {
        'source': 'app',
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        if (!kIsWeb) 'osVersion': Platform.operatingSystemVersion.length > 120 ? Platform.operatingSystemVersion.substring(0, 120) : Platform.operatingSystemVersion,
        if (_version.isNotEmpty) 'appVersion': _version,
        'reports': batch.map((e) => jsonDecode(e)).toList(),
      });
      final rest = (prefs.getStringList(_key) ?? []).skip(batch.length).toList();
      await prefs.setStringList(_key, rest);
      if (rest.isNotEmpty) _flushTimer = Timer(const Duration(seconds: 5), flush);
    } catch (e) {
      // offline or the API is down: kept for the next start; a report the API refuses (400) is dropped
      if (e is ApiException && e.status >= 400 && e.status < 500 && e.status != 429) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_key);
      }
    } finally {
      _flushing = false;
    }
  }
}

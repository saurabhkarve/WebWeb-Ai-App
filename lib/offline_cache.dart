import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The last good answer of the API for the screens people open most (chats, messages, feed, profiles),
/// kept on the phone so the app opens and reads like WhatsApp with no network: it shows what it had and
/// refreshes once the network is back. Files under the app's support folder; cleared on sign-out.
class OfflineCache {
  OfflineCache._();

  static Directory? _dir;
  static const _maxBytes = 512 * 1024; // per answer
  static const _maxFiles = 200;

  /// Answers that make no sense offline (searches, live checks, one-off tokens) are never kept.
  static final _skip = RegExp(r'^/(users/search|products/search|public/handle-check|app/ice|ai/status)|/receipts$|/reactions$');

  static bool cacheable(String path, Map<String, dynamic>? q) => !kIsWeb && !_skip.hasMatch(path) && !(q?.containsKey('after') ?? false);

  static String _key(String path, Map<String, dynamic>? q) {
    final keys = (q?.keys.where((k) => q[k] != null).toList() ?? [])..sort();
    return keys.isEmpty ? path : '$path?${keys.map((k) => '$k=${q![k]}').join('&')}';
  }

  static Future<File?> _file(String key) async {
    try {
      _dir ??= Directory('${(await getApplicationSupportDirectory()).path}/api-cache');
      if (!await _dir!.exists()) await _dir!.create(recursive: true);
      // a readable, collision-free file name for the key
      return File('${_dir!.path}/${base64Url.encode(utf8.encode(key)).replaceAll('=', '')}.json');
    } catch (_) {
      return null;
    }
  }

  static Future<void> put(String path, Map<String, dynamic>? q, String body) async {
    if (body.length > _maxBytes) return;
    final f = await _file(_key(path, q));
    if (f == null) return;
    try {
      await f.writeAsString(body, flush: false);
      _trim();
    } catch (_) {}
  }

  static Future<dynamic> get(String path, Map<String, dynamic>? q) async {
    final f = await _file(_key(path, q));
    if (f == null || !await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  static int _writes = 0;
  /// Keeps the newest answers only (checked every 25 writes).
  static Future<void> _trim() async {
    if (++_writes % 25 != 0 || _dir == null) return;
    try {
      final files = _dir!.listSync().whereType<File>().toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      for (final f in files.skip(_maxFiles)) {
        f.deleteSync();
      }
    } catch (_) {}
  }

  /// Sign-out: nothing of the old account stays on the phone.
  static Future<void> clear() async {
    try {
      _dir ??= Directory('${(await getApplicationSupportDirectory()).path}/api-cache');
      if (await _dir!.exists()) await _dir!.delete(recursive: true);
    } catch (_) {}
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api.dart';

/// Who is online (green badge) or was active in the last 2 hours (gold badge), for every avatar on screen
/// (web lib/presence.ts). Avatars register their member; one request a moment later asks for all of them,
/// and members still on screen are asked again every minute.
class PresenceStore extends ChangeNotifier {
  PresenceStore._();
  static final instance = PresenceStore._();

  final _known = <String, (String?, DateTime)>{};
  final _watched = <String, int>{};
  Timer? _soon, _ticker;
  Api? _api;
  static const _fresh = Duration(minutes: 1);

  /// 'online', 'recent' or null.
  String? of(String uid) => _known[uid]?.$1;

  void watch(String uid, Api api) {
    _api = api;
    _watched[uid] = (_watched[uid] ?? 0) + 1;
    _schedule();
  }

  void unwatch(String uid) {
    final n = (_watched[uid] ?? 1) - 1;
    n > 0 ? _watched[uid] = n : _watched.remove(uid);
  }

  void _schedule() {
    _soon ??= Timer(const Duration(milliseconds: 80), _fetch);
    _ticker ??= Timer.periodic(_fresh, (_) => _schedule());
  }

  Future<void> _fetch() async {
    _soon = null;
    final api = _api;
    if (api == null) return;
    final now = DateTime.now();
    final due = _watched.keys.where((u) => now.difference(_known[u]?.$2 ?? DateTime(2000)) > _fresh).toList();
    for (var i = 0; i < due.length; i += 100) {
      final part = due.sublist(i, i + 100 > due.length ? due.length : i + 100);
      try {
        final r = await api.get('/users/presence', {'ids': part.join(',')}) as Map;
        for (final u in part) {
          _known[u] = (r[u] as String?, DateTime.now());
        }
        notifyListeners();
      } catch (_) {
        // signed out or offline: badges stay neutral
      }
    }
  }
}

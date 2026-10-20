import 'dart:async';

import 'api.dart';

/// Post views (as on x.com, the web's lib/services/views.ts): a card counts as seen once it is built on screen, sent
/// in small batches. The server counts each member once per post and never the author.
class ViewTracker {
  static final _seen = <String>{};
  static final _queue = <String>[];
  static Timer? _timer;
  static Api? _api;

  static void record(Api api, String id) {
    if (!_seen.add(id)) return;
    _api = api;
    _queue.add(id);
    _timer ??= Timer(const Duration(seconds: 3), _flush);
  }

  static void _flush() {
    _timer = null;
    final api = _api;
    if (api == null || _queue.isEmpty) return;
    final ids = _queue.take(50).toList();
    _queue.removeRange(0, ids.length);
    api.post('/posts/views', {'ids': ids}).catchError((_) => null); // a lost view is not worth a retry
    if (_queue.isNotEmpty) _timer = Timer(const Duration(seconds: 1), _flush);
  }
}

/// A count the way x.com shows it: 999, 1.2K, 12K, 1.2M.
String compactCount(int n) {
  if (n < 1000) return '$n';
  String one(double v) => v.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
  if (n < 1000000) return n < 10000 ? '${one((n ~/ 100) / 10)}K' : '${n ~/ 1000}K';
  return '${one((n ~/ 100000) / 10)}M';
}

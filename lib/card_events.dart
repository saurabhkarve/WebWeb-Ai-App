import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api.dart';

/// How members read an ask's cards (which one they reached, swiped to the end, tapped): sent in small batches to
/// POST /posts/card-events, the same measure the website feeds (admin: Ask cards).
class CardEvents {
  static final _queue = <Map<String, Object>>[];
  static final _once = <String>{};
  static Timer? _timer;

  static String get _platform => defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  /// `view` and `complete` count once per card per ask in this run; `swipe` and `cta` each time.
  static void log(Api api, String postId, String event, int card, int cards) {
    if (event != 'swipe' && event != 'cta') {
      final key = '$postId:$event:${event == 'view' ? card : 0}';
      if (!_once.add(key)) return;
    }
    _queue.add({'postId': postId, 'event': event, 'card': card, 'cards': cards, 'platform': _platform});
    _timer ??= Timer(const Duration(seconds: 3), () => _flush(api));
  }

  static void _flush(Api api) {
    _timer = null;
    if (_queue.isEmpty) return;
    final events = _queue.take(60).toList();
    _queue.removeRange(0, events.length);
    api.post('/posts/card-events', {'events': events}).catchError((_) => null);
    if (_queue.isNotEmpty) _timer = Timer(const Duration(seconds: 1), () => _flush(api));
  }
}

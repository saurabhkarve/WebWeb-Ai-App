import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';
import 'config.dart';

/// One WebSocket to the API (`/app/ws`): live chat events, typing, presence and call signalling.
/// Chat messages themselves are sent over REST; this carries what happens around them.
/// Reconnects automatically while a token is set. Tells the server when the app goes to the background, so
/// messages and calls then come as push notifications instead of over a socket the phone may suspend.
class RealtimeService extends ChangeNotifier with WidgetsBindingObserver {
  RealtimeService() {
    WidgetsBinding.instance.addObserver(this);
  }

  bool _foreground = true;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) return; // shade pulled down, app switcher: still on screen
    final fg = state == AppLifecycleState.resumed;
    if (fg == _foreground) return;
    _foreground = fg;
    send({'type': 'app_state', 'fg': fg});
  }

  WebSocketChannel? _ch;
  String? _token;
  Timer? _retry;
  int _attempt = 0;
  bool connected = false;
  /// the server sends push notifications to this phone (set from its hello)
  bool serverPush = false;
  final Set<String> online = {}; // user ids
  final _events = StreamController<Json>.broadcast();

  Stream<Json> get events => _events.stream;
  bool isOnline(String uid) => online.contains(uid);

  void connect(String token) {
    if (_token == token && (_ch != null || _retry != null)) return;
    _token = token;
    _open();
  }

  void _open() {
    final token = _token;
    if (token == null) return;
    _retry?.cancel();
    _retry = null;
    try {
      final ch = WebSocketChannel.connect(Uri.parse('$wsUrl?token=$token'));
      _ch = ch;
      ch.ready.then((_) {
        if (_ch != ch) return;
        _attempt = 0;
        connected = true;
        if (!_foreground) send({'type': 'app_state', 'fg': false});
        notifyListeners();
      }).catchError((_) => _closed(ch));
      ch.stream.listen(_onData, onDone: () => _closed(ch), onError: (_) => _closed(ch));
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _onData(dynamic raw) {
    Json m;
    try {
      m = Map<String, dynamic>.from(jsonDecode(raw as String));
    } catch (_) {
      return;
    }
    switch (m['type']) {
      case 'hello':
        serverPush = m['push'] == true;
        online
          ..clear()
          ..addAll(List<String>.from(m['online'] ?? []));
        notifyListeners();
        break;
      case 'presence':
        m['online'] == true ? online.add('${m['uid']}') : online.remove('${m['uid']}');
        notifyListeners();
        break;
    }
    _events.add(m);
  }

  void _closed(WebSocketChannel ch) {
    if (_ch != ch) return;
    _ch = null;
    connected = false;
    online.clear();
    notifyListeners();
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_token == null || _retry != null) return;
    _attempt++;
    _retry = Timer(Duration(seconds: (_attempt * 2).clamp(2, 15)), () {
      _retry = null;
      _open();
    });
  }

  bool send(Json m) {
    if (!connected || _ch == null) return false;
    _ch!.sink.add(jsonEncode(m));
    return true;
  }

  void disconnect() {
    _token = null;
    _retry?.cancel();
    _retry = null;
    final ch = _ch;
    _ch = null;
    connected = false;
    online.clear();
    ch?.sink.close();
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    disconnect();
    _events.close();
    super.dispose();
  }
}

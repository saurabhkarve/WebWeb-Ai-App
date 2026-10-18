import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';
import 'config.dart';

/// One WebSocket to the API (`/app/ws`): live chat events, typing, presence and call signalling.
/// Chat messages themselves are sent over REST; this carries what happens around them.
/// Reconnects automatically while a token is set. Tells the server when the app goes to the background, so
/// messages and calls then come as push notifications instead of over a socket the phone may suspend.
///
/// Like WhatsApp it notices a dead link quickly: a heartbeat every 20 s (a socket that stays silent for 45 s,
/// e.g. after switching from Wi-Fi to mobile data, is dropped and reopened), and it reconnects at once when
/// the network comes back or the app returns to the front instead of waiting out the back-off.
class RealtimeService extends ChangeNotifier with WidgetsBindingObserver {
  RealtimeService() {
    WidgetsBinding.instance.addObserver(this);
    _net = Connectivity().onConnectivityChanged.listen((r) {
      final was = networkUp;
      networkUp = r.any((x) => x != ConnectivityResult.none);
      if (networkUp != was) notifyListeners();
      // a new network (or a different one): the old socket is likely dead, reconnect straight away
      if (networkUp) reconnectNow();
    });
    Connectivity().checkConnectivity().then((r) {
      networkUp = r.any((x) => x != ConnectivityResult.none);
      notifyListeners();
    }).catchError((_) {});
  }

  bool _foreground = true;
  StreamSubscription? _net;
  Timer? _beat;
  DateTime _lastData = DateTime.now();

  /// The phone has some network (Wi-Fi, mobile data, ...). False means "Waiting for network".
  bool networkUp = true;

  /// Fires whenever the socket (re)connects: outboxes and screens catch up then.
  final _online = StreamController<void>.broadcast();
  Stream<void> get onReconnect => _online.stream;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) return; // shade pulled down, app switcher: still on screen
    final fg = state == AppLifecycleState.resumed;
    if (fg == _foreground) return;
    _foreground = fg;
    send({'type': 'app_state', 'fg': fg});
    // back in front: a socket the phone suspended may be dead without having closed
    if (fg) {
      if (!connected || DateTime.now().difference(_lastData) > const Duration(seconds: 30)) reconnectNow();
    }
  }

  /// Drops the current socket (if any) and opens a new one now, skipping the back-off.
  void reconnectNow() {
    if (_token == null) return;
    _attempt = 0;
    final ch = _ch;
    if (ch != null) {
      // probe instead of tearing down a healthy socket: the heartbeat closes it if nothing comes back
      if (connected && DateTime.now().difference(_lastData) < const Duration(seconds: 5)) return;
      send({'type': 'ping'});
      Timer(const Duration(seconds: 4), () {
        if (_ch == ch && DateTime.now().difference(_lastData) > const Duration(seconds: 4)) _closed(ch);
      });
      return;
    }
    _open();
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
        _lastData = DateTime.now();
        if (!_foreground) send({'type': 'app_state', 'fg': false});
        _startBeat(ch);
        notifyListeners();
        _online.add(null);
      }).catchError((_) => _closed(ch));
      ch.stream.listen(_onData, onDone: () => _closed(ch), onError: (_) => _closed(ch));
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _startBeat(WebSocketChannel ch) {
    _beat?.cancel();
    _beat = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_ch != ch) return;
      if (DateTime.now().difference(_lastData) > const Duration(seconds: 45)) {
        _closed(ch); // silent for too long: the link is gone even though it never closed
        return;
      }
      send({'type': 'ping'});
    });
  }

  void _onData(dynamic raw) {
    _lastData = DateTime.now();
    Json m;
    try {
      m = Map<String, dynamic>.from(jsonDecode(raw as String));
    } catch (_) {
      return;
    }
    switch (m['type']) {
      case 'pong':
        return;
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
    _beat?.cancel();
    try {
      ch.sink.close();
    } catch (_) {}
    _ch = null;
    connected = false;
    online.clear();
    notifyListeners();
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_token == null || _retry != null) return;
    _attempt++;
    // quick first retries, then every 15 s; a network change or the app coming back skips the wait
    _retry = Timer(Duration(seconds: _attempt == 1 ? 1 : (_attempt * 2).clamp(2, 15)), () {
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
    _beat?.cancel();
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
    _net?.cancel();
    disconnect();
    _events.close();
    _online.close();
    super.dispose();
  }
}

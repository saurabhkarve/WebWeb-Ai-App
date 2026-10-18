import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api.dart';
import 'auth_provider.dart';
import 'models.dart';
import 'native_calls.dart';
import 'realtime.dart';
import 'screens/post_detail.dart';
import 'screens/profile.dart';
import 'screens/talk.dart' show ChatThread;

/// Push (FCM) + local notifications. What is sent, when and to whom is decided by the API's
/// notification engine; this shows it and opens the right screen on a tap.
///
/// - App open or in background with a live WebSocket: the API sends `notify` / `msg` events instead
///   of pushes, shown here as local notifications (unless that chat is already on screen).
/// - App killed / socket gone: FCM. Everything but calls carries a `notification` payload that the
///   OS shows itself (channel `quiet` during the member's quiet hours).
/// - Calls: iPhones get a VoIP push that rings through CallKit (AppDelegate); Android gets a data-only
///   push that [firebaseBackgroundHandler] turns into the full-screen call UI ([NativeCalls]).
/// - Every push carries `path` (what to open) and `nid` / `sig`: a tap opens it and tells the API,
///   which learns what this member cares about.
class NotificationService with WidgetsBindingObserver {
  NotificationService(this.auth, this.rt, this.nav);

  final AuthProvider auth;
  final RealtimeService rt;
  final GlobalKey<NavigatorState> nav;

  /// Id of the chat currently on screen (set by ChatThread) — no notifications for it.
  static String? activeChat;

  /// Fires when a push arrives while the app is open, so the header's bell updates at once.
  static final activity = StreamController<void>.broadcast();

  static bool get supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
  static bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;

  bool _ready = false;
  bool _asked = false; // notification permission requested this run
  bool _foreground = true;
  String? _registeredFor; // auth token the FCM token was last sent with
  String? _fcmToken;
  final Map<String, String> _names = {};

  Future<void> init() async {
    if (!supported || _ready) return;
    try {
      await initFirebase();
    } catch (e) {
      debugPrint('Firebase init failed: $e');
      return;
    }
    _ready = true;
    WidgetsBinding.instance.addObserver(this);
    await _initLocal(onTap: (r) => _openFromPayload(r.payload));

    final fm = FirebaseMessaging.instance;
    // iOS: in the foreground we show our own local notification (see onMessage), so no system banner too.
    await fm.setForegroundNotificationPresentationOptions(alert: false, badge: true, sound: false);

    // Foreground push: the WebSocket is probably down (otherwise the server would not push),
    // so show it ourselves.
    FirebaseMessaging.onMessage.listen((m) {
      activity.add(null);
      _handleData(m.data, title: m.notification?.title, body: m.notification?.body);
    });
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _openFromData(m.data));
    fm.onTokenRefresh.listen((t) {
      _fcmToken = t;
      _registeredFor = null;
      register();
    });

    rt.events.listen(_onRealtime);
    NativeCalls.events.listen((ev) {
      if (ev is CallEventActionDidUpdateDevicePushTokenVoip) _registerVoip();
    });

    // Cold start from a tapped notification.
    final initial = await fm.getInitialMessage();
    final launch = await _local.getNotificationAppLaunchDetails();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (initial != null) {
        _openFromData(initial.data);
      } else if (launch?.didNotificationLaunchApp == true) {
        _openFromPayload(launch!.notificationResponse?.payload);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    // a registration that failed (no APNs token yet, offline) is retried whenever the app comes back
    if (_foreground && _registeredFor == null) register();
  }

  /// Asks for notification permission once the person is signed in and has a profile
  /// (not on the login screen, where a cold prompt is usually declined).
  Future<void> _askPermission() async {
    if (_asked) return;
    _asked = true;
    await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
    await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
  }

  /// Whether this phone shows our notifications (for the "Get alerts on this device" row).
  Future<bool> alertsEnabled() async {
    if (!_ready) return true; // nothing to offer (e.g. Firebase not configured in this build)
    try {
      final st = (await FirebaseMessaging.instance.getNotificationSettings()).authorizationStatus;
      return st == AuthorizationStatus.authorized || st == AuthorizationStatus.provisional;
    } catch (_) {
      return true;
    }
  }

  /// Asks again; when the person already said no, the OS will not ask, so open the app's settings.
  Future<bool> enableAlerts() async {
    if (!_ready) return true;
    final st = (await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true)).authorizationStatus;
    final on = st == AuthorizationStatus.authorized || st == AuthorizationStatus.provisional;
    if (on) {
      _registeredFor = null;
      await register();
    }
    return on;
  }

  /// Sends this device's FCM token to the backend (once per login).
  Future<void> register() async {
    if (!_ready || auth.token == null || _registeredFor == auth.token) return;
    try {
      await _askPermission();
      // iOS hands out an FCM token only after APNs has registered the device.
      if (_ios) {
        for (var i = 0; i < 20 && await FirebaseMessaging.instance.getAPNSToken() == null; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
      _fcmToken ??= await FirebaseMessaging.instance.getToken();
      if (_fcmToken == null) return;
      await auth.api.post('/app/push/token', {'token': _fcmToken, 'platform': _ios ? 'ios' : 'android'});
      _registeredFor = auth.token;
      await _registerVoip();
      await NativeCalls.requestPermissions();
    } catch (e) {
      debugPrint('push token register failed: $e');
    }
  }

  /// iPhone: the PushKit token that lets calls ring through CallKit when the app is closed.
  String? _voipToken;
  Future<void> _registerVoip([String? token]) async {
    final t = token ?? await NativeCalls.voipToken();
    if (t == null || auth.token == null) return;
    try {
      await auth.api.post('/app/push/token', {'token': t, 'platform': 'ios', 'kind': 'voip'});
      _voipToken = t;
    } catch (e) {
      debugPrint('voip token register failed: $e');
    }
  }

  /// Called before logout so this phone stops getting the old account's pushes.
  Future<void> unregister() async {
    if (!_ready || auth.token == null) return;
    for (final t in [_fcmToken, _voipToken]) {
      if (t == null) continue;
      try {
        await auth.api.post('/app/push/token/remove', {'token': t});
      } catch (_) {}
    }
    _voipToken = null;
    _registeredFor = null;
  }

  // ---------- live events (WebSocket) ----------
  Future<void> _onRealtime(Json e) async {
    final me = auth.profile?.uid;
    switch (e['type']) {
      case 'msg':
        final m = Map<String, dynamic>.from(e['message']);
        if (m['senderUid'] == me) return;
        final chatId = '${e['chatId']}';
        if (_foreground && activeChat == chatId) return;
        // in the background the server sends a push for it (the app told it so); avoid showing it twice
        if (!_foreground && _ready && rt.serverPush) return;
        final name = await _chatPeerName(chatId);
        final hasImage = m['imageUrl'] != null;
        final text = '${m['text'] ?? ''}';
        await showMessage(chatId: chatId, name: name, body: text.isNotEmpty ? text : (hasImage ? '📷 Photo' : 'New message'));
        break;
      case 'notify':
        // the API decided this is worth showing; it chose the socket because the app is connected and in front
        if (!_foreground && _ready && rt.serverPush) return;
        final data = Map<String, dynamic>.from(e['data'] ?? {});
        await showActivity(data, title: '${e['title'] ?? ''}', body: '${e['body'] ?? ''}');
        break;
      // incoming calls ring through CallManager (in-app screen, or the phone's call UI in the background)
      case 'call_end':
      case 'call_unavailable':
        await _local.cancel(id: _callNotifId('${e['callId']}'));
        break;
    }
  }

  /// Name of the other person in a chat (cached).
  Future<String> _chatPeerName(String chatId) async {
    final cached = _names[chatId];
    if (cached != null) return cached;
    try {
      final c = ChatSummary.fromJson(await auth.api.get('/chats/$chatId') as Map, auth.profile?.uid ?? '');
      return _names[chatId] = c.peer.name;
    } catch (_) {
      return 'New message';
    }
  }
  // ---------- push data ----------
  Future<void> _handleData(Map<String, dynamic> d, {String? title, String? body}) async {
    switch (d['type']) {
      case 'msg':
        if (_foreground && activeChat == d['chatId']) return;
        await showMessage(chatId: '${d['chatId']}', name: title ?? '${d['name']}', body: body ?? '');
        break;
      case 'call':
        if (rt.connected) return; // the socket already brought the offer to CallManager
        await handleCallData(d);
        break;
      case 'call_cancel':
        await handleCallData(d);
        break;
      default:
        if (d['kind'] == null && d['path'] == null) return;
        await showActivity(d, title: title ?? 'WEBWEB AI', body: body ?? '');
    }
  }

  // ---------- taps ----------
  void _openFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      _openFromData(Map<String, dynamic>.from(jsonDecode(payload)));
    } catch (_) {}
  }

  Future<void> _openFromData(Map<String, dynamic> d) async {
    // Calls: nothing to do — opening the app reconnects the socket and the server hands over the offer.
    if (d['type'] == 'call' || d['type'] == 'call_cancel') return;
    if (d['nid'] != null && d['sig'] != null) {
      auth.api.post('/notifications/opened', {'id': d['nid'], 'sig': d['sig']}).catchError((_) => null);
    }
    // Wait until the user is logged in and the main shell is up.
    for (var i = 0; i < 40 && (auth.profile == null || nav.currentState == null); i++) {
      await Future.delayed(const Duration(milliseconds: 250));
    }
    final nv = nav.currentState;
    if (nv == null || auth.profile == null) return;
    try {
      final path = '${d['path'] ?? ''}';
      final isChat = d['type'] == 'msg' || d['chatId'] != null || path.startsWith('/chat/') || d['kind'] == 'missed_call';
      if (!isChat) {
        if (d['postId'] != null) {
          nv.push(MaterialPageRoute(builder: (_) => PostDetailScreen(postId: '${d['postId']}')));
          return;
        }
        final post = RegExp(r'^/post/([0-9a-f-]{36})').firstMatch(path)?.group(1);
        if (post != null) {
          nv.push(MaterialPageRoute(builder: (_) => PostDetailScreen(postId: post)));
          return;
        }
        // a page: /@handle (contact requests, catalog items)
        final handle = RegExp(r'^/@([a-z0-9_.-]+)$').firstMatch(path)?.group(1);
        if (handle != null) nv.push(MaterialPageRoute(builder: (_) => ProfileScreen(handle: handle)));
        return; // anything else (catch-ups, feed) just opens the app
      }
      var chatId = '${d['chatId'] ?? ''}';
      if (chatId.isEmpty && path.startsWith('/chat/')) chatId = path.substring(6);
      if (chatId.isEmpty && d['from'] != null) chatId = (await auth.api.post('/chats', {'userId': d['from']}) as Map)['id'] as String;
      if (chatId.isEmpty || activeChat == chatId) return;
      final c = ChatSummary.fromJson(await auth.api.get('/chats/$chatId') as Map, auth.profile!.uid);
      nv.push(MaterialPageRoute(builder: (_) => ChatThread(chatId: chatId, peer: c.peer)));
    } catch (_) {}
  }
}
// ======================= shared with the background isolate =======================

final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
bool _localReady = false;

const _messagesChannel = AndroidNotificationChannel(
  'messages',
  'Messages',
  description: 'New chat messages and missed calls',
  importance: Importance.high,
);
const _asksChannel = AndroidNotificationChannel(
  'asks',
  'Asks',
  description: 'Responses and referrals on your asks and catalog',
  importance: Importance.high,
);
const _activityChannel = AndroidNotificationChannel(
  'activity',
  'Activity',
  description: 'Reactions, reposts, ratings and new asks that fit your business',
  importance: Importance.defaultImportance,
);
const _quietChannel = AndroidNotificationChannel(
  'quiet',
  'Quiet hours',
  description: 'Delivered silently at night',
  importance: Importance.low,
  playSound: false,
  enableVibration: false,
);
const _callsChannel = AndroidNotificationChannel(
  'calls',
  'Incoming calls',
  description: 'Rings when someone calls you',
  importance: Importance.max,
);

const _messageDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'messages',
    'Messages',
    channelDescription: 'New chat messages and missed calls',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.message,
  ),
  iOS: DarwinNotificationDetails(threadIdentifier: 'messages'),
);

const _asksDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'asks',
    'Asks',
    channelDescription: 'Responses and referrals on your asks and catalog',
    importance: Importance.high,
    priority: Priority.high,
  ),
  iOS: DarwinNotificationDetails(threadIdentifier: 'asks'),
);

Future<void> _initLocal({DidReceiveNotificationResponseCallback? onTap}) async {
  if (_localReady && onTap == null) return;
  await _local.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      // permission is asked later by FirebaseMessaging.requestPermission (after sign-in)
      iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
    ),
    onDidReceiveNotificationResponse: onTap,
  );
  final android = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(_messagesChannel);
  await android?.createNotificationChannel(_asksChannel);
  await android?.createNotificationChannel(_callsChannel);
  await android?.createNotificationChannel(_activityChannel);
  await android?.createNotificationChannel(_quietChannel);
  _localReady = true;
}

int _callNotifId(String callId) => callId.hashCode & 0x7fffffff;

Future<void> showMessage({required String chatId, required String name, required String body}) async {
  await _initLocal();
  await _local.show(
    id: chatId.hashCode & 0x7fffffff,
    title: name,
    body: body,
    notificationDetails: _messageDetails,
    payload: jsonEncode({'type': 'msg', 'chatId': chatId, 'name': name}),
  );
}
const _activityDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'activity',
    'Activity',
    channelDescription: 'Reactions, reposts, ratings and new asks that fit your business',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  ),
  iOS: DarwinNotificationDetails(threadIdentifier: 'activity'),
);

/// Any notification from the API's engine (asks, responses, activity, catch-ups). Notifications on the
/// same subject replace each other (same id).
Future<void> showActivity(Map<String, dynamic> d, {required String title, required String body}) async {
  await _initLocal();
  final kind = '${d['kind'] ?? d['type'] ?? ''}';
  if (kind == 'message' || kind == 'msg') {
    await showMessage(chatId: '${d['chatId']}', name: title, body: body);
    return;
  }
  const asks = {'ask_response', 'ask_referral', 'share_asked', 'share_answered', 'contact_request', 'item_referral', 'ask_match'};
  final details = kind == 'missed_call' ? _messageDetails : (asks.contains(kind) ? _asksDetails : _activityDetails);
  final key = '${d['postId'] ?? d['productId'] ?? d['storyId'] ?? d['from'] ?? d['nid'] ?? title}$kind';
  await _local.show(
    id: key.hashCode & 0x7fffffff,
    title: title,
    body: body,
    notificationDetails: details,
    payload: jsonEncode(d),
  );
}

Future<void> showIncomingCall({required String callId, required String from, required String name, required bool video}) async {
  await _initLocal();
  await _local.show(
    id: _callNotifId(callId),
    title: name,
    body: video ? 'Incoming video call' : 'Incoming voice call',
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        'calls',
        'Incoming calls',
        channelDescription: 'Rings when someone calls you',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.call,
        fullScreenIntent: true,
        ongoing: true,
        autoCancel: true,
        timeoutAfter: 45000,
        audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
        additionalFlags: Int32List.fromList([4]), // FLAG_INSISTENT: keep ringing
      ),
      iOS: const DarwinNotificationDetails(presentSound: true, interruptionLevel: InterruptionLevel.timeSensitive),
    ),
    payload: jsonEncode({'type': 'call', 'callId': callId, 'from': from}),
  );
}

/// Data-only call pushes (works in both the main and the background isolate): ring through the phone's
/// own call UI, or stop it when the caller hung up / it was answered elsewhere.
Future<void> handleCallData(Map<String, dynamic> d) async {
  switch (d['type']) {
    case 'call':
      if (NativeCalls.supported) {
        await NativeCalls.showIncoming(
          id: '${d['callId']}',
          name: '${d['name'] ?? 'Someone'}',
          video: d['video'] == 'true',
          from: '${d['from'] ?? ''}',
          handle: '${d['handle'] ?? ''}',
          photo: '${d['photo'] ?? ''}',
        );
      } else {
        await showIncomingCall(callId: '${d['callId']}', from: '${d['from']}', name: '${d['name'] ?? d['from']}', video: d['video'] == 'true');
      }
      break;
    case 'call_cancel':
      await NativeCalls.end('${d['callId']}');
      await _initLocal();
      await _local.cancel(id: _callNotifId('${d['callId']}'));
      break;
  }
}

/// Runs in its own isolate when a push arrives while the app is in the background or killed.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await initFirebase();
  await handleCallData(message.data);
}

/// Android reads android/app/google-services.json. iOS takes its Firebase app from build-time
/// --dart-define values (set in Codemagic), so no GoogleService-Info.plist has to be added to Xcode;
/// without them it falls back to a GoogleService-Info.plist in the Runner target.
Future<void>? _firebaseInit;

/// Safe to call from several places at once (notifications, crash reporting): one initialisation.
Future<void> initFirebase() => _firebaseInit ??= _initFirebase().catchError((Object e) {
      _firebaseInit = null; // let a later call try again
      throw e;
    });

Future<void> _initFirebase() async {
  if (Firebase.apps.isNotEmpty) return;
  const iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  if (defaultTargetPlatform == TargetPlatform.iOS && iosAppId.isNotEmpty) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: String.fromEnvironment('FIREBASE_IOS_API_KEY'),
        appId: iosAppId,
        messagingSenderId: String.fromEnvironment('FIREBASE_SENDER_ID'),
        projectId: String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: 'webweb-ai-app'),
        iosBundleId: 'ai.webweb.app',
      ),
    );
    return;
  }
  await Firebase.initializeApp();
}

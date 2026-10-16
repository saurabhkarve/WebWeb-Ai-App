import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api.dart';
import 'auth_provider.dart';
import 'models.dart';
import 'realtime.dart';
import 'screens/post_detail.dart';
import 'screens/profile.dart';
import 'screens/talk.dart' show ChatThread;

/// Push (FCM) + local notifications for chats, calls and activity on your asks.
///
/// - App open or in background with a live WebSocket: events come over [RealtimeService]
///   and are shown as local notifications (unless that chat is already on screen).
/// - App killed / socket gone: the backend sends an FCM push. Messages carry a
///   `notification` payload (shown by Android itself); incoming calls are data-only and
///   are turned into a full-screen call notification by [firebaseBackgroundHandler].
/// - iOS: the server sends calls as a visible alert (iOS does not wake a killed app for
///   data-only pushes); tapping it opens the app and the socket picks up the pending offer.
/// - Tapping any notification opens what it is about: the chat, the ask, or the profile.
class NotificationService with WidgetsBindingObserver {
  NotificationService(this.auth, this.rt, this.nav);

  final AuthProvider auth;
  final RealtimeService rt;
  final GlobalKey<NavigatorState> nav;

  /// Id of the chat currently on screen (set by ChatThread) — no notifications for it.
  static String? activeChat;

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
    FirebaseMessaging.onMessage.listen((m) => _handleData(m.data, title: m.notification?.title, body: m.notification?.body));
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _openFromData(m.data));
    fm.onTokenRefresh.listen((t) {
      _fcmToken = t;
      _registeredFor = null;
      register();
    });

    rt.events.listen(_onRealtime);

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
        for (var i = 0; i < 10 && await FirebaseMessaging.instance.getAPNSToken() == null; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
      _fcmToken ??= await FirebaseMessaging.instance.getToken();
      if (_fcmToken == null) return;
      await auth.api.post('/app/push/token', {'token': _fcmToken, 'platform': _ios ? 'ios' : 'android'});
      _registeredFor = auth.token;
    } catch (e) {
      debugPrint('push token register failed: $e');
    }
  }

  /// Called before logout so this phone stops getting the old account's pushes.
  Future<void> unregister() async {
    if (!_ready || _fcmToken == null || auth.token == null) return;
    try {
      await auth.api.post('/app/push/token/remove', {'token': _fcmToken});
    } catch (_) {}
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
        final name = await _chatPeerName(chatId);
        final hasImage = m['imageUrl'] != null;
        final text = '${m['text'] ?? ''}';
        await showMessage(chatId: chatId, name: name, body: text.isNotEmpty ? text : (hasImage ? '📷 Photo' : 'New message'));
        break;
      case 'call_offer':
        // In the foreground the call screen is enough; in the background, ring through a notification.
        if (_foreground) return;
        final caller = Map<String, dynamic>.from(e['caller'] ?? {});
        await showIncomingCall(
          callId: '${e['callId']}',
          from: '${e['from']}',
          name: '${caller['name'] ?? 'Someone'}',
          video: e['video'] == true,
        );
        break;
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
      case 'ask_response':
      case 'item_referral':
        await _local.show(
          id: '${d['postId'] ?? d['productId']}'.hashCode & 0x7fffffff,
          title: title ?? 'New activity',
          body: body ?? '',
          notificationDetails: _asksDetails,
          payload: jsonEncode(d),
        );
        break;
      case 'missed_call':
        await _local.show(
          id: '${d['from']}missed'.hashCode,
          title: title ?? 'Missed call',
          body: body ?? '',
          notificationDetails: _messageDetails,
          payload: jsonEncode({'type': 'missed_call', 'from': d['from']}),
        );
        break;
      default:
        await handleCallData(d);
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
    const routable = {'msg', 'missed_call', 'ask_response', 'item_referral'};
    if (!routable.contains(d['type'])) return;
    // Wait until the user is logged in and the main shell is up.
    for (var i = 0; i < 40 && (auth.profile == null || nav.currentState == null); i++) {
      await Future.delayed(const Duration(milliseconds: 250));
    }
    final nv = nav.currentState;
    if (nv == null || auth.profile == null) return;
    try {
      if (d['type'] == 'ask_response' && d['postId'] != null) {
        nv.push(MaterialPageRoute(builder: (_) => PostDetailScreen(postId: '${d['postId']}')));
        return;
      }
      // other links carry the web path: /@handle opens that profile
      final handle = RegExp(r'^/@([a-z0-9]+)').firstMatch('${d['path'] ?? ''}')?.group(1);
      if (d['type'] == 'item_referral') {
        if (handle != null) nv.push(MaterialPageRoute(builder: (_) => ProfileScreen(handle: handle)));
        return;
      }
      var chatId = '${d['chatId'] ?? ''}';
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

/// Data-only call pushes (works in both the main and the background isolate).
Future<void> handleCallData(Map<String, dynamic> d) async {
  switch (d['type']) {
    case 'call':
      await showIncomingCall(
        callId: '${d['callId']}',
        from: '${d['from']}',
        name: '${d['name'] ?? d['from']}',
        video: d['video'] == 'true',
      );
      break;
    case 'call_cancel':
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
Future<void> initFirebase() async {
  if (Firebase.apps.isNotEmpty) return;
  const iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  if (defaultTargetPlatform == TargetPlatform.iOS && iosAppId.isNotEmpty) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: String.fromEnvironment('FIREBASE_IOS_API_KEY'),
        appId: iosAppId,
        messagingSenderId: String.fromEnvironment('FIREBASE_SENDER_ID'),
        projectId: String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: 'webweb-ai'),
        iosBundleId: 'ai.webweb.app',
      ),
    );
    return;
  }
  await Firebase.initializeApp();
}

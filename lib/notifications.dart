import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'device.dart';
import 'auth_provider.dart';
import 'models.dart';
import 'native_calls.dart';
import 'realtime.dart';
import 'widgets.dart';
import 'i18n.dart';
import 'screens/contact_picker.dart';
import 'screens/leads.dart';
import 'screens/p2.dart';
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
  /// the shell shows messages and activity itself, as a banner, while the app is in front
  static bool inAppBanners = false;

  /// Fires when a push arrives while the app is open, so the header's bell updates at once.
  static final activity = StreamController<void>.broadcast();

  static bool get supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
  static bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;

  bool _ready = false;
  bool _asked = false; // notification permission requested this run
  bool _foreground = true;
  String? _registeredFor; // auth token the FCM token was last sent with
  DateTime? _registeredAt; // when it was last sent
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
    await _initLocal(onTap: _onResponse);

    final fm = FirebaseMessaging.instance;
    // iOS: in the foreground we show our own local notification (see onMessage), so no system banner too.
    await fm.setForegroundNotificationPresentationOptions(alert: false, badge: true, sound: false);

    // Foreground push: the WebSocket is probably down (otherwise the server would not push),
    // so show it ourselves.
    FirebaseMessaging.onMessage.listen((m) {
      if (auth.token == null) return; // signed out on this phone: not for it any more
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

    _takePendingAction();
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
    // a registration that failed (no APNs token yet, offline) is retried whenever the app comes back, and the token
    // is sent again at most hourly so a server that lost it (a cleanup, a restore) gets it back on the next open
    if (!_foreground) return;
    _takePendingAction();
    Device.report(auth.api); // permissions may have changed in Settings meanwhile
    if (_registeredFor != null && _registeredAt != null && DateTime.now().difference(_registeredAt!) > const Duration(hours: 1)) {
      _registeredFor = null;
    }
    if (_registeredFor == null) register();
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
      await Device.flushSignOuts(); // an earlier offline sign-out goes first
      await auth.api.post('/app/push/token', {'token': _fcmToken, 'platform': _ios ? 'ios' : 'android', 'deviceId': await Device.load()});
      _registeredFor = auth.token;
      _registeredAt = DateTime.now();
      await _registerVoip();
      await NativeCalls.requestPermissions();
      Device.report(auth.api, force: true);
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
      await auth.api.post('/app/push/token', {'token': t, 'platform': 'ios', 'kind': 'voip', 'deviceId': await Device.load()});
      _voipToken = t;
    } catch (e) {
      debugPrint('voip token register failed: $e');
    }
  }

  /// Called before logout so this phone stops getting the account's pushes: the API forgets this device's
  /// tokens (by device id, so also ones the app no longer knows; kept and sent later when offline), and the
  /// phone's Firebase token itself is dropped, so anything still addressed to it fails and is cleaned up.
  Future<void> unregister() async {
    final tokens = <String>[];
    if (_ready) {
      try {
        _fcmToken ??= await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds: 5));
      } catch (_) {}
      try {
        _voipToken ??= _ios ? await NativeCalls.voipToken() : null;
      } catch (_) {}
      tokens.addAll([_fcmToken, _voipToken].whereType<String>());
    }
    await Device.signOut(auth.api, tokens);
    if (_ready) {
      try {
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {}
      await _local.cancelAll();
    }
    _fcmToken = null;
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
        if (_foreground && inAppBanners) return;
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
        if (_foreground && inAppBanners) return;
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
        await showMessage(chatId: '${d['chatId']}', name: title ?? '${d['title'] ?? d['name']}', body: body ?? '${d['body'] ?? ''}');
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
        await showActivity(d, title: title ?? '${d['title'] ?? 'WEBWEB AI'}', body: body ?? '${d['body'] ?? ''}');
    }
  }

  // ---------- notification buttons ----------
  /// A tap on a notification or on one of its buttons (the app is running; a Reply typed while it was closed went
  /// through [notificationBackgroundResponse]).
  void _onResponse(NotificationResponse r) {
    if (r.actionId == 'reply') {
      _handleReply(r);
    } else if (r.actionId == 'refer') {
      _refer(r.payload);
    } else {
      _openFromPayload(r.payload);
    }
  }

  void _handleReply(NotificationResponse r) {
    final text = (r.input ?? '').trim();
    if (text.isNotEmpty) handleNotificationReply(r.payload, text);
  }

  /// iPhone: the notification's Reply / Refer buttons are handled natively (AppDelegate), which leaves a note here
  /// for what needs the app (Refer opens the contact picker).
  Future<void> _takePendingAction() async {
    if (!_ios) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getString('pending_action');
      if (raw == null) return;
      await prefs.remove('pending_action');
      _refer(raw);
    } catch (_) {}
  }

  /// "Refer" on a lead notification: the ask opens and the member picks the contacts to refer.
  Future<void> _refer(String? payload) async {
    String? postId;
    var asker = '';
    try {
      final d = jsonDecode(payload ?? '{}') as Map;
      postId = '${d['postId'] ?? ''}';
      asker = '${d['body'] ?? ''}'.split(' · ').first;
    } catch (_) {}
    if (postId == null || postId.isEmpty) return _openFromPayload(payload);
    for (var i = 0; i < 40 && (auth.profile == null || nav.currentState == null); i++) {
      await Future.delayed(const Duration(milliseconds: 250));
    }
    final nv = nav.currentState;
    final ctx = nav.currentContext;
    if (nv == null || ctx == null || auth.profile == null) return;
    nv.push(MaterialPageRoute(builder: (_) => PostDetailScreen(postId: postId!)));
    try {
      final mine = ((await auth.api.get('/app/posts/$postId/referrals/mine')) as List).length;
      if (mine >= 5) return;
      final picked = await nv.push<List<PickedContact>>(MaterialPageRoute(builder: (_) => ContactPicker(askerName: asker, maxSelect: 5 - mine)));
      var ok = 0;
      for (final c in picked ?? const <PickedContact>[]) {
        try {
          await auth.api.post('/posts/$postId/refer', {'name': c.name, 'phone': c.phone});
          ok++;
        } catch (_) {}
      }
      final c2 = nav.currentContext;
      if (ok > 0 && c2 != null && c2.mounted) toast(c2, t('Referral sent'));
    } catch (_) {}
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
        // "Your week" (the Monday scorecard)
        if (path == '/week') {
          nv.push(MaterialPageRoute(builder: (_) => SubPage(title: t('Your week'), body: const WeekScreen())));
          return;
        }
        // P2: Today (a morning notice, a question's result), alerts (the 8 pm summary goes to Leads), an update's reach
        if (path.startsWith('/today')) {
          final poll = Uri.tryParse(path)?.queryParameters['poll'];
          nv.push(MaterialPageRoute(builder: (_) => SubPage(title: t('Today in your area'), body: TodayScreen(poll: poll))));
          return;
        }
        if (path == '/alerts') {
          nv.push(MaterialPageRoute(builder: (_) => SubPage(title: t('Alerts'), body: const AlertsScreen())));
          return;
        }
        if (path == '/leads') {
          nv.push(MaterialPageRoute(builder: (_) => SubPage(title: t('Leads for you'), body: const LeadsScreen())));
          return;
        }
        if (path.startsWith('/update/') && auth.profile != null) {
          nv.push(MaterialPageRoute(builder: (_) => ProfileScreen(handle: auth.profile!.handle)));
          return;
        }
        if (d['postId'] != null) {
          // "Did you find someone?" opens the ask with the question in view
          nv.push(MaterialPageRoute(builder: (_) => PostDetailScreen(postId: '${d['postId']}', askOutcome: d['kind'] == 'ask_outcome' || path.contains('outcome=1'))));
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
      if (chatId.isEmpty && _sender(d) != null) chatId = (await auth.api.post('/chats', {'userId': _sender(d)}) as Map)['id'] as String;
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

/// Reply from the notification itself (Android: an inline text box; iPhone: the MESSAGE / ASK category in AppDelegate).
const _replyAction = AndroidNotificationAction(
  'reply',
  'Reply',
  inputs: [AndroidNotificationActionInput(label: 'Reply')],
  allowGeneratedReplies: true,
  semanticAction: SemanticAction.reply,
  cancelNotification: false,
);
const _askReplyAction = AndroidNotificationAction(
  'reply',
  'Reply',
  inputs: [AndroidNotificationActionInput(label: 'I can do this: price, when')],
  semanticAction: SemanticAction.reply,
);
const _referAction = AndroidNotificationAction('refer', 'Refer', showsUserInterface: true);

const _messageDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'messages',
    'Messages',
    channelDescription: 'New chat messages and missed calls',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.message,
    groupKey: 'messages',
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
    groupKey: 'asks',
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
    onDidReceiveBackgroundNotificationResponse: notificationBackgroundResponse,
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

int _chatNotifId(String chatId) => chatId.hashCode & 0x7fffffff;
const _summaryId = 0x7ffffff0;

/// What a chat's notification shows: the last few lines, theirs and the ones sent from the notification.
Future<List<Map<String, dynamic>>> _chatLines(String chatId, {String? add, bool mine = false}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final key = 'nh_$chatId';
  final lines = <Map<String, dynamic>>[];
  for (final e in prefs.getStringList(key) ?? const <String>[]) {
    try {
      lines.add(Map<String, dynamic>.from(jsonDecode(e) as Map));
    } catch (_) {}
  }
  if (add != null) {
    lines.add({'t': add, 'me': mine, 'ts': DateTime.now().millisecondsSinceEpoch});
    if (lines.length > 6) lines.removeRange(0, lines.length - 6);
    await prefs.setStringList(key, [for (final l in lines) jsonEncode(l)]);
  }
  return lines;
}

/// The chat is open or answered: its notification and the lines it kept go away.
Future<void> clearChatNotification(String chatId) async {
  try {
    await _initLocal();
    await _local.cancel(id: _chatNotifId(chatId));
    (await SharedPreferences.getInstance()).remove('nh_$chatId');
  } catch (_) {}
}

/// One notification per chat (the same person or group): new messages are added to it as lines (Android:
/// MessagingStyle with a Reply box, several chats fold into one group; iPhone: threadIdentifier = the chat).
Future<void> showMessage({required String chatId, required String name, required String body, bool quiet = false, String? sent, bool failed = false}) async {
  await _initLocal();
  final lines = await _chatLines(chatId, add: sent ?? body, mine: sent != null);
  final them = Person(name: name, key: chatId);
  const me = Person(name: 'You', key: 'me');
  await _local.show(
    id: _chatNotifId(chatId),
    title: name,
    body: lines.last['t'] as String,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        quiet ? 'quiet' : 'messages',
        quiet ? 'Quiet hours' : 'Messages',
        channelDescription: 'New chat messages and missed calls',
        importance: quiet ? Importance.low : Importance.high,
        priority: quiet ? Priority.low : Priority.high,
        category: AndroidNotificationCategory.message,
        groupKey: 'messages',
        tag: chatId,
        onlyAlertOnce: sent != null,
        actions: const [_replyAction],
        styleInformation: MessagingStyleInformation(
          me,
          conversationTitle: name,
          groupConversation: false,
          messages: [for (final l in lines) Message(l['t'] as String, DateTime.fromMillisecondsSinceEpoch(l['ts'] as int), l['me'] == true ? me : them)],
        ),
      ),
      iOS: DarwinNotificationDetails(threadIdentifier: chatId, categoryIdentifier: 'MESSAGE'),
    ),
    payload: jsonEncode({'type': 'msg', 'chatId': chatId, 'name': name}),
  );
  await _summary('messages', 'Messages', 'New messages');
}

/// Android folds notifications of one group under a summary; without one they would not be grouped below four.
Future<void> _summary(String group, String channelName, String text) async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  await _local.show(
    id: _summaryId + (group == 'messages' ? 0 : group == 'asks' ? 1 : 2),
    title: 'WEBWEB AI',
    body: text,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        group == 'messages' ? 'messages' : 'asks',
        channelName,
        groupKey: group,
        setAsGroupSummary: true,
        groupAlertBehavior: GroupAlertBehavior.children,
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: const InboxStyleInformation([]),
      ),
    ),
  );
}

/// A Reply typed into a notification (also when the app is closed): sent as a chat message, or as "I can do this"
/// on a lead. The notification then shows it, or says it was not sent.
Future<void> handleNotificationReply(String? payload, String text) async {
  Map<String, dynamic> d;
  try {
    d = Map<String, dynamic>.from(jsonDecode(payload ?? '{}') as Map);
  } catch (_) {
    return;
  }
  final ok = await sendNotificationReply(d, text);
  await _initLocal();
  final chatId = '${d['chatId'] ?? ''}';
  if (chatId.isNotEmpty) {
    await showMessage(chatId: chatId, name: '${d['name'] ?? 'Chat'}', body: '', sent: ok ? text : 'Not sent: $text. Tap to try again.');
  } else {
    await _local.cancel(id: _activityId(d, ''));
    if (!ok) await _showFailed(d);
  }
}

Future<void> _showFailed(Map<String, dynamic> d) => _local.show(
      id: _activityId(d, ''),
      title: 'Reply not sent',
      body: 'Tap to open the ask and try again',
      notificationDetails: const NotificationDetails(android: AndroidNotificationDetails('asks', 'Asks', groupKey: 'asks'), iOS: DarwinNotificationDetails(threadIdentifier: 'asks')),
      payload: jsonEncode(d),
    );

/// Sends a notification's Reply with the saved sign-in (this also runs in the background isolate).
Future<bool> sendNotificationReply(Map<String, dynamic> d, String text) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final token = prefs.getString('token');
  if (token == null) return false;
  final api = Api(() => token);
  try {
    final chatId = '${d['chatId'] ?? ''}';
    final postId = '${d['postId'] ?? ''}';
    if (chatId.isNotEmpty) {
      await api.post('/chats/$chatId/messages', {'text': text, 'clientId': NativeCalls.newCallId()});
    } else if (postId.isNotEmpty) {
      await api.post('/posts/$postId/share', {'kind': 'info', 'text': text, 'canDo': true});
    } else {
      return false;
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// Reply typed into a notification while the app is closed (Android runs this in a background isolate).
@pragma('vm:entry-point')
Future<void> notificationBackgroundResponse(NotificationResponse r) async {
  if (r.actionId != 'reply') return;
  final text = (r.input ?? '').trim();
  if (text.isNotEmpty) await handleNotificationReply(r.payload, text);
}

const _activityDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'activity',
    'Activity',
    channelDescription: 'Reactions, reposts, ratings and new asks that fit your business',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    groupKey: 'activity',
  ),
  iOS: DarwinNotificationDetails(threadIdentifier: 'activity'),
);

int _activityId(Map<String, dynamic> d, String title) {
  final kind = '${d['kind'] ?? d['type'] ?? ''}';
  final key = '${d['postId'] ?? d['productId'] ?? d['storyId'] ?? _sender(d) ?? d['nid'] ?? title}$kind';
  return key.hashCode & 0x7fffffff;
}

/// Any notification from the API's engine (asks, responses, activity, catch-ups). Notifications on the
/// same subject replace each other (same id). A new lead (ask_match) has Reply ("I can do this") and Refer.
Future<void> showActivity(Map<String, dynamic> d, {required String title, required String body}) async {
  await _initLocal();
  final kind = '${d['kind'] ?? d['type'] ?? ''}';
  if (kind == 'message' || kind == 'msg') {
    await showMessage(chatId: '${d['chatId']}', name: title, body: body, quiet: d['channel'] == 'quiet');
    return;
  }
  const asks = {'ask_response', 'ask_referral', 'ask_reaction', 'ask_repost', 'ask_shared', 'ask_thread', 'share_asked', 'share_answered', 'contact_request', 'item_referral', 'ask_match', 'ask_won', 'ask_outcome'};
  final lead = kind == 'ask_match' && '${d['postId'] ?? ''}'.isNotEmpty;
  final quiet = d['channel'] == 'quiet';
  final isAsk = asks.contains(kind);
  final NotificationDetails details;
  if (kind == 'missed_call') {
    details = _messageDetails;
  } else if (lead) {
    details = NotificationDetails(
      android: AndroidNotificationDetails(
        quiet ? 'quiet' : 'asks',
        quiet ? 'Quiet hours' : 'Asks',
        channelDescription: 'Responses and referrals on your asks and catalog',
        importance: quiet ? Importance.low : Importance.high,
        priority: quiet ? Priority.low : Priority.high,
        groupKey: 'asks',
        actions: const [_askReplyAction, _referAction],
      ),
      iOS: DarwinNotificationDetails(threadIdentifier: 'ask-${d['postId']}', categoryIdentifier: 'ASK'),
    );
  } else if (isAsk) {
    details = _asksDetails;
  } else {
    details = _activityDetails;
  }
  await _local.show(
    id: _activityId(d, title),
    title: title,
    body: body,
    notificationDetails: details,
    payload: jsonEncode(d),
  );
  if (isAsk) {
    await _summary('asks', 'Asks', 'Activity on your asks');
  } else if (details == _activityDetails) {
    await _summary('activity', 'Activity', 'New activity');
  }
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

/// The sender's id in a push: Firebase reserves the key `from`, so the API sends `fromUid` (older servers sent `from`).
Object? _sender(Map<String, dynamic> d) => d['fromUid'] ?? d['from'];

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
          from: '${_sender(d) ?? ''}',
          handle: '${d['handle'] ?? ''}',
          photo: '${d['photo'] ?? ''}',
        );
      } else {
        await showIncomingCall(callId: '${d['callId']}', from: '${_sender(d)}', name: '${d['name'] ?? _sender(d)}', video: d['video'] == 'true');
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
  // signed out on this phone: a push still on its way is not for it (no ringing for a call)
  if (message.data['type'] == 'call' && (await SharedPreferences.getInstance()).getString('token') == null) return;
  await initFirebase();
  // Android messages and leads arrive data-only (the API: app-push.ts), so the app shows them, with their buttons
  final d = message.data;
  if (message.notification == null && d['title'] != null && (d['kind'] == 'message' || d['kind'] == 'ask_match')) {
    if ((await SharedPreferences.getInstance()).getString('token') == null) return;
    try {
      await showActivity(d, title: '${d['title']}', body: '${d['body'] ?? ''}');
    } catch (_) {}
    return;
  }
  await handleCallData(message.data);
  // the main app may not be running to hear the phone's Decline: wait here for this call's answer
  if (message.data['type'] == 'call' && NativeCalls.supported) await _declineWhenDeclined('${message.data['callId']}');
}

/// Until the call shown from a background push is answered, declined or gone (45 s ring + a margin): a Decline
/// goes to the API from here, so the caller stops ringing at once.
Future<void> _declineWhenDeclined(String callId) async {
  final done = Completer<void>();
  final sub = NativeCalls.events.listen((ev) async {
    switch (ev) {
      case CallEventActionCallDecline(:final callKitParams) when callKitParams.id == callId:
        await declineCallOnServer(callId);
        if (!done.isCompleted) done.complete();
      case CallEventActionCallAccept(:final callKitParams) when callKitParams.id == callId:
      case CallEventActionCallEnded(:final callKitParams) when callKitParams.id == callId:
        if (!done.isCompleted) done.complete();
      case CallEventActionCallTimeout(:final id) when id == callId:
        if (!done.isCompleted) done.complete();
      default:
        break;
    }
  });
  await done.future.timeout(const Duration(seconds: 55), onTimeout: () {});
  await sub.cancel();
}

/// Tells the API a call was declined, with the saved sign-in (works in the background isolate, which has no
/// AuthProvider). The API takes the first of this and the socket's call_reject; a second one is a harmless 404.
Future<void> declineCallOnServer(String callId) async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('token');
  if (token == null) return;
  final device = prefs.getString('device_id');
  await Api(() => token).post('/app/calls/$callId/decline', {if (device != null) 'deviceId': device}).catchError((_) => null);
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

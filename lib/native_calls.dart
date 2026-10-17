import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

/// The phone's own incoming-call UI, so a WEBWEB call rings like a phone call even when the app is closed:
/// - iPhone: CallKit. The API sends a VoIP push; AppDelegate (PushKit) hands it to CallKit at once, as
///   Apple requires. Calls that arrive over the socket while the app is in the background use it too.
/// - Android: a full-screen call screen started from a high-priority data push (see notifications.dart).
/// Answer / decline come back as events that [CallManager] handles. Safe to call from the background isolate.
class NativeCalls {
  static bool get supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// CallKit needs UUIDs as call ids; the API and the website use the same.
  static String newCallId() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  static Future<void> showIncoming({
    required String id,
    required String name,
    required bool video,
    String? from,
    String? handle,
    String? photo,
  }) async {
    if (!supported) return;
    try {
      await FlutterCallkitIncoming.showCallkitIncoming(CallKitParams(
        id: id,
        nameCaller: name,
        appName: 'WEBWEB AI',
        avatar: (photo ?? '').isNotEmpty ? photo : null,
        handle: (handle ?? '').isNotEmpty ? '@$handle' : (video ? 'Video call' : 'Voice call'),
        type: video ? 1 : 0,
        duration: 45000,
        // the API sends its own "Missed call" notification
        missedCallNotification: const NotificationParams(showNotification: false, isShowCallback: false),
        callingNotification: const NotificationParams(showNotification: false),
        extra: {'from': from ?? '', 'video': video},
        android: const AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          isShowFullLockedScreen: true,
          isImportant: true,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#1E1E1E',
          actionColor: '#22C55E',
          textColor: '#FFFFFF',
          incomingCallNotificationChannelName: 'Incoming calls',
          missedCallNotificationChannelName: 'Missed calls',
          textAccept: 'Answer',
          textDecline: 'Decline',
        ),
        ios: const IOSParams(
          handleType: 'generic',
          supportsVideo: true,
          maximumCallGroups: 1,
          maximumCallsPerCallGroup: 1,
          supportsDTMF: false,
          supportsHolding: false,
          supportsGrouping: false,
          supportsUngrouping: false,
          includesCallsInRecents: true,
          ringtonePath: 'system_ringtone_default',
          configureAudioSession: true,
          audioSessionMode: 'voiceChat',
          audioSessionActive: true,
          audioSessionPreferredSampleRate: 44100.0,
          audioSessionPreferredIOBufferDuration: 0.005,
        ),
      ));
    } catch (e) {
      debugPrint('native call UI failed: $e');
    }
  }

  /// Tells the OS the call is live (iOS shows it in the status bar / call list).
  static Future<void> connected(String id) async {
    if (!supported) return;
    try {
      await FlutterCallkitIncoming.setCallConnected(id);
    } catch (_) {}
  }

  /// Stops the ringing / closes the native call (CallKit must be told when a call ends).
  static Future<void> end(String id) async {
    if (!supported) return;
    try {
      await FlutterCallkitIncoming.endCall(id);
    } catch (_) {}
  }

  /// Calls the OS says are ringing or live (e.g. one answered on the lock screen before the app started).
  static Future<List<CallKitParams>> active() async {
    if (!supported) return const [];
    try {
      return await FlutterCallkitIncoming.activeCalls();
    } catch (_) {
      return const [];
    }
  }

  /// iPhone's PushKit token (empty until iOS hands it out; [onEvent] reports updates).
  static Future<String?> voipToken() async {
    if (defaultTargetPlatform != TargetPlatform.iOS || kIsWeb) return null;
    try {
      final t = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
      return (t ?? '').isEmpty ? null : t;
    } catch (_) {
      return null;
    }
  }

  /// Android 14+: full-screen call screens need the user's OK; asks once after sign-in.
  static Future<void> requestPermissions() async {
    if (defaultTargetPlatform != TargetPlatform.android || kIsWeb) return;
    try {
      if (!await FlutterCallkitIncoming.canUseFullScreenIntent()) await FlutterCallkitIncoming.requestFullIntentPermission();
    } catch (_) {}
  }

  static Stream<CallEvent?> get events => supported ? FlutterCallkitIncoming.onEvent : const Stream.empty();
}

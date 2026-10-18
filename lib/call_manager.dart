import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' hide AndroidAudioMode;

import 'api.dart';
import 'i18n.dart';
import 'native_calls.dart';
import 'permissions.dart';
import 'realtime.dart';
import 'screens/call_screen.dart';

enum CallState { calling, ringing, connecting, connected, ended }

class ActiveCall {
  final String id;
  final Json user; // the other person
  final bool video;
  final bool incoming;
  CallState state;
  String? note;
  DateTime? connectedAt;
  bool muted = false, camOff = false, speaker;
  /// the other side's connection dropped; the API gives it 15 s to come back
  bool peerAway = false;
  /// our own connection dropped mid-call (network switch, tunnel…); ICE is being restarted
  bool reconnecting = false;
  /// handled by the phone's call UI: CallKit (every iPhone call) / the Android lock-screen call screen
  bool native = false;
  Json? offerSdp;
  ActiveCall({
    required this.id,
    required this.user,
    required this.video,
    required this.incoming,
    required this.state,
    this.offerSdp,
  }) : speaker = video;
}

/// WebRTC voice/video calls. Signalling goes through [RealtimeService] (the API relays
/// offer/ringing/answer/ICE, the same protocol as the website, so app and web can call each other).
/// ICE servers (STUN + our TURN relay) come from the API. Like WhatsApp:
/// - iPhone: every call goes through CallKit ([NativeCalls]), incoming (also in the foreground, as the
///   system banner) and outgoing, so it shows on the lock screen, in the status bar and in Recents.
/// - Android: in the foreground a call rings on the in-app screen, in the background or when the app was
///   closed on the full-screen call screen; during the call the "Ongoing call" service keeps the microphone.
/// - A dropped connection (Wi-Fi to mobile data, a tunnel) shows "Reconnecting…" and the caller restarts
///   ICE; the call only ends when it cannot come back within [_reconnectFor].
/// - Voice calls on the earpiece turn the screen off at the ear; video calls keep it on.
class CallManager extends ChangeNotifier with WidgetsBindingObserver {
  final RealtimeService rt;
  final GlobalKey<NavigatorState> nav;
  final Api api;

  CallManager(this.rt, this.nav, this.api) {
    rt.events.listen(_onEvent);
    WidgetsBinding.instance.addObserver(this);
    NativeCalls.events.listen(_onNative);
    _adoptNativeAccepted();
    rt.addListener(() {
      if (rt.connected) _adoptNativeAccepted();
    });
    // back online mid-call: the old network path is gone, so restart ICE right away
    rt.onReconnect.listen((_) {
      if (current?.reconnecting == true) _restartIce();
    });
    NativeCalls.onHangUp(() {
      if (inCall) hangUp();
    });
  }

  bool _foreground = true;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _syncDevice(); // Android only starts the call service from the foreground
  }

  /// How long a dropped call may try to come back before it ends.
  static const _reconnectFor = Duration(seconds: 25);
  Timer? _dropTimer, _restartTimer;
  bool _restarting = false;
  bool _serviceOn = false, _serviceConnected = false;

  /// The phone's side of the call: Android's ongoing-call service, the proximity sensor, the screen.
  void _syncDevice() {
    final c = current;
    final live = c != null && c.state != CallState.ended && !(c.incoming && c.state == CallState.ringing);
    final connected = live && c.state == CallState.connected;
    if (!live) {
      if (_serviceOn) NativeCalls.service(on: false);
      _serviceOn = _serviceConnected = false;
    } else if (_foreground && (!_serviceOn || _serviceConnected != connected)) {
      _serviceOn = true;
      _serviceConnected = connected;
      NativeCalls.service(
        on: true,
        name: _displayName(c.user),
        video: c.video,
        connected: connected,
        status: connected ? '${t(c.video ? 'Ongoing video call' : 'Ongoing voice call')} · ${t('Tap to return')}' : t('Calling…'),
        hangUp: t('Hang up'),
      );
    }
    NativeCalls.proximity(live && !c.video && !c.speaker);
    NativeCalls.keepAwake(live && c.video);
  }

  static String _displayName(Json u) =>
      '${u['userType'] == 'entrepreneur' && '${u['company'] ?? ''}'.isNotEmpty ? u['company'] : u['name'] ?? 'Someone'}';

  /// Calls answered on the lock screen before their offer reached the app (the API re-sends it on connect).
  final Set<String> _nativeAccepted = {};

  Future<void> _adoptNativeAccepted() async {
    for (final c in await NativeCalls.active()) {
      if (c.isAccepted && current?.id != c.id) _nativeAccepted.add(c.id);
    }
  }

  static const _fallbackIce = [
    {'urls': ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302']},
  ];
  List<dynamic>? _ice;
  DateTime _iceAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// STUN + TURN (short-lived credentials) from the API, reused for an hour.
  Future<Map<String, dynamic>> _iceConfig() async {
    if (_ice == null || DateTime.now().difference(_iceAt) > const Duration(hours: 1)) {
      try {
        final r = await api.get('/app/ice') as Map;
        _ice = List<dynamic>.from(r['iceServers'] as List);
        _iceAt = DateTime.now();
      } catch (_) {
        _ice ??= _fallbackIce;
      }
    }
    return {'iceServers': _ice, 'sdpSemantics': 'unified-plan'};
  }

  ActiveCall? current;
  final localR = RTCVideoRenderer();
  final remoteR = RTCVideoRenderer();
  bool _renderersReady = false;
  RTCPeerConnection? _pc;
  MediaStream? _local;
  bool _remoteSet = false;
  final List<RTCIceCandidate> _pendingIce = [];
  bool _screenOpen = false;
  Timer? _timeoutTimer;

  // Sound players
  final AudioPlayer _ringbackPlayer = AudioPlayer();
  bool _isPlayingRingback = false;
  bool _isPlayingRingtone = false;

  bool get inCall => current != null && current!.state != CallState.ended;
  bool get isScreenOpen => _screenOpen;

  void setScreenVisible(bool visible) {
    _screenOpen = visible;
    notifyListeners();
  }

  Future<void> _initRenderers() async {
    if (_renderersReady) return;
    await localR.initialize();
    await remoteR.initialize();
    _renderersReady = true;
  }

  /// Microphone (and camera for video) checked right before every call, with the explaining pop-up
  /// when either was turned off ([Permissions.ensure]).
  Future<bool> _mediaAllowed(bool video) async {
    final ctx = nav.currentContext;
    if (ctx == null) return true; // no screen yet (e.g. answered on the lock screen): getUserMedia reports it
    if (!await Permissions.ensure(ctx, Need.microphone, reason: t('To talk on WEBWEB calls.'))) return false;
    if (!video) return true;
    final ctx2 = nav.currentContext;
    if (ctx2 == null || !ctx2.mounted) return true;
    return Permissions.ensure(ctx2, Need.camera, reason: t('To show your video in this call.'));
  }

  /// A readable reason for a failed getUserMedia / call setup.
  static String _mediaError(Object e, bool video) {
    final m = '$e'.toLowerCase();
    if (m.contains('permission') || m.contains('notallowed') || m.contains('denied')) {
      return video
          ? t('Allow microphone and camera access for WEBWEB in Settings to make video calls.')
          : t('Allow microphone access for WEBWEB in Settings to make calls.');
    }
    if (m.contains('notfound') || m.contains('not found')) return t('No microphone or camera found on this phone.');
    return t('Could not start the call');
  }

  void openScreen() {
    if (_screenOpen) return;
    final nv = nav.currentState;
    if (nv == null) return;
    _screenOpen = true;
    notifyListeners();
    nv
        .push(MaterialPageRoute(builder: (_) => const CallScreen()))
        .whenComplete(() {
      _screenOpen = false;
      notifyListeners();
    });
  }

  // ---------- Ringtone & Ringback sounds ----------
  static Uint8List _ringbackWav() {
    const rate = 8000;
    const seconds = 4;
    const n = rate * seconds;
    final data = ByteData(44 + n * 2);
    void str(int o, String v) {
      for (var i = 0; i < v.length; i++) {
        data.setUint8(o + i, v.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    data.setUint32(4, 36 + n * 2, Endian.little);
    str(8, 'WAVEfmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little); // PCM
    data.setUint16(22, 1, Endian.little); // mono
    data.setUint32(24, rate, Endian.little);
    data.setUint32(28, rate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    str(36, 'data');
    data.setUint32(40, n * 2, Endian.little);
    for (var i = 0; i < rate; i++) {
      final edge = math.min(math.min(i, rate - i) / 200, 1.0);
      final v = math.sin(2 * math.pi * 425 * i / rate) * 0.25 * edge;
      data.setInt16(44 + i * 2, (v * 32767).round(), Endian.little);
    }
    return data.buffer.asUint8List();
  }

  Future<void> _playRingback() async {
    if (_isPlayingRingback) return;
    _isPlayingRingback = true;
    final video = current?.video ?? false;
    try {
      // in the call's own audio route (earpiece for voice, like a phone), without taking the
      // microphone's audio session away on iOS
      await _ringbackPlayer.setAudioContext(AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playAndRecord,
          options: {AVAudioSessionOptions.allowBluetooth, if (video) AVAudioSessionOptions.defaultToSpeaker},
        ),
        android: AudioContextAndroid(
          isSpeakerphoneOn: video,
          audioMode: AndroidAudioMode.inCommunication,
          contentType: AndroidContentType.speech,
          usageType: AndroidUsageType.voiceCommunication,
          audioFocus: AndroidAudioFocus.gainTransient,
        ),
      ));
      await _ringbackPlayer.setReleaseMode(ReleaseMode.loop);
      await _ringbackPlayer.play(BytesSource(_ringbackWav()));
    } catch (_) {}
  }

  void _playIncomingRingtone() {
    if (_isPlayingRingtone) return;
    _isPlayingRingtone = true;
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      try {
        FlutterRingtonePlayer().play(
          android: AndroidSounds.ringtone,
          ios: IosSounds.electronic,
          looping: true,
          volume: 1.0,
        );
      } catch (_) {}
    }
  }

  void _stopSounds() {
    if (_isPlayingRingback) {
      _isPlayingRingback = false;
      try {
        _ringbackPlayer.stop();
      } catch (_) {}
    }
    if (_isPlayingRingtone) {
      _isPlayingRingtone = false;
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        try {
          FlutterRingtonePlayer().stop();
        } catch (_) {}
      }
    }
  }

  // ---------- Outgoing Call ----------
  Future<void> startCall(Json user, bool video) async {
    if (current != null) return;
    if (!rt.networkUp) throw t("You're offline. Calls need an internet connection.");
    if (!rt.connected) {
      rt.reconnectNow();
      throw t('Connecting to WEBWEB… try again in a moment.');
    }
    if (!await _mediaAllowed(video)) return;
    if (current != null) return;
    final id = NativeCalls.newCallId();
    final c = current = ActiveCall(
      id: id,
      user: user,
      video: video,
      incoming: false,
      state: CallState.calling,
    );
    if (defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb) {
      c.native = true;
      NativeCalls.startOutgoing(id: id, name: _displayName(user), video: video, handle: '${user['handle'] ?? ''}');
    }
    notifyListeners();
    openScreen();
    _syncDevice();

    // 45s ringing timeout
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 45), () {
      if (current?.id == id && current?.state != CallState.connected) {
        hangUp(note: 'No answer');
      }
    });

    try {
      await _initRenderers();
      await _createPc(video);
      if (current != c) return;
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      rt.send({
        'type': 'call_offer',
        'callId': id,
        'to': user['uid'],
        'video': video,
        'sdp': {'sdp': offer.sdp, 'type': offer.type},
      });
    } catch (e) {
      if (current == c) _finish(_mediaError(e, video));
    }
  }

  // ---------- Incoming Call ----------
  Future<void> accept() async {
    final c = current;
    if (c == null || !c.incoming || c.offerSdp == null) return;
    _stopSounds();
    if (!await _mediaAllowed(c.video)) {
      if (current == c) hangUp(note: c.video ? 'Camera or microphone is off' : 'Microphone is off');
      return;
    }
    if (current != c || c.state == CallState.ended) return;
    c.state = CallState.connecting;
    notifyListeners();
    _syncDevice();
    try {
      await _initRenderers();
      await _createPc(c.video);
      await _pc!.setRemoteDescription(
          RTCSessionDescription(c.offerSdp!['sdp'], c.offerSdp!['type']));
      _remoteSet = true;
      await _flushIce();
      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      rt.send({
        'type': 'call_answer',
        'callId': c.id,
        'sdp': {'sdp': answer.sdp, 'type': answer.type},
      });
    } catch (e) {
      if (current == c) hangUp(note: _mediaError(e, c.video));
    }
  }

  void reject() {
    final c = current;
    if (c == null) return;
    _stopSounds();
    _signalEnd(c.id, decline: true);
    _finish('Declined');
  }

  void hangUp({String? note}) {
    final c = current;
    if (c == null) return;
    _stopSounds();
    _timeoutTimer?.cancel();
    _signalEnd(c.id, decline: false);
    _finish(note ?? 'Call ended');
  }

  /// Over the socket, or over REST when it is down (e.g. declined on the lock screen right after waking).
  void _signalEnd(String id, {required bool decline}) {
    if (rt.send({'type': decline ? 'call_reject' : 'call_end', 'callId': id})) return;
    api.post('/app/calls/$id/${decline ? 'decline' : 'end'}', {}).catchError((_) => null);
  }

  // ---------- the phone's own call UI ----------
  void _onNative(CallEvent? ev) {
    switch (ev) {
      case CallEventActionCallAccept(:final callKitParams):
        final id = callKitParams.id;
        if (current?.id == id) {
          openScreen();
          if (current!.state == CallState.ringing) accept();
        } else {
          _nativeAccepted.add(id); // the offer arrives once the socket is up
        }
      case CallEventActionCallDecline(:final callKitParams):
        final id = callKitParams.id;
        if (current?.id == id) {
          reject();
        } else {
          _signalEnd(id, decline: true);
        }
      case CallEventActionCallEnded(:final callKitParams):
        if (current?.id == callKitParams.id && current!.state != CallState.ended) hangUp();
      case CallEventActionCallToggleMute(:final isMuted):
        if (current != null && current!.muted != isMuted) toggleMute();
      default:
        break;
    }
  }

  // ---------- Media & Controls ----------
  void toggleMute() {
    final c = current;
    if (c == null) return;
    c.muted = !c.muted;
    for (final t in _local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !c.muted;
    }
    if (c.native) NativeCalls.muted(c.id, c.muted);
    notifyListeners();
  }

  void toggleCamera() {
    final c = current;
    if (c == null || !c.video) return;
    c.camOff = !c.camOff;
    for (final t in _local?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !c.camOff;
    }
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final tracks = _local?.getVideoTracks() ?? [];
    if (tracks.isNotEmpty) await Helper.switchCamera(tracks.first);
  }

  Future<void> toggleSpeaker() async {
    final c = current;
    if (c == null) return;
    c.speaker = !c.speaker;
    if (!kIsWeb) await Helper.setSpeakerphoneOn(c.speaker);
    _syncDevice();
    notifyListeners();
  }

  // ---------- Peer Connection Setup ----------
  Future<void> _createPc(bool video) async {
    _remoteSet = false;
    _pendingIce.clear();
    final pc = await createPeerConnection(await _iceConfig());
    _pc = pc;

    _local = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video ? {'facingMode': 'user'} : false,
    });
    localR.srcObject = _local;

    for (final t in _local!.getTracks()) {
      await pc.addTrack(t, _local!);
    }

    pc.onIceCandidate = (c) {
      final id = current?.id;
      if (id != null && c.candidate != null) {
        rt.send({
          'type': 'call_ice',
          'callId': id,
          'candidate': c.toMap(),
        });
      }
    };

    pc.onTrack = (e) {
      if (e.streams.isNotEmpty) {
        remoteR.srcObject = e.streams[0];
      }
      notifyListeners();
    };

    void onConnected() {
      final c = current;
      if (c == null || _pc != pc) return;
      _stopSounds();
      _timeoutTimer?.cancel();
      _dropTimer?.cancel();
      _restartTimer?.cancel();
      _restarting = false;
      if (c.reconnecting) {
        c.reconnecting = false;
        notifyListeners();
      }
      if (c.state != CallState.connected) {
        c.state = CallState.connected;
        c.connectedAt = DateTime.now();
        if (c.native) NativeCalls.connected(c.id);
        if (!kIsWeb) Helper.setSpeakerphoneOn(c.speaker);
        _syncDevice();
        notifyListeners();
      }
    }

    pc.onConnectionState = (s) {
      if (_pc != pc) return;
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        onConnected();
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _dropped(failed: true);
      }
    };

    pc.onIceConnectionState = (s) {
      if (_pc != pc) return;
      if (s == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          s == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        onConnected();
      } else if (s == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        _dropped(failed: false);
      } else if (s == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _dropped(failed: true);
      }
    };

    notifyListeners();
  }

  /// The media path broke. Before the call ever connected that is the end of it; mid-call it shows
  /// "Reconnecting…": "disconnected" often heals by itself within seconds, otherwise (or on "failed") the
  /// caller restarts ICE with fresh candidates, and the call ends after [_reconnectFor].
  void _dropped({required bool failed}) {
    final c = current;
    if (c == null || c.state == CallState.ended) return;
    if (c.state != CallState.connected) {
      if (failed) hangUp(note: 'Could not connect');
      return;
    }
    if (!c.reconnecting) {
      c.reconnecting = true;
      notifyListeners();
      _dropTimer?.cancel();
      _dropTimer = Timer(_reconnectFor, () {
        if (current == c && c.reconnecting) hangUp(note: 'Connection lost');
      });
    }
    _restartTimer?.cancel();
    if (failed) {
      _restartIce();
    } else {
      _restartTimer = Timer(const Duration(seconds: 4), _restartIce);
    }
  }

  /// Only the caller offers again (both doing it at once would collide); the callee answers in _onEvent.
  Future<void> _restartIce() async {
    final c = current, pc = _pc;
    if (c == null || pc == null || c.incoming || !c.reconnecting || _restarting) return;
    if (!rt.connected) return; // retried from onReconnect
    _restarting = true;
    try {
      final offer = await pc.createOffer({'iceRestart': true});
      if (_pc != pc) return;
      await pc.setLocalDescription(offer);
      rt.send({'type': 'call_restart', 'callId': c.id, 'sdp': {'sdp': offer.sdp, 'type': offer.type}});
    } catch (_) {
      // tried again by the next state change or reconnect
    } finally {
      // let another attempt go out if this one gets no answer (e.g. the other phone was still offline)
      Timer(const Duration(seconds: 6), () {
        if (_pc == pc) _restarting = false;
        if (current == c && c.reconnecting && _pc == pc) _restartIce();
      });
    }
  }

  Future<void> _flushIce() async {
    for (final c in _pendingIce) {
      await _pc?.addCandidate(c);
    }
    _pendingIce.clear();
  }

  // ---------- Signalling Events ----------
  Future<void> _onEvent(Json e) async {
    switch (e['type']) {
      case 'call_offer':
        if (current != null) {
          if (current!.id == e['callId']) return; // the same offer, re-sent after a reconnect
          rt.send({'type': 'call_reject', 'callId': e['callId']}); // busy
          return;
        }
        current = ActiveCall(
          id: e['callId'],
          user: Map<String, dynamic>.from(e['caller'] ?? {
            'uid': e['from'],
            'name': 'Someone',
          }),
          video: e['video'] == true,
          incoming: true,
          state: CallState.ringing,
          offerSdp: Map<String, dynamic>.from(e['sdp']),
        );
        _pendingIce.clear();
        // Acknowledge to caller that our device received the call and is ringing
        rt.send({'type': 'call_ringing', 'callId': e['callId']});
        final c = current!;
        // answered on the lock screen while the app was starting? (the event may not have reached Dart yet)
        final answered = _nativeAccepted.remove(c.id) || (await NativeCalls.active()).any((x) => x.id == c.id && x.isAccepted);
        if (current != c) return;
        if (answered) {
          // answered on the lock screen / CallKit while the app was starting
          c.native = true;
          notifyListeners();
          openScreen();
          accept();
        } else if (_foreground && defaultTargetPlatform != TargetPlatform.iOS) {
          _playIncomingRingtone();
          notifyListeners();
          openScreen();
        } else {
          c.native = true;
          notifyListeners();
          NativeCalls.showIncoming(
            id: c.id,
            name: _displayName(c.user),
            video: c.video,
            from: '${e['from']}',
            handle: '${c.user['handle'] ?? ''}',
            photo: c.user['photoURL'] as String?,
          );
        }
        break;

      case 'call_ringing':
        if (current?.id != e['callId']) return;
        if (current?.state == CallState.calling) {
          current!.state = CallState.ringing;
          _playRingback();
          notifyListeners();
        }
        break;

      case 'call_answer':
        if (current?.id != e['callId'] || _pc == null) return;
        _stopSounds();
        _timeoutTimer?.cancel();
        await _pc!.setRemoteDescription(
            RTCSessionDescription(e['sdp']['sdp'], e['sdp']['type']));
        _remoteSet = true;
        current!.state = current!.state == CallState.connected
            ? CallState.connected
            : CallState.connecting;
        notifyListeners();
        await _flushIce();
        break;

      // the caller restarted ICE after a network change: answer with our fresh candidates
      case 'call_restart':
        if (current?.id != e['callId'] || _pc == null || e['sdp'] == null) return;
        final pc = _pc!;
        try {
          await pc.setRemoteDescription(RTCSessionDescription(e['sdp']['sdp'], e['sdp']['type']));
          final answer = await pc.createAnswer();
          await pc.setLocalDescription(answer);
          rt.send({'type': 'call_restart_answer', 'callId': e['callId'], 'sdp': {'sdp': answer.sdp, 'type': answer.type}});
        } catch (_) {}
        break;

      case 'call_restart_answer':
        if (current?.id != e['callId'] || _pc == null || e['sdp'] == null) return;
        try {
          await _pc!.setRemoteDescription(RTCSessionDescription(e['sdp']['sdp'], e['sdp']['type']));
        } catch (_) {}
        break;

      case 'call_ice':
        if (current?.id != e['callId']) return;
        final c = e['candidate'] as Map;
        final cand = RTCIceCandidate(
          c['candidate'],
          c['sdpMid'],
          c['sdpMLineIndex'],
        );
        if (_pc != null && _remoteSet) {
          await _pc!.addCandidate(cand);
        } else {
          _pendingIce.add(cand);
        }
        break;

      case 'call_end':
        if (current?.id != e['callId']) return;
        _stopSounds();
        _timeoutTimer?.cancel();
        _finish(const {
              'declined': 'Declined',
              'no_answer': 'No answer',
              'missed': 'Missed call',
              'answered_elsewhere': 'Answered on another device',
            }[e['reason']] ??
            'Call ended');
        break;

      case 'call_peer_away':
      case 'call_peer_back':
        if (current?.id != e['callId']) return;
        current!.peerAway = e['type'] == 'call_peer_away';
        notifyListeners();
        break;

      case 'call_unavailable':
        if (current?.id != e['callId']) return;
        _stopSounds();
        _timeoutTimer?.cancel();
        _finish('Not reachable right now');
        break;
    }
  }

  void _finish(String note) {
    final c = current;
    if (c == null) return;
    _stopSounds();
    _timeoutTimer?.cancel();
    _dropTimer?.cancel();
    _restartTimer?.cancel();
    _restarting = false;
    c.state = CallState.ended;
    c.reconnecting = false;
    c.note = note;
    notifyListeners();
    NativeCalls.end(c.id);
    _syncDevice();
    _teardown();
    Timer(const Duration(milliseconds: 1400), () {
      if (current == c) {
        current = null;
        notifyListeners();
      }
    });
  }

  void _teardown() {
    for (final t in _local?.getTracks() ?? <MediaStreamTrack>[]) {
      t.stop();
    }
    _local?.dispose();
    _local = null;
    _pc?.close();
    _pc = null;
    _remoteSet = false;
    _pendingIce.clear();
    if (_renderersReady) {
      localR.srcObject = null;
      remoteR.srcObject = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopSounds();
    _timeoutTimer?.cancel();
    _dropTimer?.cancel();
    _restartTimer?.cancel();
    _ringbackPlayer.dispose();
    _teardown();
    if (_renderersReady) {
      localR.dispose();
      remoteR.dispose();
    }
    super.dispose();
  }
}

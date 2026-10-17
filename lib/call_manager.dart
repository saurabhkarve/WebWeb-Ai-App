import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'api.dart';
import 'native_calls.dart';
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
  /// ringing through CallKit / the Android call screen (not the in-app screen)
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
/// ICE servers (STUN + our TURN relay) come from the API. In the foreground a call rings on the in-app
/// screen; in the background or when the app was closed it rings through the phone's own call UI
/// ([NativeCalls]: CallKit / Android full-screen), and answering there opens the call here.
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
  }

  bool _foreground = true;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _foreground = state == AppLifecycleState.resumed;

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

  Future<bool> _permissions(bool video) async => true;

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
    try {
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
    if (!rt.connected) throw 'Not connected to the server yet';
    if (!await _permissions(video)) {
      throw 'Microphone${video ? ' / camera' : ''} permission is needed for calls';
    }
    final id = NativeCalls.newCallId();
    current = ActiveCall(
      id: id,
      user: user,
      video: video,
      incoming: false,
      state: CallState.calling,
    );
    notifyListeners();
    openScreen();

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
      _finish('Could not start the call');
    }
  }

  // ---------- Incoming Call ----------
  Future<void> accept() async {
    final c = current;
    if (c == null || !c.incoming || c.offerSdp == null) return;
    _stopSounds();
    if (!await _permissions(c.video)) {
      reject();
      return;
    }
    c.state = CallState.connecting;
    notifyListeners();
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
      hangUp(note: 'Connection failed');
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
      if (c == null) return;
      _stopSounds();
      _timeoutTimer?.cancel();
      if (c.state != CallState.connected) {
        c.state = CallState.connected;
        c.connectedAt = DateTime.now();
        if (c.native) NativeCalls.connected(c.id);
        if (!kIsWeb) Helper.setSpeakerphoneOn(c.speaker);
        notifyListeners();
      }
    }

    pc.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        onConnected();
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        hangUp(note: 'Connection dropped');
      }
    };

    pc.onIceConnectionState = (s) {
      if (s == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          s == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        onConnected();
      } else if (s == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        hangUp(note: 'Connection failed');
      }
    };

    notifyListeners();
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
        } else if (_foreground) {
          _playIncomingRingtone();
          notifyListeners();
          openScreen();
        } else {
          c.native = true;
          notifyListeners();
          NativeCalls.showIncoming(
            id: c.id,
            name: '${c.user['userType'] == 'entrepreneur' && '${c.user['company'] ?? ''}'.isNotEmpty ? c.user['company'] : c.user['name'] ?? 'Someone'}',
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
    c.state = CallState.ended;
    c.note = note;
    notifyListeners();
    NativeCalls.end(c.id);
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
    _ringbackPlayer.dispose();
    _teardown();
    if (_renderersReady) {
      localR.dispose();
      remoteR.dispose();
    }
    super.dispose();
  }
}

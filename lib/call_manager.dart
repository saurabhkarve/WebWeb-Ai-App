import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'api.dart';
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

/// WebRTC voice/video calls. Signalling goes through [RealtimeService]
/// (the backend relays offer/ringing/answer/ICE).
/// Reference implementation based on AirMsg with ringtones, ringback,
/// call states, camera switching, audio routing, and graceful cleanup.
class CallManager extends ChangeNotifier {
  final RealtimeService rt;
  final GlobalKey<NavigatorState> nav;

  CallManager(this.rt, this.nav) {
    rt.events.listen(_onEvent);
  }

  static const _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

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
    final n = rate * seconds;
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
    final id = '${DateTime.now().microsecondsSinceEpoch}-${user['uid']}';
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
    rt.send({'type': 'call_reject', 'callId': c.id});
    _finish('Declined');
  }

  void hangUp({String? note}) {
    final c = current;
    if (c == null) return;
    _stopSounds();
    _timeoutTimer?.cancel();
    rt.send({'type': 'call_end', 'callId': c.id});
    _finish(note ?? 'Call ended');
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
    final pc = await createPeerConnection(_iceServers);
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
        _playIncomingRingtone();
        notifyListeners();
        openScreen();
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

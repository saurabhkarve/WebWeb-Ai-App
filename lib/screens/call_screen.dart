import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../call_manager.dart';
import '../widgets.dart';

/// Full-screen call UI: incoming (accept / decline), calling, ringing,
/// and in-call controls with PiP video swapping & minimize support.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  Timer? _tick;
  bool _popped = false;
  bool _swapped = false; // tapping thumbnail swaps remote and local video

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CallManager>().setScreenVisible(true);
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _status(ActiveCall c) {
    switch (c.state) {
      case CallState.calling:
        return 'Calling…';
      case CallState.ringing:
        return c.incoming
            ? 'Incoming ${c.video ? 'video' : 'voice'} call'
            : 'Ringing…';
      case CallState.connecting:
        return 'Connecting…';
      case CallState.ended:
        return c.note ?? 'Call ended';
      case CallState.connected:
        final d = DateTime.now().difference(c.connectedAt ?? DateTime.now());
        String two(int n) => n.toString().padLeft(2, '0');
        if (d.inHours > 0) {
          return '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
        }
        return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
    }
  }

  void _onMinimize() {
    context.read<CallManager>().setScreenVisible(false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cm = context.watch<CallManager>();
    final c = cm.current;

    if (c == null) {
      if (!_popped) {
        _popped = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            cm.setScreenVisible(false);
            Navigator.of(context).maybePop();
          }
        });
      }
      return const Scaffold(backgroundColor: Colors.black);
    }

    final hasRemoteStream = cm.remoteR.srcObject != null;
    final hasLocalStream = cm.localR.srcObject != null;
    final isConnected = c.state == CallState.connected;
    final showVideo = c.video && isConnected;

    // Which video is large and which is in thumbnail
    final bigRenderer = _swapped ? cm.localR : cm.remoteR;
    final thumbRenderer = _swapped ? cm.remoteR : cm.localR;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) cm.setScreenVisible(false);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F141A),
        body: Stack(
          children: [
            // Full-screen video (when connected)
            if (showVideo && (hasRemoteStream || hasLocalStream))
              Positioned.fill(
                child: RTCVideoView(
                  bigRenderer,
                  mirror: _swapped,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),

            // Shading overlay on top of video
            if (showVideo)
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black54,
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black87,
                      ],
                      stops: [0.0, 0.25, 0.7, 1.0],
                    ),
                  ),
                ),
              ),

            // Main Content Layer
            SafeArea(
              child: Column(
                children: [
                  // Top bar with minimize button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.keyboard_arrow_down,
                              color: Colors.white, size: 32),
                          onPressed: _onMinimize,
                          tooltip: 'Minimize call',
                        ),
                        const Spacer(),
                        if (c.video)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.videocam, size: 14, color: Colors.white),
                                SizedBox(width: 4),
                                Text('HD',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                  // User Info & Status
                  if (!showVideo) ...[
                    const SizedBox(height: 40),
                    Avatar(name: '${c.user['name']}', size: 110, ring: true),
                    const SizedBox(height: 20),
                  ],

                  Text(
                    '${c.user['name']}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _status(c),
                    style: TextStyle(
                      color: c.state == CallState.ended
                          ? Colors.redAccent
                          : (c.state == CallState.connected
                              ? Colors.greenAccent
                              : Colors.white70),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const Spacer(),

                  // Bottom Controls
                  _controls(cm, c),
                  const SizedBox(height: 36),
                ],
              ),
            ),

            // Picture-in-picture Thumbnail Video
            if (c.video &&
                !c.camOff &&
                hasLocalStream &&
                c.state != CallState.ended)
              Positioned(
                right: 16,
                top: 76,
                child: GestureDetector(
                  onTap: () {
                    if (showVideo) setState(() => _swapped = !_swapped);
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 105,
                      height: 145,
                      color: Colors.black54,
                      child: Stack(
                        children: [
                          RTCVideoView(
                            showVideo ? thumbRenderer : cm.localR,
                            mirror: !_swapped,
                            objectFit:
                                RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                          ),
                          if (showVideo)
                            Positioned(
                              bottom: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.black45,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.sync,
                                    size: 14, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _round(IconData icon, Color bg, VoidCallback? onTap,
      {String? label, Color fg = Colors.white, double size = 62}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkResponse(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, color: fg, size: size * .45),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _controls(CallManager cm, ActiveCall c) {
    if (c.state == CallState.ringing && c.incoming) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _round(
            Icons.call_end,
            Colors.redAccent,
            cm.reject,
            label: 'Decline',
            size: 72,
          ),
          _round(
            c.video ? Icons.videocam : Icons.call,
            const Color(0xFF2AAE6B),
            cm.accept,
            label: 'Accept',
            size: 72,
          ),
        ],
      );
    }

    if (c.state == CallState.ended) return const SizedBox(height: 90);

    const off = Colors.white24;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _round(
              c.muted ? Icons.mic_off : Icons.mic,
              c.muted ? Colors.white : off,
              cm.toggleMute,
              fg: c.muted ? Colors.black : Colors.white,
              label: c.muted ? 'Unmute' : 'Mute',
            ),
            _round(
              c.speaker ? Icons.volume_up : Icons.volume_down,
              c.speaker ? Colors.white : off,
              cm.toggleSpeaker,
              fg: c.speaker ? Colors.black : Colors.white,
              label: 'Speaker',
            ),
            if (c.video)
              _round(
                c.camOff ? Icons.videocam_off : Icons.videocam,
                c.camOff ? Colors.white : off,
                cm.toggleCamera,
                fg: c.camOff ? Colors.black : Colors.white,
                label: 'Camera',
              ),
            if (c.video)
              _round(
                Icons.cameraswitch,
                off,
                cm.switchCamera,
                label: 'Flip',
              ),
          ],
        ),
        const SizedBox(height: 28),
        _round(
          Icons.call_end,
          Colors.redAccent,
          () => cm.hangUp(),
          label: 'End call',
          size: 72,
        ),
      ],
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../call_manager.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'talk.dart' show openChat;

const _bg = Color(0xFF1E1E1E);
const _red = Color(0xFFDC2626);
const _emerald = Color(0xFF10B981);

/// Full-screen call, styled as the web call-screen: ink background, the avatar with a pulsing gold
/// ring while it rings, name, a status line, and round 64 px controls. The app adds video, speaker,
/// camera flip and minimise. When the call ends it stays up with "Send a message" and "Close".
class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with SingleTickerProviderStateMixin {
  Timer? _tick;
  bool _swapped = false; // tapping the thumbnail swaps remote and local video
  ActiveCall? _last; // kept after the manager clears the call, for the ended view
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

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
    _pulse.dispose();
    super.dispose();
  }

  String _status(ActiveCall c) {
    final kind = c.video ? 'video' : 'voice';
    switch (c.state) {
      case CallState.calling:
        return t('Starting call…');
      case CallState.ringing:
        return c.incoming ? t('Incoming $kind call') : t('Ringing…');
      case CallState.connecting:
        return t('Connecting…');
      case CallState.ended:
        return t(c.note ?? 'Call ended');
      case CallState.connected:
        final d = DateTime.now().difference(c.connectedAt ?? DateTime.now());
        String two(int n) => n.toString().padLeft(2, '0');
        return d.inHours > 0 ? '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}' : '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
    }
  }

  void _close() {
    context.read<CallManager>().setScreenVisible(false);
    Navigator.of(context).maybePop();
  }

  void _minimise() {
    context.read<CallManager>().setScreenVisible(false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cm = context.watch<CallManager>();
    final live = cm.current;
    if (live != null) _last = live;
    final c = live ?? _last;
    if (c == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _close();
      });
      return const Scaffold(backgroundColor: _bg);
    }
    final ended = live == null || c.state == CallState.ended;
    final ringing = !ended && (c.state == CallState.ringing || c.state == CallState.calling);
    final connected = !ended && c.state == CallState.connected;
    final showVideo = c.video && connected && !ended;
    final hasRemote = cm.remoteR.srcObject != null;
    final hasLocal = cm.localR.srcObject != null;
    final name = '${c.user['name'] ?? ''}';
    final photo = c.user['photoURL'] as String?;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) cm.setScreenVisible(false);
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(children: [
          if (showVideo && (hasRemote || hasLocal))
            Positioned.fill(
              child: RTCVideoView(_swapped ? cm.localR : cm.remoteR, mirror: _swapped, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
            ),
          if (showVideo)
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x8A000000), Colors.transparent, Colors.transparent, Color(0xDD000000)],
                    stops: [0, .25, .7, 1],
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Column(children: [
              SizedBox(
                height: 56,
                child: Row(children: [
                  if (!ended)
                    _topButton(WI.chevronDown, t('Minimise call'), _minimise)
                  else
                    const SizedBox(width: 56),
                  const Spacer(),
                  if (ended) _topButton(WI.close, t('Close'), _close),
                ]),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (!showVideo) ...[
                        _ringAvatar(name, photo, ringing),
                        const SizedBox(height: 16),
                      ],
                      Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
                      const SizedBox(height: 16),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        if (!ended) ...[
                          WIcon(c.video ? WI.video : WI.phone, size: 16, color: Colors.white.withValues(alpha: .7)),
                          const SizedBox(width: 8),
                        ],
                        Flexible(child: Text(_status(c), textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: .7)))),
                      ]),
                      const SizedBox(height: 24),
                      if (ended) _endedActions(c) else _controls(cm, c),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
          // picture-in-picture: own camera, tap to swap
          if (c.video && !c.camOff && hasLocal && !ended)
            Positioned(
              right: 16,
              top: MediaQuery.of(context).padding.top + 64,
              child: GestureDetector(
                onTap: showVideo ? () => setState(() => _swapped = !_swapped) : null,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 105,
                    height: 145,
                    color: Colors.black54,
                    child: Stack(children: [
                      RTCVideoView(showVideo ? (_swapped ? cm.remoteR : cm.localR) : cm.localR, mirror: !_swapped, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                      if (showVideo)
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                            child: const WIcon(WI.refresh, size: 14, color: Colors.white),
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _topButton(WI icon, String label, VoidCallback onTap) => Semantics(
        button: true,
        label: label,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: SizedBox(width: 56, height: 56, child: Center(child: WIcon(icon, size: 28, color: Colors.white))),
        ),
      );

  /// animate-pulse ring-4 ring-[#ffc700]/50 while it rings
  Widget _ringAvatar(String name, String? photo, bool ringing) => AnimatedBuilder(
        animation: _pulse,
        builder: (_, child) {
          final o = ringing ? (.5 + .5 * math.cos(_pulse.value * 2 * math.pi)) : 0.0;
          return Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: ringing ? [BoxShadow(color: kGold.withValues(alpha: .5 * o + .15), spreadRadius: 4)] : null,
            ),
            child: Opacity(opacity: ringing ? .75 + .25 * o : 1, child: child),
          );
        },
        child: Avatar(name: name, photoUrl: photo, size: 112),
      );

  Widget _round(WI icon, String label, Color bg, VoidCallback onTap, {Color fg = Colors.white, double turns = 0}) => GestureDetector(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Transform.rotate(angle: turns * 2 * math.pi, child: WIcon(icon, size: 28, strokeWidth: 1.9, color: fg)),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
        ]),
      );

  Widget _controls(CallManager cm, ActiveCall c) {
    final white15 = Colors.white.withValues(alpha: .15);
    if (c.state == CallState.ringing && c.incoming) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        _round(WI.phone, t('Decline'), _red, cm.reject, turns: 135 / 360),
        const SizedBox(width: 40),
        _round(c.video ? WI.video : WI.phone, t('Answer'), _emerald, cm.accept),
      ]);
    }
    final waiting = c.state != CallState.connected;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (!waiting)
        Wrap(alignment: WrapAlignment.center, spacing: 24, runSpacing: 16, children: [
          _round(c.muted ? WI.micOff : WI.mic, t(c.muted ? 'Unmute' : 'Mute'), c.muted ? Colors.white : white15, cm.toggleMute, fg: c.muted ? kInk : Colors.white),
          _round(c.speaker ? WI.speaker : WI.speakerLow, t('Speaker'), c.speaker ? Colors.white : white15, cm.toggleSpeaker, fg: c.speaker ? kInk : Colors.white),
          if (c.video) _round(c.camOff ? WI.videoOff : WI.video, t('Camera'), c.camOff ? Colors.white : white15, cm.toggleCamera, fg: c.camOff ? kInk : Colors.white),
          if (c.video) _round(WI.flipCamera, t('Flip'), white15, cm.switchCamera),
        ]),
      if (!waiting) const SizedBox(height: 24),
      _round(WI.phone, t(waiting ? 'Cancel' : 'End'), _red, () => cm.hangUp(), turns: 135 / 360),
    ]);
  }

  Widget _endedActions(ActiveCall c) {
    final uid = '${c.user['uid'] ?? ''}';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (uid.isNotEmpty)
          GoldButton(
            label: t('Send a message'),
            height: 40,
            onPressed: () {
              final peer = Peer.fromJson(c.user);
              final nav = Navigator.of(context);
              context.read<CallManager>().setScreenVisible(false);
              nav.pop();
              openChat(nav.context, peer);
            },
          ),
        const SizedBox(height: 8),
        Material(
          color: Colors.transparent,
          child: Ink(
            height: 40,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _close,
              child: Center(child: Text(t('Close'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white))),
            ),
          ),
        ),
      ]),
    );
  }
}

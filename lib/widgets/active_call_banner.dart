import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../call_manager.dart';

/// WhatsApp / AirMsg style top active call banner.
/// Shown when a call is running in the background and the call screen is minimized.
class ActiveCallBanner extends StatefulWidget {
  const ActiveCallBanner({super.key});

  @override
  State<ActiveCallBanner> createState() => _ActiveCallBannerState();
}

class _ActiveCallBannerState extends State<ActiveCallBanner> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _timeString(DateTime? connectedAt) {
    if (connectedAt == null) return 'Connecting…';
    final diff = DateTime.now().difference(connectedAt);
    String two(int n) => n.toString().padLeft(2, '0');
    if (diff.inHours > 0) {
      return '${diff.inHours}:${two(diff.inMinutes % 60)}:${two(diff.inSeconds % 60)}';
    }
    return '${two(diff.inMinutes)}:${two(diff.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final cm = context.watch<CallManager>();
    final c = cm.current;

    // Show banner only if call is active and call screen is currently not open
    if (c == null || c.state == CallState.ended || cm.isScreenOpen) {
      return const SizedBox.shrink();
    }

    final isConnecting = c.state != CallState.connected;
    final timeOrStatus = isConnecting
        ? (c.state == CallState.ringing ? 'Ringing…' : 'Connecting…')
        : _timeString(c.connectedAt);

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        bottom: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2832),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: isConnecting ? Colors.orangeAccent : const Color(0xFF2AAE6B),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              // Tap area to re-open call screen
              Expanded(
                child: InkWell(
                  onTap: cm.openScreen,
                  borderRadius: BorderRadius.circular(12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: isConnecting
                              ? Colors.orangeAccent.withValues(alpha: .2)
                              : const Color(0xFF2AAE6B).withValues(alpha: .2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          c.video ? Icons.videocam : Icons.call,
                          size: 18,
                          color: isConnecting
                              ? Colors.orangeAccent
                              : const Color(0xFF2AAE6B),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${c.user['name']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              timeOrStatus,
                              style: TextStyle(
                                color: isConnecting
                                    ? Colors.orangeAccent
                                    : Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Text(
                        'Tap to return',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),

              // Quick Controls
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  c.muted ? Icons.mic_off : Icons.mic,
                  color: c.muted ? Colors.redAccent : Colors.white70,
                  size: 20,
                ),
                onPressed: cm.toggleMute,
                tooltip: c.muted ? 'Unmute' : 'Mute',
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.call_end,
                  color: Colors.redAccent,
                  size: 20,
                ),
                onPressed: () => cm.hangUp(),
                tooltip: 'End Call',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

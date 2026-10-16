import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../call_manager.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets.dart';

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
    if (connectedAt == null) return t('Connecting…');
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
        ? t(c.state == CallState.ringing ? 'Ringing…' : 'Connecting…')
        : _timeString(c.connectedAt);

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        bottom: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: kInk,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: isConnecting ? kGold : const Color(0xFF10B981),
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
                              ? kGold.withValues(alpha: .2)
                              : const Color(0xFF10B981).withValues(alpha: .2),
                          shape: BoxShape.circle,
                        ),
                        child: WIcon(
                          c.video ? WI.video : WI.phone,
                          size: 18,
                          color: isConnecting ? kGold : const Color(0xFF10B981),
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
                                color: isConnecting ? kGold : Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        t('Tap to return'),
                        style: const TextStyle(
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
                icon: WIcon(
                  c.muted ? WI.micOff : WI.mic,
                  color: c.muted ? const Color(0xFFDC2626) : Colors.white70,
                  size: 20,
                ),
                onPressed: cm.toggleMute,
                tooltip: t(c.muted ? 'Unmute' : 'Mute'),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Transform.rotate(
                  angle: 2.356,
                  child: const WIcon(WI.phone, color: Color(0xFFDC2626), size: 20),
                ),
                onPressed: () => cm.hangUp(),
                tooltip: t('End'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

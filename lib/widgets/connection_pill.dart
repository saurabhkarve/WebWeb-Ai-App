import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n.dart';
import '../realtime.dart';
import '../theme.dart';

/// WhatsApp-style status while the app cannot reach the server: "Waiting for network…" with no network at all,
/// "Connecting…" while the link is being re-made. Shown only after a moment, so a quick reconnect never flashes.
/// Everything keeps working from the phone's copy meanwhile; messages wait in the outbox.
String? connectionStatus(RealtimeService rt) {
  if (!rt.networkUp) return t('Waiting for network…');
  if (!rt.connected) return t('Connecting…');
  return null;
}

class ConnectionPill extends StatefulWidget {
  const ConnectionPill({super.key});
  @override
  State<ConnectionPill> createState() => _ConnectionPillState();
}

class _ConnectionPillState extends State<ConnectionPill> {
  bool _shown = false;
  String? _pendingText;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final text = connectionStatus(context.watch<RealtimeService>());
    if (text == null) {
      _shown = false;
      _pendingText = null;
    } else if (!_shown && _pendingText == null) {
      _pendingText = text;
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (mounted && _pendingText != null) setState(() => _shown = true);
      });
    }
    final visible = text != null && _shown;
    return IgnorePointer(
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, -0.4),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: p.ink,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: 14, offset: const Offset(0, 4))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.8, color: p.onInk)),
                const SizedBox(width: 8),
                Text(text ?? '', style: TextStyle(color: p.onInk, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

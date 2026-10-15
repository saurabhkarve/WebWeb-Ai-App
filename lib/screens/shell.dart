import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../realtime.dart';
import '../theme.dart';
import '../widgets/active_call_banner.dart';
import 'ask.dart';
import 'connect.dart';
import 'find.dart';
import 'profile.dart';
import 'talk.dart';

/// The 5 tabs from the web side bar: Connect, Find, Talk, Ask, Profile.
/// The tab bar is a floating "island" (same idea as the AirMsg app).
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _i = 0;
  int _feedTick = 0;
  int _unread = 0;
  StreamSubscription? _sub;

  static const _items = [
    (Icons.join_inner, 'Connect'),
    (Icons.search, 'Find'),
    (Icons.forum_outlined, 'Talk'),
    (Icons.back_hand_outlined, 'Ask'),
    (Icons.person_outline, 'Profile'),
  ];

  @override
  void initState() {
    super.initState();
    _loadUnread();
    _sub = context.read<RealtimeService>().events.listen((e) {
      if (e['type'] == 'msg' || e['type'] == 'read') _loadUnread();
    });
  }

  Future<void> _loadUnread() async {
    try {
      final d = await context.read<AuthProvider>().api.get('/chats') as List;
      final n = d.where((c) => c['unread'] == true).length;
      if (mounted && n != _unread) setState(() => _unread = n);
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      body: Column(
        children: [
          const ActiveCallBanner(),
          Expanded(
            child: Stack(children: [
              Positioned.fill(
                child: IndexedStack(index: _i, children: [
                  ConnectScreen(refreshTick: _feedTick, onGoAsk: () => setState(() => _i = 3)),
                  const FindScreen(),
                  if (_i == 2) const TalkScreen() else const SizedBox.shrink(), // reload conversations each time it opens
                  AskScreen(onPosted: () => setState(() {
                        _feedTick++;
                        _i = 0;
                      })),
                  const ProfileScreen(),
                ]),
              ),
            ]),
          ),
          // floating island
          Padding(
            padding: EdgeInsets.only(top: 4, bottom: bottomInset + 8),
            child: Center(child: _island(p)),
          ),
        ],
      ),
    );
  }

  Widget _island(Pal p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: (p.dark ? p.card : p.chip).withValues(alpha: .92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: p.border.withValues(alpha: .7)),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 22, offset: Offset(0, 8))],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var k = 0; k < _items.length; k++)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _i = k),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Stack(clipBehavior: Clip.none, children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: _i == k ? p.selected : Colors.transparent),
                    child: Icon(_items[k].$1, size: 20, color: _i == k ? p.onSelected : p.text),
                  ),
                  if (k == 2 && _unread > 0)
                    Positioned(
                      right: -6,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: kGold, borderRadius: BorderRadius.circular(9), border: Border.all(color: p.card, width: 1.5)),
                        child: Text(_unread > 99 ? '99+' : '$_unread', style: const TextStyle(color: Color(0xFF1E1E1E), fontSize: 10.5, fontWeight: FontWeight.w700)),
                      ),
                    ),
                ]),
                const SizedBox(height: 2),
                Text(_items[k].$2, style: TextStyle(fontSize: 10.5, fontWeight: _i == k ? FontWeight.w700 : FontWeight.w500, color: _i == k ? p.text : p.muted)),
              ]),
            ),
          ),
      ]),
    );
  }
}

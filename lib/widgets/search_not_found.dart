import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../contact_sync.dart';
import '../i18n.dart';
import '../screens/service_contacts_sheet.dart';
import '../theme.dart';
import '../widgets.dart';

/// When a search finds no one: not a dead end but a few next steps. A tip that changes every few seconds (simpler words, a
/// town nearby, the members who refer, and sharing the contacts in the phone book so neighbours can find them) and the
/// buttons to act on it (web SearchNotFound).
class SearchNotFound extends StatefulWidget {
  final String query;
  /// "Ask members near you": opens the ask
  final VoidCallback onAsk;
  const SearchNotFound({super.key, required this.query, required this.onAsk});
  @override
  State<SearchNotFound> createState() => _SearchNotFoundState();
}

class _SearchNotFoundState extends State<SearchNotFound> with SingleTickerProviderStateMixin {
  late final _wobble = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  Timer? _tick;
  int _i = 0;
  // sharing service contacts from this phone: offered while it is off
  bool _canShare = false;

  List<String> get _tips => [
        t('Try a shorter, simpler word, like the trade only.'),
        t('Try a town nearby: change the location above.'),
        t('Members near you may know one. Post an ask and they refer a trusted contact.'),
        if (ContactSync.supported) t('Know a good one near you? Sharing a contact from the WEBWEB app helps your neighbours find it.'),
      ];

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 3600), (_) {
      if (mounted) setState(() => _i = (_i + 1) % _tips.length);
    });
    if (ContactSync.supported) {
      ContactSync.isOn(context.read<AuthProvider>().api).then((on) {
        if (mounted) setState(() => _canShare = !on);
      }, onError: (_) {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _wobble.stop();
    } else if (!_wobble.isAnimating) {
      _wobble.repeat();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _wobble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final tips = _tips;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(children: [
        AnimatedBuilder(
          animation: _wobble,
          builder: (_, child) {
            final v = _wobble.value;
            // a small shake of the magnifier, then still
            final a = v < .4 ? (v < .2 ? -.25 * (v / .2) : -.25 + .45 * ((v - .2) / .2)) : .2 * (1 - ((v - .4) / .6));
            return Transform.rotate(angle: a, child: child);
          },
          child: Container(width: 54, height: 54, decoration: BoxDecoration(shape: BoxShape.circle, color: p.chip), child: Icon(Icons.search_rounded, size: 26, color: p.muted)),
        ),
        const SizedBox(height: 12),
        Text(t('We could not find “{q}” yet', {'q': widget.query}), textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (w, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, .25), end: Offset.zero).animate(a), child: w)),
            child: Text(tips[_i % tips.length], key: ValueKey(_i % tips.length), textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, height: 1.35, color: p.muted)),
          ),
        ),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var k = 0; k < tips.length; k++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: k == _i % tips.length ? 20 : 6,
              height: 4,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: k == _i % tips.length ? kGold : p.text.withValues(alpha: .15)),
            ),
        ]),
        const SizedBox(height: 14),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          GoldButton(label: t('Ask members near you'), wi: WI.ask, height: 40, onPressed: widget.onAsk),
          if (_canShare)
            GoldButton(
              label: t('Share contacts from the app'),
              wi: WI.share,
              outlined: true,
              height: 40,
              onPressed: () async {
                final done = await showServiceContactsSheet(context);
                if (done == true && mounted) setState(() => _canShare = false);
              },
            ),
        ]),
      ]),
    );
  }
}

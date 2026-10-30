import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets.dart';

/// The opening screen, laid out like the big apps': the WEBWEB lockup as in the header, a little above the middle, and "from SkyQ" at the bottom edge. Sizes follow the screen (the short side), and the two groups are
/// placed by alignment, not by fixed offsets, so it fits a small phone, a tall one, a tablet or a landscape window
/// without overflowing.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final mq = MediaQuery.of(context);
    final short = math.min(mq.size.width, mq.size.height);
    // the header's proportions (type 28, mark 36), scaled up
    final word = (short * .09).clamp(30.0, 56.0);
    final small = (short * .034).clamp(11.0, 16.0);
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: Stack(children: [
          // a touch above the centre, as optical centre: the lockup of the header (round mark, WEBWEB AI over
          // SMART PHONEBOOK), only larger; it shrinks rather than overflow a narrow window
          Align(
            alignment: const Alignment(0, -.1),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: FittedBox(fit: BoxFit.scaleDown, child: LogoInline(size: word, markSize: word * 1.3, tagline: true)),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: math.max(20, mq.size.height * .035)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(t('from'), style: TextStyle(fontSize: small, color: p.muted, height: 1.2)),
                SizedBox(height: small * .25),
                Text('SkyQ', style: TextStyle(fontSize: small * 1.35, fontWeight: FontWeight.w700, letterSpacing: small * .12, color: p.text)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

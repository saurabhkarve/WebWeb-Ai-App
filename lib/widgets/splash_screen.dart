import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../i18n.dart';
import '../theme.dart';
import 'logo_loader.dart';

/// The opening screen, laid out like the big apps': the WEBWEB mark with "WEBWEB AI" under it, a little above the
/// middle, and "from SKYQ" at the bottom edge. Sizes follow the screen (the short side), and the two groups are
/// placed by alignment, not by fixed offsets, so it fits a small phone, a tall one, a tablet or a landscape window
/// without overflowing.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final mq = MediaQuery.of(context);
    final short = math.min(mq.size.width, mq.size.height);
    final mark = (short * .26).clamp(72.0, 150.0);
    final title = mark * .26;
    final small = (short * .034).clamp(11.0, 16.0);
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: Stack(children: [
          // a touch above the centre, as optical centre
          Align(
            alignment: const Alignment(0, -.1),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DecoratedBox(
                decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFF9B9542).withValues(alpha: .35), blurRadius: mark * .14, offset: Offset(0, mark * .04))]),
                child: AnimatedLogo(size: mark),
              ),
              SizedBox(height: mark * .22),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: 'WEBWEB ', style: TextStyle(color: p.text)),
                  const TextSpan(text: 'AI', style: TextStyle(color: kGold)),
                ]),
                style: TextStyle(fontSize: title, fontWeight: FontWeight.w700, letterSpacing: title * .06),
              ),
            ]),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: math.max(20, mq.size.height * .035)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(t('from'), style: TextStyle(fontSize: small, color: p.muted, height: 1.2)),
                SizedBox(height: small * .25),
                Text('SKYQ', style: TextStyle(fontSize: small * 1.35, fontWeight: FontWeight.w700, letterSpacing: small * .35, color: p.text)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

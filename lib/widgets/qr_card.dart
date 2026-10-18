import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr/qr.dart';

import '../i18n.dart';
import '../theme.dart';
import '../widgets.dart';

const _cream = Color(0xFFF4F2EC);
const _grey = Color(0xFF6B6760);

/// The member's QR card, drawn like the website's (web/src/lib/qr.ts): cream card with a gold band,
/// the name, a white panel with a dotted QR code and the WEBWEB mark in the middle, the link below.
/// Always light, so it scans and prints the same in dark mode. Wrap in a [RepaintBoundary] with
/// [key] to export it as a PNG ([qrCardPng]).
class QrCard extends StatelessWidget {
  final String url, name, label;
  const QrCard({super.key, required this.url, required this.name, required this.label});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth.isFinite ? c.maxWidth : 320.0;
      final panel = w * .78;
      return Container(
        width: w,
        color: _cream,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(height: math.max(3, w * .015), decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFFFD84A), Color(0xFFE0AD00)]))),
          SizedBox(height: w * .07),
          Text('WEBWEB AI', style: TextStyle(fontSize: w * .036, fontWeight: FontWeight.w700, color: _grey, letterSpacing: .5)),
          SizedBox(height: w * .02),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: w * .08),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(name, maxLines: 1, style: TextStyle(fontSize: w * .075, fontWeight: FontWeight.w800, color: kInk)),
            ),
          ),
          SizedBox(height: w * .05),
          Container(
            width: panel,
            height: panel,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(w * .05),
              boxShadow: [BoxShadow(color: kInk.withValues(alpha: .16), blurRadius: w * .05, offset: Offset(0, w * .012))],
            ),
            child: Stack(alignment: Alignment.center, children: [
              Positioned.fill(child: CustomPaint(painter: _QrPainter(url))),
              Container(
                width: panel * .27,
                height: panel * .27,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: LogoMark(size: panel * .21),
              ),
            ]),
          ),
          SizedBox(height: w * .055),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: w * .08),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, maxLines: 1, style: TextStyle(fontSize: w * .062, fontWeight: FontWeight.w800, color: kInk)),
            ),
          ),
          SizedBox(height: w * .015),
          Text(t('Scan to open my page'), style: TextStyle(fontSize: w * .036, fontWeight: FontWeight.w600, color: _grey)),
          SizedBox(height: w * .07),
        ]),
      );
    });
  }
}

/// Dotted modules, rounded finder patterns, a clear circle in the middle for the mark
/// (high error correction, so the covered modules do not matter).
class _QrPainter extends CustomPainter {
  final String data;
  _QrPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final img = QrImage(QrCode(payload: QrPayload.fromString(data), errorCorrectLevel: QrErrorCorrectLevel.high));
    final n = img.moduleCount;
    final pad = size.width * .07;
    final cell = (size.width - pad * 2) / n;
    final center = Offset(size.width / 2, size.height / 2);
    final logoR = size.width * .135;
    final ink = Paint()..color = kInk;
    final white = Paint()..color = Colors.white;
    bool inFinder(int r, int c) => (r < 7 && c < 7) || (r < 7 && c >= n - 7) || (r >= n - 7 && c < 7);

    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (!img.isDark(r, c) || inFinder(r, c)) continue;
        final p = Offset(pad + c * cell + cell / 2, pad + r * cell + cell / 2);
        if ((p - center).distance < logoR * 1.15) continue;
        canvas.drawCircle(p, cell * .42, ink);
      }
    }
    void finder(int r, int c) {
      final o = Offset(pad + c * cell, pad + r * cell);
      RRect rr(double inset, double size, double radius) =>
          RRect.fromRectAndRadius(Rect.fromLTWH(o.dx + inset * cell, o.dy + inset * cell, size * cell, size * cell), Radius.circular(radius * cell));
      canvas.drawRRect(rr(0, 7, 2), ink);
      canvas.drawRRect(rr(1, 5, 1.4), white);
      canvas.drawRRect(rr(2, 3, 1), ink);
    }

    finder(0, 0);
    finder(0, n - 7);
    finder(n - 7, 0);
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.data != data;
}

/// The card behind [key] (a RepaintBoundary) as PNG bytes, at a print-friendly resolution.
Future<List<int>?> qrCardPng(GlobalKey key) async {
  final b = key.currentContext?.findRenderObject();
  if (b is! RenderRepaintBoundary) return null;
  final img = await b.toImage(pixelRatio: 1080 / b.size.width);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data?.buffer.asUint8List();
}

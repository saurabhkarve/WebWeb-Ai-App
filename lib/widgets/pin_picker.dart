import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme.dart';
import '../widgets.dart';
import '../places.dart' show findPlace;
import 'city_picker.dart';

/// Set a place by hand, without Location Services: move the map (drag, pinch, + / −) until the pin in the middle sits
/// on the spot, or search a city or area to jump there first. Returns the point under the pin, or null when closed.
Future<({double lat, double lng})?> showPinPicker(BuildContext context, {double? lat, double? lng, String? title}) =>
    Navigator.of(context).push<({double lat, double lng})>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => _PinPicker(lat: lat, lng: lng, title: title)),
    );

class _PinPicker extends StatefulWidget {
  final double? lat, lng;
  final String? title;
  const _PinPicker({this.lat, this.lng, this.title});
  @override
  State<_PinPicker> createState() => _PinPickerState();
}

class _PinPickerState extends State<_PinPicker> {
  static const _tile = 256.0;
  // the map's centre (where the pin is), as a share of the whole world (0..1) so it survives zooming
  late double _mx, _my;
  late double _zf;
  double _zf0 = 0;

  static (double, double) _norm(double lat, double lng) {
    final s = math.sin(lat * math.pi / 180);
    return ((lng + 180) / 360, 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi));
  }

  ({double lat, double lng}) get _centre {
    final lng = _mx * 360 - 180;
    final n = math.pi - 2 * math.pi * _my;
    final lat = 180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
    return (lat: lat, lng: ((lng + 540) % 360) - 180);
  }

  @override
  void initState() {
    super.initState();
    // no starting point: all of India, with the search to jump to a city
    final c = _norm(widget.lat ?? 22.5, widget.lng ?? 79.0);
    _mx = c.$1;
    _my = c.$2;
    _zf = widget.lat == null ? 4.5 : 15;
  }

  void _jump(double lat, double lng) => setState(() {
        final c = _norm(lat, lng);
        _mx = c.$1;
        _my = c.$2;
        _zf = 14;
      });

  Future<void> _search() async {
    final c = await showCitySheet(context, near: widget.lat == null ? null : (lat: widget.lat!, lng: widget.lng!));
    if (c == null || !mounted) return;
    // the sheet gives the place's name; its centre comes from the list of places (a typed town may have none)
    final at = findPlace(c.name);
    if (at?.lat != null && at?.lng != null) {
      _jump(at!.lat!, at.lng!);
    } else if (c.lat != null && c.lng != null) {
      _jump(c.lat!, c.lng!);
    }
  }

  void _zoom(double d) => setState(() => _zf = (_zf + d).clamp(3, 18));

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final top = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;
    // the pin is only exact enough once the map is zoomed in to streets
    final close = _zf >= 13;
    return Scaffold(
      backgroundColor: const Color(0xFFEDEAE3),
      body: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        final zl = _zf.floor();
        final n = math.pow(2, zl).toInt();
        final ts = _tile * math.pow(2, _zf - zl);
        final cx = _mx * n, cy = _my * n;
        final tiles = <Widget>[];
        for (var tx = (cx - w / 2 / ts).floor(); tx <= (cx + w / 2 / ts).floor(); tx++) {
          for (var ty = (cy - h / 2 / ts).floor(); ty <= (cy + h / 2 / ts).floor(); ty++) {
            if (ty < 0 || ty >= n) continue;
            final x = ((tx % n) + n) % n;
            tiles.add(Positioned(
              left: (tx - cx) * ts + w / 2,
              top: (ty - cy) * ts + h / 2,
              width: ts,
              height: ts,
              child: Image.network(
                'https://tile.openstreetmap.org/$zl/$x/$ty.png',
                headers: const {'User-Agent': 'WebWebAI-app/1.0 (+https://webweb.ai)'},
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFEDEAE3)),
              ),
            ));
          }
        }
        Widget zoomBtn(String s, String label, VoidCallback onTap) => Semantics(
              button: true,
              label: label,
              child: GestureDetector(
                onTap: onTap,
                child: Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: p.canvas, borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Color(0x331E1E1E), blurRadius: 6, offset: Offset(0, 2))]),
                  child: Text(s, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: p.text, height: 1)),
                ),
              ),
            );
        return Stack(clipBehavior: Clip.hardEdge, children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (_) => _zf0 = _zf,
              onScaleUpdate: (d) => setState(() {
                _zf = (_zf0 + math.log(d.scale) / math.ln2).clamp(3.0, 18.0);
                final wd = _tile * math.pow(2, _zf);
                _mx -= d.focalPointDelta.dx / wd;
                _my = (_my - d.focalPointDelta.dy / wd).clamp(0.0, 1.0);
              }),
              onDoubleTap: () => _zoom(1),
              child: Stack(clipBehavior: Clip.hardEdge, children: tiles),
            ),
          ),
          // the pin stays in the middle; its tip is the point
          Positioned(left: w / 2 - 16, top: h / 2 - 42, child: const IgnorePointer(child: CustomPaint(size: Size(32, 42), painter: _BigPin()))),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(16, top + 8, 8, 10),
              color: p.canvas.withValues(alpha: .95),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text(widget.title ?? t('Set your location'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                  IconButton(onPressed: () => Navigator.pop(context), icon: WIcon(WI.close, size: 24, color: p.text)),
                ]),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: _search,
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: p.border)),
                    child: Row(children: [
                      WIcon(WI.search, size: 18, color: p.muted),
                      const SizedBox(width: 8),
                      Text(t('Search your city or area'), style: TextStyle(fontSize: 14, color: p.muted)),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
          Positioned(right: 12, top: top + 130, child: Column(children: [zoomBtn('+', t('Zoom in'), () => _zoom(1)), const SizedBox(height: 8), zoomBtn('−', t('Zoom out'), () => _zoom(-1))])),
          Positioned(
            left: 16,
            right: 16,
            bottom: bottom + 16,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: p.canvas.withValues(alpha: .95), borderRadius: BorderRadius.circular(12)),
                child: Text(
                  close ? t('Move the map so the pin is on your shop, office or home.') : t('Search your city, or zoom in, then move the map so the pin is on your place.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, height: 1.35),
                ),
              ),
              const SizedBox(height: 10),
              GoldButton(label: t('Set location here'), onPressed: close ? () => Navigator.pop(context, _centre) : null),
            ]),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.white.withValues(alpha: .8),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              child: const Text('© OpenStreetMap', style: TextStyle(fontSize: 10, color: Color(0xFF333333))),
            ),
          ),
        ]);
      }),
    );
  }
}

/// The pin in the middle of the map: dark, gold-rimmed, its tip on the point.
class _BigPin extends CustomPainter {
  const _BigPin();
  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 28, sy = size.height / 36;
    canvas.scale(sx, sy);
    final path = Path()
      ..moveTo(14, 35)
      ..cubicTo(14, 35, 1.5, 22, 1.5, 13.2)
      ..cubicTo(1.5, 6.4, 7, 1, 14, 1)
      ..cubicTo(21, 1, 26.5, 6.4, 26.5, 13.2)
      ..cubicTo(26.5, 22, 14, 35, 14, 35)
      ..close();
    canvas.drawShadow(path, const Color(0xFF1E1E1E), 3, false);
    canvas.drawPath(path, Paint()..color = const Color(0xFF1E1E1E));
    canvas.drawPath(path, Paint()
      ..color = const Color(0xFFFFC700)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    canvas.drawCircle(const Offset(14, 13), 4.5, Paint()..color = const Color(0xFFFFC700));
  }

  @override
  bool shouldRepaint(_BigPin old) => false;
}

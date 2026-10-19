import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../models.dart';
import '../places.dart';
import '../screens/find.dart';
import '../theme.dart';
import '../widgets.dart';

/// The timing chip of an ask (web ask-chips.tsx timeLeft): days left for "within 7 / 30 days",
/// otherwise the timing as it is.
String? askTimeLeft(Post post) {
  final u = post.urgency;
  if (u == null || u.isEmpty) return null;
  final days = u == '7_days' ? 7 : (u == '30_days' ? 30 : null);
  if (days == null) return t(labelOf(kUrgencies, u));
  final left = (post.createdAt.add(Duration(days: days)).difference(DateTime.now()).inMinutes / 1440).ceil();
  return left > 1 ? t('{n} days left', {'n': left}) : (left == 1 ? t('Last day') : t('Deadline passed'));
}

/// "Edited 14:05" today, else "Edited 12 Oct" (web utils.ts editedLabel).
String editedLabel(DateTime d) {
  final now = DateTime.now();
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final when = d.year == now.year && d.month == now.month && d.day == now.day
      ? '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}'
      : '${d.day} ${months[d.month - 1]}';
  return t('Edited {time}', {'time': when});
}

/// Where an ask reaches: a map of its area with the reach circle (web ask-area-sheet.tsx).
Future<void> showAskAreaSheet(BuildContext context, Post post) {
  final p = Pal.of(context);
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.canvas,
    barrierColor: kInk.withValues(alpha: .6),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) {
      final place = findPlace(post.locationPref);
      final lat = post.lat ?? place?.lat, lng = post.lng ?? place?.lng;
      final radius = (post.radiusM ?? (place?.radiusKm ?? 10) * 1000).toDouble();
      final area = post.locationPref ?? '';
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(t('Where this ask reaches'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
              InkResponse(onTap: () => Navigator.pop(ctx), radius: 20, child: Padding(padding: const EdgeInsets.all(6), child: WIcon(WI.close, size: 20, color: p.muted))),
            ]),
            const SizedBox(height: 12),
            if (lat != null && lng != null)
              ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(height: 280, child: AreaMap(lat: lat, lng: lng, radiusM: radius)))
            else
              Container(height: 120, alignment: Alignment.center, decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(12)), child: Text(t(area), style: TextStyle(color: p.muted))),
            const SizedBox(height: 12),
            Row(children: [
              if (area.isNotEmpty) ...[
                WIcon(WI.pin, size: 16, color: p.muted),
                const SizedBox(width: 4),
                Flexible(child: Text(t(area), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                const SizedBox(width: 12),
              ],
              WIcon(WI.locate, size: 16, color: p.muted),
              const SizedBox(width: 4),
              Text(t('{d} reach', {'d': formatDistance(radius)}), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            Text(t('Members inside the circle see this ask.'), style: TextStyle(fontSize: 12, color: p.muted)),
            if (area.isNotEmpty) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => FindScreen(standalone: true, initialLocation: area)));
                },
                child: Text(t('More asks in {area}', {'area': t(area)}), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.link)),
              ),
            ],
          ]),
        ),
      );
    },
  );
}

/// A still map (OpenStreetMap tiles) centred on a point, zoomed so the reach circle fits, with the circle drawn on top.
class AreaMap extends StatelessWidget {
  final double lat, lng, radiusM;
  const AreaMap({super.key, required this.lat, required this.lng, required this.radiusM});

  static const _tile = 256.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        final cosLat = math.cos(lat * math.pi / 180);
        // metres per pixel at zoom 0 is 156543 · cos(lat); pick the zoom where the circle fills ~70% of the height
        final want = radiusM / (h * .35);
        final z = (math.log(156543.03 * cosLat / want) / math.ln2).floor().clamp(3, 15);
        final scale = math.pow(2, z).toDouble();
        final mpp = 156543.03 * cosLat / scale;
        final cx = (lng + 180) / 360 * _tile * scale;
        final sinLat = math.sin(lat * math.pi / 180);
        final cy = (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) * _tile * scale;
        final left = cx - w / 2, top = cy - h / 2;
        final n = scale.toInt();
        final tiles = <Widget>[];
        for (var tx = (left / _tile).floor(); tx * _tile < left + w; tx++) {
          for (var ty = (top / _tile).floor(); ty * _tile < top + h; ty++) {
            if (ty < 0 || ty >= n) continue;
            final x = ((tx % n) + n) % n;
            tiles.add(Positioned(
              left: tx * _tile - left,
              top: ty * _tile - top,
              width: _tile,
              height: _tile,
              child: Image.network(
                'https://tile.openstreetmap.org/$z/$x/$ty.png',
                headers: const {'User-Agent': 'WebWebAI-app/1.0 (+https://webweb.ai)'},
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFEDEAE3)),
              ),
            ));
          }
        }
        return Stack(clipBehavior: Clip.hardEdge, children: [
          const Positioned.fill(child: ColoredBox(color: Color(0xFFEDEAE3))),
          ...tiles,
          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _Circle(radiusM / mpp)))),
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
      });
}

class _Circle extends CustomPainter {
  final double r;
  _Circle(this.r);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFFFFC700).withValues(alpha: .18));
    canvas.drawCircle(c, r, Paint()
      ..color = const Color(0xFFE0AD00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    canvas.drawCircle(c, 6, Paint()..color = const Color(0xFF1E1E1E));
    canvas.drawCircle(c, 6, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_Circle old) => old.r != r;
}

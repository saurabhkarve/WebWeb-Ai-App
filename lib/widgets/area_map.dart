import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

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

/// The day a "Within 7 / 30 days" ask closes, as "24 Nov" (null for Immediate, Flexible or none).
String? askDeadline(Post post) {
  final u = post.urgency;
  final days = u == '7_days' ? 7 : (u == '30_days' ? 30 : null);
  if (days == null) return null;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final d = post.createdAt.add(Duration(days: days));
  return '${d.day} ${months[d.month - 1]}';
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

/// Where an ask reaches: a map of its area with the reach circle (web ask-area-sheet.tsx). A search box drops a pin on
/// any place and says how far it is from the ask and whether it is inside the circle.
Future<void> showAskAreaSheet(BuildContext context, Post post) {
  final p = Pal.of(context);
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.canvas,
    barrierColor: kInk.withValues(alpha: .6),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    // a bottom drawer: drag it down by its handle (or anywhere, the map is a still picture) or tap the close icon
    showDragHandle: true,
    enableDrag: true,
    builder: (ctx) => _AskAreaSheet(post: post, outer: context),
  );
}

typedef _Spot = ({String name, String sub, double lat, double lng});

class _AskAreaSheet extends StatefulWidget {
  final Post post;
  final BuildContext outer;
  const _AskAreaSheet({required this.post, required this.outer});
  @override
  State<_AskAreaSheet> createState() => _AskAreaSheetState();
}

class _AskAreaSheetState extends State<_AskAreaSheet> {
  final _q = TextEditingController();
  List<_Spot> _hits = [];
  bool _busy = false, _none = false;
  _Spot? _spot;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  // our own places as you type (instant, offline); the keyboard's search also asks OpenStreetMap for streets and landmarks
  void _type(String v) => setState(() {
        _none = false;
        _hits = v.trim().length < 2
            ? []
            : searchPlaces(v, limit: 6).where((x) => x.lat != null && x.lng != null).map((x) => (name: t(x.name), sub: x.subtitle, lat: x.lat!, lng: x.lng!)).toList();
      });

  Future<void> _search() async {
    final text = _q.text.trim();
    if (text.length < 3) return;
    setState(() => _busy = true);
    try {
      final res = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/search?format=json&limit=5&countrycodes=in&q=${Uri.encodeComponent(text)}'),
        headers: const {'Accept-Language': 'en', 'User-Agent': 'WebWebAI-app/1.0 (+https://webweb.ai)'},
      );
      final found = (jsonDecode(res.body) as List).map((d) {
        final parts = '${d['display_name']}'.split(',').map((x) => x.trim()).toList();
        return (name: parts.first, sub: parts.skip(1).take(2).join(', '), lat: double.parse('${d['lat']}'), lng: double.parse('${d['lon']}'));
      }).toList();
      if (mounted) {
        setState(() {
          _hits = found;
          _none = found.isEmpty;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _none = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final post = widget.post;
    final place = findPlace(post.locationPref);
    final lat = post.lat ?? place?.lat, lng = post.lng ?? place?.lng;
    final radius = (post.radiusM ?? (place?.radiusKm ?? 10) * 1000).toDouble();
    final area = post.locationPref ?? '';
    final spot = _spot;
    final away = spot != null && lat != null && lng != null ? distanceKm(lat, lng, spot.lat, spot.lng) * 1000 : null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(t('Where this ask reaches'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            InkResponse(onTap: () => Navigator.pop(context), radius: 20, child: Padding(padding: const EdgeInsets.all(6), child: WIcon(WI.close, size: 20, color: p.muted))),
          ]),
          const SizedBox(height: 10),
          // search a place: a pin on the map and how far it is
          TextField(
            controller: _q,
            onChanged: _type,
            onSubmitted: (_) => _search(),
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: t('Search a place, e.g. Turbhe MIDC'),
              isDense: true,
              filled: true,
              fillColor: p.field,
              prefixIcon: Padding(padding: const EdgeInsets.all(10), child: WIcon(WI.search, size: 18, color: p.muted)),
              prefixIconConstraints: const BoxConstraints(minWidth: 38),
              suffixIcon: _busy ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: BorderSide(color: p.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: BorderSide(color: p.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: BorderSide(color: kGold.withValues(alpha: .6))),
            ),
          ),
          if (_hits.isNotEmpty || _none)
            Container(
              margin: const EdgeInsets.only(top: 6),
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(color: p.canvas, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
              child: _none
                  ? Padding(padding: const EdgeInsets.all(12), child: Text(t('No places found'), style: TextStyle(color: p.muted)))
                  : ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
                      for (final h in _hits)
                        ListTile(
                          dense: true,
                          leading: WIcon(WI.pin, size: 16, color: p.muted),
                          title: Text(h.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: h.sub.isEmpty ? null : Text(h.sub, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () {
                            FocusScope.of(context).unfocus();
                            setState(() {
                              _spot = h;
                              _hits = [];
                              _q.text = h.name;
                            });
                          },
                        ),
                    ]),
            ),
          const SizedBox(height: 10),
          if (lat != null && lng != null)
            // edge to edge in the sheet, square corners (as on the web)
            SizedBox(
              height: 280,
              child: LayoutBuilder(
                builder: (_, box) => OverflowBox(
                  maxWidth: box.maxWidth + 32,
                  minWidth: box.maxWidth + 32,
                  child: DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: p.border))),
                    child: AreaMap(lat: lat, lng: lng, radiusM: radius, point: spot == null ? null : (lat: spot.lat, lng: spot.lng)),
                  ),
                ),
              ),
            )
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
          ValueListenableBuilder<({double lat, double lng})?>(
            valueListenable: kMyPlace,
            builder: (_, me, __) {
              if (me == null || lat == null || lng == null) return const SizedBox.shrink();
              final d = (distanceKm(lat, lng, me.lat, me.lng) * 1000).round();
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF2563EB), border: Border.all(color: Colors.white, width: 2), boxShadow: const [BoxShadow(color: Color(0x552563EB), spreadRadius: 2)])),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: t('You are {d} from this ask', {'d': formatDistance(d)})),
                      TextSpan(text: ' · ${t(d <= radius ? 'Inside the reach' : 'Outside the reach')}', style: TextStyle(fontWeight: FontWeight.w700, color: d <= radius ? const Color(0xFF059669) : p.muted)),
                    ]), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ]),
              );
            },
          ),
          if (spot != null && away != null)
            Text.rich(TextSpan(children: [
              TextSpan(text: t('{place} is {d} from this ask', {'place': spot.name, 'd': formatDistance(away)})),
              TextSpan(
                text: ' · ${t(away <= radius ? 'Inside the reach' : 'Outside the reach')}',
                style: TextStyle(fontWeight: FontWeight.w700, color: away <= radius ? const Color(0xFF059669) : p.muted),
              ),
            ]), style: const TextStyle(fontSize: 13))
          else
            Text(t('Members inside the circle see this ask.'), style: TextStyle(fontSize: 12, color: p.muted)),
          if (area.isNotEmpty) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () {
                Navigator.pop(context);
                Navigator.push(widget.outer, MaterialPageRoute(builder: (_) => FindScreen(standalone: true, initialLocation: area)));
              },
              child: Text(t('More asks in {area}', {'area': t(area)}), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.link)),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Where the member is now, shown as a blue dot on the ask maps so the distance can be compared. Read quietly: only
/// when location is already allowed (a map never asks), and again when the last reading is over five minutes old.
final ValueNotifier<({double lat, double lng})?> kMyPlace = ValueNotifier(null);
DateTime? _myPlaceAt;
bool _myPlaceBusy = false;

Future<void> loadMyPlace() async {
  if (_myPlaceBusy || (_myPlaceAt != null && DateTime.now().difference(_myPlaceAt!) < const Duration(minutes: 5))) return;
  _myPlaceBusy = true;
  try {
    final perm = await Geolocator.checkPermission();
    if ((perm != LocationPermission.whileInUse && perm != LocationPermission.always) || !await Geolocator.isLocationServiceEnabled()) return;
    Position? pos = await Geolocator.getLastKnownPosition();
    pos ??= await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 8)));
    kMyPlace.value = (lat: pos.latitude, lng: pos.longitude);
    _myPlaceAt = DateTime.now();
  } catch (_) {
    // no reading: the map simply has no blue dot
  } finally {
    _myPlaceBusy = false;
  }
}

/// A still map (OpenStreetMap tiles) centred on a point, zoomed so the reach circle fits, with the circle drawn on top.
class AreaMap extends StatelessWidget {
  final double lat, lng, radiusM;
  /// a searched place, drawn as a dark pin; the map zooms out to keep it in view
  final ({double lat, double lng})? point;
  const AreaMap({super.key, required this.lat, required this.lng, required this.radiusM, this.point});

  static const _tile = 256.0;

  @override
  Widget build(BuildContext context) {
    loadMyPlace();
    return ValueListenableBuilder<({double lat, double lng})?>(valueListenable: kMyPlace, builder: (context, me, _) => _map(context, me));
  }

  Widget _map(BuildContext context, ({double lat, double lng})? me) => LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        final cosLat = math.cos(lat * math.pi / 180);
        // metres per pixel at zoom 0 is 156543 · cos(lat); pick the zoom where the circle fills ~70% of the height
        final fromMe = me == null ? null : distanceKm(lat, lng, me.lat, me.lng) * 1000;
        var reach = point == null ? radiusM : math.max(radiusM, distanceKm(lat, lng, point!.lat, point!.lng) * 1000 * 1.15);
        // you are kept in view when you are within 50 km of the ask
        if (fromMe != null && fromMe <= 50000) reach = math.max(reach, fromMe * 1.15);
        final want = reach / (h * .35);
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
          if (point != null)
            Builder(builder: (_) {
              final px = (point!.lng + 180) / 360 * _tile * scale - left;
              final s2 = math.sin(point!.lat * math.pi / 180);
              final py = (0.5 - math.log((1 + s2) / (1 - s2)) / (4 * math.pi)) * _tile * scale - top;
              return Positioned(
                left: px - 14,
                top: py - 34,
                child: IgnorePointer(child: CustomPaint(size: const Size(28, 36), painter: _Pin())),
              );
            }),
          if (me != null && fromMe != null && fromMe <= 50000)
            Builder(builder: (_) {
              final mx = (me.lng + 180) / 360 * _tile * scale - left;
              final s3 = math.sin(me.lat * math.pi / 180);
              final my = (0.5 - math.log((1 + s3) / (1 - s3)) / (4 * math.pi)) * _tile * scale - top;
              return Positioned(
                left: mx - 15,
                top: my - 15,
                child: IgnorePointer(
                  child: Semantics(
                    label: t('You are here'),
                    child: Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF2563EB).withValues(alpha: .22)),
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF2563EB), border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 4)]),
                      ),
                    ),
                  ),
                ),
              );
            }),
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

/// The searched place's pin: dark, gold-rimmed, its tip on the spot (web area-map's search pin).
class _Pin extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
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
  bool shouldRepaint(_Pin old) => false;
}

/// Where an ask is, on a map you can drag, pinch and zoom (buttons too) but not change: view only. The ask's reach is
/// drawn around its pin (web map-viewer.tsx).
Future<void> showAreaViewer(BuildContext context, {required double lat, required double lng, required double radiusM, String? label}) =>
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => _AreaViewer(lat: lat, lng: lng, radiusM: radiusM, label: label)));

class _AreaViewer extends StatefulWidget {
  final double lat, lng, radiusM;
  final String? label;
  const _AreaViewer({required this.lat, required this.lng, required this.radiusM, this.label});
  @override
  State<_AreaViewer> createState() => _AreaViewerState();
}

class _AreaViewerState extends State<_AreaViewer> {
  static const _tile = 256.0;
  late double _zf;
  // the map's centre, as a share of the whole world (0..1) so it survives zooming
  late double _mx, _my;
  double _zf0 = 0;

  static (double, double) _norm(double lat, double lng) {
    final s = math.sin(lat * math.pi / 180);
    return ((lng + 180) / 360, 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi));
  }

  @override
  void initState() {
    super.initState();
    final c = _norm(widget.lat, widget.lng);
    _mx = c.$1;
    _my = c.$2;
    final cosLat = math.cos(widget.lat * math.pi / 180);
    // a place with no reach (a profile's city): a street-level view with no circle
    final want = widget.radiusM / (300 * .45);
    _zf = widget.radiusM <= 0 ? 13 : (math.log(156543.03 * cosLat / want) / math.ln2).floor().clamp(3, 17).toDouble();
  }

  void _zoom(double d) => setState(() => _zf = (_zf + d).clamp(3, 18));

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final pin = _norm(widget.lat, widget.lng);
    return Scaffold(
      backgroundColor: const Color(0xFFEDEAE3),
      body: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        final world = _tile * math.pow(2, _zf);
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
        final px = (pin.$1 - _mx) * world + w / 2;
        final py = (pin.$2 - _my) * world + h / 2;
        final mpp = 156543.03 * math.cos(widget.lat * math.pi / 180) / math.pow(2, _zf);
        final r = widget.radiusM / mpp;
        Widget zoomBtn(String s, VoidCallback onTap) => GestureDetector(
              onTap: onTap,
              child: Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: p.canvas, borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Color(0x331E1E1E), blurRadius: 6, offset: Offset(0, 2))]),
                child: Text(s, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: p.text, height: 1)),
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
          if (r > 0) Positioned(left: px - r, top: py - r, width: r * 2, height: r * 2, child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFD94B3A).withValues(alpha: .1), border: Border.all(color: const Color(0xFFD94B3A).withValues(alpha: .7), width: 2))))),
          Positioned(left: px - 14, top: py - 34, child: IgnorePointer(child: CustomPaint(size: const Size(28, 36), painter: _Pin()))),
          // the title bar
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 8, 8, 10),
              decoration: BoxDecoration(color: p.canvas.withValues(alpha: .92)),
              child: Row(children: [
                const WIcon(WI.pin, size: 20, color: kGold),
                const SizedBox(width: 8),
                Expanded(child: Text(widget.label ?? t('Where'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                IconButton(onPressed: () => Navigator.pop(context), icon: WIcon(WI.close, size: 24, color: p.text)),
              ]),
            ),
          ),
          Positioned(right: 12, top: MediaQuery.of(context).padding.top + 70, child: Column(children: [zoomBtn('+', () => _zoom(1)), const SizedBox(height: 8), zoomBtn('−', () => _zoom(-1))])),
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

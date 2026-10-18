import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets.dart';

/// The shapes the design uses; the server crops to the same ones (api/src/profile-images.ts).
class CropSpec {
  final String kind; // sent to POST /me/photo?kind=
  final double aspect;
  final bool round;
  final int width, height;
  final String title, done, hint;
  const CropSpec(this.kind, this.aspect, this.round, this.width, this.height, this.title, this.done, this.hint);
}

const kAvatarCrop = CropSpec('avatar', 1, true, 640, 640, 'Crop profile photo', 'Use this photo', 'Shown round on your page, asks and chats.');
const kCoverCrop = CropSpec('cover', 3, false, 1500, 500, 'Crop cover', 'Use this cover', 'Shown across the top of your page.');

const _maxZoom = 5.0;

/// Pick a picture from the gallery and crop it to [spec]: PNG bytes at the size the server keeps, or null
/// when the member backs out. The server re-encodes it (JPEG, two sizes, no EXIF).
Future<Uint8List?> pickAndCrop(BuildContext context, CropSpec spec) async {
  final nav = Navigator.of(context);
  // large enough to zoom in, small enough to decode quickly; the picker applies the photo's rotation
  final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400, maxHeight: 2400, imageQuality: 92);
  if (f == null) return null;
  final ui.Image image;
  try {
    final codec = await ui.instantiateImageCodec(await f.readAsBytes());
    image = (await codec.getNextFrame()).image;
  } catch (_) {
    throw ApiException(t('This photo format is not supported. Please choose a JPG, PNG or WebP picture.'));
  }
  try {
    return await nav.push<Uint8List>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => _CropScreen(image: image, spec: spec)));
  } finally {
    image.dispose();
  }
}

class _CropScreen extends StatefulWidget {
  final ui.Image image;
  final CropSpec spec;
  const _CropScreen({required this.image, required this.spec});
  @override
  State<_CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<_CropScreen> {
  // centre of the frame in image pixels, and zoom over "just covers the frame"
  late double _cx = widget.image.width / 2, _cy = widget.image.height / 2;
  double _zoom = 1;
  Size _frame = Size.zero;
  bool _busy = false;
  // gesture start
  double _startZoom = 1;

  double get _base => _frame.isEmpty ? 0 : math.max(_frame.width / widget.image.width, _frame.height / widget.image.height);
  double get _scale => _base * _zoom;

  /// keeps the frame covered by the photo
  void _clamp() {
    _zoom = _zoom.clamp(1.0, _maxZoom);
    final s = _scale;
    if (s == 0) return;
    final hw = _frame.width / 2 / s, hh = _frame.height / 2 / s;
    _cx = _cx.clamp(hw, widget.image.width - hw);
    _cy = _cy.clamp(hh, widget.image.height - hh);
  }

  /// zoom to [z] keeping the image point under [focal] (from the frame's centre) where it is
  void _zoomTo(double z, [Offset focal = Offset.zero]) {
    final s0 = _scale;
    final px = _cx + focal.dx / s0, py = _cy + focal.dy / s0;
    _zoom = z.clamp(1.0, _maxZoom);
    final s1 = _scale;
    _cx = px - focal.dx / s1;
    _cy = py - focal.dy / s1;
    _clamp();
  }

  Future<void> _save() async {
    if (_busy || _scale == 0) return;
    setState(() => _busy = true);
    try {
      final spec = widget.spec;
      final sw = _frame.width / _scale, sh = _frame.height / _scale;
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      final dst = Rect.fromLTWH(0, 0, spec.width.toDouble(), spec.height.toDouble());
      canvas.drawRect(dst, Paint()..color = Colors.white); // transparent PNGs would turn black as JPEG on the server
      canvas.drawImageRect(widget.image, Rect.fromLTWH(_cx - sw / 2, _cy - sh / 2, sw, sh), dst, Paint()..filterQuality = FilterQuality.high);
      final out = await rec.endRecording().toImage(spec.width, spec.height);
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      out.dispose();
      if (!mounted) return;
      Navigator.of(context).pop(data!.buffer.asUint8List());
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, t('Could not prepare the photo. Please try again.'), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final spec = widget.spec;
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        foregroundColor: Colors.white,
        title: Text(t(spec.title)),
      ),
      body: SafeArea(
        top: false,
        child: Column(children: [
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              final fw = math.min(c.maxWidth - 48, (c.maxHeight - 48) * spec.aspect);
              final frame = Size(fw, fw / spec.aspect);
              if (frame != _frame) {
                _frame = frame;
                _clamp();
              }
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: (_) => _startZoom = _zoom,
                onScaleUpdate: (d) => setState(() {
                  final s = _scale;
                  _cx -= d.focalPointDelta.dx / s;
                  _cy -= d.focalPointDelta.dy / s;
                  final focal = d.localFocalPoint - Offset(c.maxWidth / 2, c.maxHeight / 2);
                  _zoomTo(_startZoom * d.scale, focal);
                }),
                onDoubleTap: () => setState(() => _zoomTo(_zoom > 1.5 ? 1 : 2)),
                child: CustomPaint(
                  size: Size(c.maxWidth, c.maxHeight),
                  painter: _CropPainter(widget.image, _cx, _cy, _scale, _frame, spec.round),
                ),
              );
            }),
          ),
          Container(
            color: p.card,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${t(spec.hint)} ${t('Drag to move, pinch to zoom.')}', style: TextStyle(fontSize: 12, color: p.muted)),
              Row(children: [
                Text(t('Zoom'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted)),
                Expanded(
                  child: Slider(
                    value: _zoom,
                    min: 1,
                    max: _maxZoom,
                    activeColor: kGold,
                    onChanged: _busy ? null : (v) => setState(() => _zoomTo(v)),
                  ),
                ),
              ]),
              Row(children: [
                Expanded(child: GoldButton(label: t('Cancel'), outlined: true, onPressed: _busy ? null : () => Navigator.of(context).pop())),
                const SizedBox(width: 10),
                Expanded(child: GoldButton(label: t(spec.done), loading: _busy, onPressed: _busy ? null : _save)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  final ui.Image image;
  final double cx, cy, scale;
  final Size frame;
  final bool round;
  _CropPainter(this.image, this.cx, this.cy, this.scale, this.frame, this.round);

  @override
  void paint(Canvas canvas, Size size) {
    if (scale == 0) return;
    final centre = size.center(Offset.zero);
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.scale(scale);
    canvas.translate(-cx, -cy);
    canvas.drawImage(image, Offset.zero, Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();

    final rect = Rect.fromCenter(center: centre, width: frame.width, height: frame.height);
    void addFrame(Path path) => round ? path.addOval(rect) : path.addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)));
    final hole = Path();
    addFrame(hole);
    // everything outside the frame is dimmed: the screen with the frame cut out (even-odd)
    final dim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    addFrame(dim);
    canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: .6));
    // thirds, to line things up
    canvas.save();
    canvas.clipPath(hole);
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .3)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = rect.left + rect.width * i / 3, y = rect.top + rect.height * i / 3;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), grid);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
    }
    canvas.restore();
    canvas.drawPath(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: .9),
    );
  }

  @override
  bool shouldRepaint(_CropPainter o) => o.cx != cx || o.cy != cy || o.scale != scale || o.frame != frame || o.image != image;
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../i18n.dart';
import '../location.dart';
import '../models.dart';
import '../screens/profile.dart';
import '../theme.dart';
import '../widgets.dart';

/// The reach of the Nearby map, in km (the API only returns members inside it).
const kNearbyKm = 50;

/// A member on the map: where the pin stands (the centre of the area on their page, moved a little) and how far it is.
class NearbyMember {
  final Profile user;
  final double lat, lng, distanceM;
  NearbyMember(this.user, this.lat, this.lng, this.distanceM);
  String get name => displayName(user.userType, user.name, user.company);
  String get what =>
      [if (user.category.isNotEmpty) t(labelOf(kProfileCategories, user.category)), if (user.location.isNotEmpty) user.location].join(' · ');
}

class NearbyData {
  final double? lat, lng;
  final List<NearbyMember> members;
  const NearbyData(this.lat, this.lng, this.members);
  bool get hasCenter => lat != null && lng != null;
}

Future<NearbyData> fetchNearby(BuildContext context, {double? lat, double? lng}) async {
  final api = context.read<AuthProvider>().api;
  final d = await api.get('/users/nearby', {if (lat != null) 'lat': '$lat', if (lng != null) 'lng': '$lng'}) as Map;
  final c = d['center'] as Map?;
  final list = <NearbyMember>[];
  for (final e in (d['members'] as List? ?? const [])) {
    final m = e as Map;
    list.add(NearbyMember(Profile.fromJson(m), (m['lat'] as num).toDouble(), (m['lng'] as num).toDouble(), (m['distanceM'] as num).toDouble()));
  }
  return NearbyData((c?['lat'] as num?)?.toDouble(), (c?['lng'] as num?)?.toDouble(), list);
}

(double, double) _norm(double lat, double lng) {
  final s = math.sin(lat * math.pi / 180);
  return ((lng + 180) / 360, 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi));
}

/// The Nearby tab's map: a small picture of the members within 50 km as pins. Tap it (or a pin) for the full screen map.
class NearbyMapCard extends StatefulWidget {
  const NearbyMapCard({super.key});
  @override
  State<NearbyMapCard> createState() => _NearbyMapCardState();
}

class _NearbyMapCardState extends State<NearbyMapCard> {
  NearbyData? _data;
  bool _failed = false, _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({double? lat, double? lng}) async {
    try {
      final d = await fetchNearby(context, lat: lat, lng: lng);
      if (mounted) setState(() => _data = d);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _useMyLocation() async {
    setState(() => _busy = true);
    try {
      final h = await currentLocation(context, reason: t('to show the members near you on the map'), source: 'other');
      if (!mounted) return;
      await _load(lat: h.lat, lng: h.lng);
    } on PermissionNotGiven {
      // the pop-up already explained
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open([NearbyMember? pick]) {
    final d = _data;
    if (d == null) return;
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => NearbyMapPage(initial: d, pick: pick)));
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final d = _data;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 200,
        decoration: BoxDecoration(color: const Color(0xFFEDEAE3), border: Border.all(color: p.border), borderRadius: BorderRadius.circular(20)),
        child: d == null
            ? Center(child: _failed ? Text(t('The map could not load.'), style: TextStyle(color: p.muted)) : const LogoLoader(size: 32))
            : !d.hasCenter
                ? _noPlace(p)
                : Stack(children: [
                    Positioned.fill(
                      child: _MapView(data: d, interactive: false, onPin: _open, onTapMap: () => _open()),
                    ),
                    Positioned(
                      left: 10,
                      top: 10,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                              color: p.canvas.withValues(alpha: .94),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: const [BoxShadow(color: Color(0x261E1E1E), blurRadius: 6)]),
                          child: Text(
                            d.members.isEmpty
                                ? t('No members within {n} km yet', {'n': kNearbyKm})
                                : t('{c} members within {n} km', {'c': d.members.length, 'n': kNearbyKm}),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 10,
                      top: 10,
                      child: IgnorePointer(
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                              color: p.canvas.withValues(alpha: .94),
                              shape: BoxShape.circle,
                              boxShadow: const [BoxShadow(color: Color(0x261E1E1E), blurRadius: 6)]),
                          child: Icon(Icons.open_in_full_rounded, size: 17, color: p.text),
                        ),
                      ),
                    ),
                  ]),
      ),
    );
  }

  Widget _noPlace(Pal p) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const WIcon(WI.pin, size: 30, color: kGold),
          const SizedBox(height: 8),
          Text(t('See the members around you'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kInk)),
          const SizedBox(height: 4),
          Text(t('Within {n} km, on a map.', {'n': kNearbyKm}), style: const TextStyle(fontSize: 13, color: Color(0xFF555555))),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _busy ? null : _useMyLocation,
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(20)),
              child: Text(_busy ? t('Finding you…') : t('Use my location'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
            ),
          ),
        ]),
      );
}

/// The full screen map: drag, pinch and zoom, a search box over the members, a pin opens the member.
class NearbyMapPage extends StatefulWidget {
  final NearbyData initial;
  final NearbyMember? pick;
  const NearbyMapPage({super.key, required this.initial, this.pick});
  @override
  State<NearbyMapPage> createState() => _NearbyMapPageState();
}

class _NearbyMapPageState extends State<NearbyMapPage> {
  late NearbyData _data = widget.initial;
  final _q = TextEditingController();
  final _focus = FocusNode();
  final _ctl = _MapCtl();
  NearbyMember? _sel;
  bool _busy = false;
  // the result list shows while typing, and closes once one is chosen
  bool _list = false;
  String _last = '';

  @override
  void initState() {
    super.initState();
    _sel = widget.pick;
    _q.addListener(() {
      if (_q.text != _last) _list = true;
      _last = _q.text;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _q.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<NearbyMember> get _matches {
    final q = _q.text.trim().toLowerCase();
    if (q.isEmpty) return _data.members;
    return _data.members.where((m) {
      final u = m.user;
      return '${m.name} ${u.name} ${u.company} ${u.category} ${labelOf(kProfileCategories, u.category)} ${u.location} ${u.services.join(' ')}'
          .toLowerCase()
          .contains(q);
    }).toList();
  }

  void _choose(NearbyMember m) {
    _focus.unfocus();
    setState(() {
      _sel = m;
      _list = false;
    });
    _ctl.flyTo(m.lat, m.lng, zoom: 12);
  }

  Future<void> _here() async {
    setState(() => _busy = true);
    try {
      final h = await currentLocation(context, reason: t('to show the members near you on the map'), source: 'other');
      if (!mounted) return;
      final d = await fetchNearby(context, lat: h.lat, lng: h.lng);
      if (!mounted) return;
      setState(() {
        _data = d;
        _sel = null;
      });
      _ctl.flyTo(h.lat, h.lng, zoom: 10.5);
    } on PermissionNotGiven {
      // the pop-up already explained
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final mq = MediaQuery.of(context);
    final top = mq.padding.top, bottom = mq.padding.bottom;
    // on a phone the search box sits at the bottom, under the thumb; on a wider screen it is at the top
    final small = mq.size.width < 768;
    final matches = _matches;
    final searching = _q.text.trim().isNotEmpty;
    final showList = searching && _list;
    const shadow = [BoxShadow(color: Color(0x331E1E1E), blurRadius: 8, offset: Offset(0, 2))];
    // above the search box when it is at the bottom
    final lift = small ? 12 + 48 + 10 + bottom : 18 + bottom;
    final searchBox = Container(
      height: 48,
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(color: p.canvas, borderRadius: BorderRadius.circular(26), boxShadow: shadow),
      child: Row(children: [
        WIcon(WI.search, size: 20, color: p.muted),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _q,
            focusNode: _focus,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              hintText: t('Search members on the map'),
              hintStyle: TextStyle(color: p.muted, fontWeight: FontWeight.w500),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        if (searching) IconButton(onPressed: _q.clear, icon: WIcon(WI.close, size: 18, color: p.muted)),
      ]),
    );
    final results = showList
        ? Container(
            margin: EdgeInsets.only(top: small ? 0 : 8, bottom: small ? 8 : 0),
            constraints: BoxConstraints(maxHeight: mq.size.height * .4),
            decoration: BoxDecoration(color: p.canvas, borderRadius: BorderRadius.circular(18), boxShadow: shadow),
            child: matches.isEmpty
                ? Padding(padding: const EdgeInsets.all(16), child: Text(t('No one matches on the map.'), style: TextStyle(color: p.muted)))
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: math.min(matches.length, 30),
                    itemBuilder: (_, i) => _row(matches[i], p, () => _choose(matches[i])),
                  ),
          )
        : null;
    return Scaffold(
      backgroundColor: const Color(0xFFEDEAE3),
      resizeToAvoidBottomInset: true,
      body: Stack(children: [
        Positioned.fill(
          child: _MapView(
              data: _data,
              members: matches,
              selected: _sel,
              interactive: true,
              ctl: _ctl,
              onPin: (m) => _choose(m),
              onTapMap: () {
                _focus.unfocus();
                if (_sel != null) setState(() => _sel = null);
              }),
        ),
        // back
        Positioned(
          left: 12,
          top: top + 10,
          child: Semantics(label: t('Back'), button: true, child: _btn(p, Icons.arrow_back_rounded, () => Navigator.pop(context))),
        ),
        // the search box: bottom on a phone (results open upward), top beside the back button on a wider screen
        if (small)
          Positioned(
              left: 12,
              right: 12,
              bottom: 12 + bottom,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [if (results != null) results, searchBox]))
        else
          Positioned(
              left: 68,
              right: 12,
              top: top + 10,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [searchBox, if (results != null) results])),
        // zoom, and back to me (out of the way of the results)
        if (!showList)
          Positioned(
            right: 12,
            bottom: (_sel == null ? 12 : 132) + lift,
            child: Column(children: [
              _btn(p, _busy ? null : Icons.my_location_rounded, _busy ? null : _here, busy: _busy),
              const SizedBox(height: 8),
              _btn(p, Icons.add_rounded, () => _ctl.zoom(1)),
              const SizedBox(height: 8),
              _btn(p, Icons.remove_rounded, () => _ctl.zoom(-1)),
            ]),
          ),
        Positioned(
          left: 0,
          bottom: 0,
          child: Container(
            color: Colors.white.withValues(alpha: .8),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            child: const Text('© OpenStreetMap', style: TextStyle(fontSize: 10, color: Color(0xFF333333))),
          ),
        ),
        if (_sel != null && !showList)
          Positioned(
            left: 12,
            right: 12,
            bottom: lift,
            child: Container(
              decoration: BoxDecoration(color: p.canvas, borderRadius: BorderRadius.circular(20), boxShadow: shadow),
              child: _row(_sel!, p, () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: _sel!.user.handle))),
                  big: true),
            ),
          ),
      ]),
    );
  }

  Widget _btn(Pal p, IconData? icon, VoidCallback? onTap, {bool busy = false}) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: p.canvas,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [BoxShadow(color: Color(0x331E1E1E), blurRadius: 6, offset: Offset(0, 2))]),
          child: busy ? const LogoLoader(size: 20) : Icon(icon, size: 22, color: p.text),
        ),
      );

  Widget _row(NearbyMember m, Pal p, VoidCallback onTap, {bool big = false}) => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: big ? 14 : 8),
          child: Row(children: [
            Avatar(name: m.name, photoUrl: m.user.photoUrl, size: big ? 48 : 38, type: m.user.userType, badge: 16, uid: m.user.uid),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                      child: Text(m.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                  const SizedBox(width: 4),
                  VerifiedBadge(level: m.user.verification, premium: m.user.premium, plan: m.user.plan),
                ]),
                Text(m.what, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.muted)),
              ]),
            ),
            const SizedBox(width: 8),
            Text(t('{d} away', {'d': formatDistance(m.distanceM)}), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.muted)),
          ]),
        ),
      );
}

/// Lets the page move the map (search results, the zoom buttons, back to me).
class _MapCtl {
  _MapViewState? _s;
  void flyTo(double lat, double lng, {double? zoom}) => _s?._flyTo(lat, lng, zoom);
  void zoom(double d) => _s?._zoomBy(d);
}

/// OpenStreetMap tiles, the 50 km circle, the pins and the blue "you are here" dot, drawn the way the ask maps are.
class _MapView extends StatefulWidget {
  final NearbyData data;
  final List<NearbyMember>? members;
  final NearbyMember? selected;
  final bool interactive;
  final _MapCtl? ctl;
  final void Function(NearbyMember) onPin;
  final VoidCallback onTapMap;
  const _MapView({required this.data, this.members, this.selected, required this.interactive, this.ctl, required this.onPin, required this.onTapMap});
  @override
  State<_MapView> createState() => _MapViewState();
}

class _MapViewState extends State<_MapView> {
  static const _tile = 256.0;
  // the centre as a share of the world (0..1), and the zoom (fractional)
  late double _mx, _my;
  double _zf = 8, _zf0 = 8;
  bool _fitted = false;

  @override
  void initState() {
    super.initState();
    final c = _norm(widget.data.lat!, widget.data.lng!);
    _mx = c.$1;
    _my = c.$2;
    widget.ctl?._s = this;
  }

  @override
  void didUpdateWidget(_MapView old) {
    super.didUpdateWidget(old);
    widget.ctl?._s = this;
    if (old.data != widget.data) _fitted = false;
  }

  void _flyTo(double lat, double lng, double? zoom) => setState(() {
        final c = _norm(lat, lng);
        _mx = c.$1;
        _my = c.$2;
        if (zoom != null) _zf = zoom;
      });

  void _zoomBy(double d) => setState(() => _zf = (_zf + d).clamp(4.0, 18.0));

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final pins = widget.members ?? d.members;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth, h = box.maxHeight;
      final cosLat = math.cos(d.lat! * math.pi / 180);
      if (!_fitted) {
        _fitted = true;
        final c = _norm(d.lat!, d.lng!);
        _mx = c.$1;
        _my = c.$2;
        // the 50 km circle fills the shorter side
        final want = kNearbyKm * 1000 / (math.min(w, h) * .46);
        _zf = (math.log(156543.03 * cosLat / want) / math.ln2).clamp(4.0, 14.0);
      }
      final world = _tile * math.pow(2, _zf);
      final zl = _zf.floor();
      final n = math.pow(2, zl).toInt();
      final ts = _tile * math.pow(2, _zf - zl);
      final cx = _mx * n, cy = _my * n;
      Offset at(double lat, double lng) {
        final q = _norm(lat, lng);
        return Offset((q.$1 - _mx) * world + w / 2, (q.$2 - _my) * world + h / 2);
      }

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
      final me = at(d.lat!, d.lng!);
      final r = kNearbyKm * 1000 / (156543.03 * cosLat / math.pow(2, _zf));
      final big = widget.interactive;
      final size = big ? 40.0 : 26.0;
      // the selected one last, so it is on top
      final ordered = [...pins.where((m) => m != widget.selected), if (widget.selected != null) widget.selected!];
      final pinWidgets = <Widget>[];
      for (final m in ordered) {
        final o = at(m.lat, m.lng);
        if (o.dx < -size || o.dx > w + size || o.dy < -size || o.dy > h + size) continue;
        final sel = m == widget.selected;
        final s = sel ? size * 1.25 : size;
        pinWidgets.add(Positioned(
          left: o.dx - s / 2,
          top: o.dy - s / 2,
          width: s,
          height: s,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onPin(m),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: kGoldGradient,
                border: Border.all(color: sel ? kInk : Colors.white, width: sel ? 3 : 2),
                boxShadow: const [BoxShadow(color: Color(0x551E1E1E), blurRadius: 5, offset: Offset(0, 2))],
              ),
              padding: const EdgeInsets.all(2),
              child: ClipOval(
                child: big
                    ? Avatar(name: m.name, photoUrl: m.user.photoUrl, size: s - 10, type: m.user.userType, badge: 0)
                    : Center(
                        child: Text(m.name.isEmpty ? '' : m.name.characters.first.toUpperCase(),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: kInk))),
              ),
            ),
          ),
        ));
      }
      return Stack(clipBehavior: Clip.hardEdge, children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTapMap,
            onScaleStart: widget.interactive ? (_) => _zf0 = _zf : null,
            onScaleUpdate: widget.interactive
                ? (g) => setState(() {
                      _zf = (_zf0 + math.log(g.scale) / math.ln2).clamp(4.0, 18.0);
                      final wd = _tile * math.pow(2, _zf);
                      _mx -= g.focalPointDelta.dx / wd;
                      _my = (_my - g.focalPointDelta.dy / wd).clamp(0.0, 1.0);
                    })
                : null,
            onDoubleTap: widget.interactive ? () => _zoomBy(1) : null,
            child: Stack(clipBehavior: Clip.hardEdge, children: tiles),
          ),
        ),
        Positioned(
          left: me.dx - r,
          top: me.dy - r,
          width: r * 2,
          height: r * 2,
          child: IgnorePointer(
              child: DecoratedBox(
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, color: kGold.withValues(alpha: .12), border: Border.all(color: const Color(0xFFE0AD00), width: 2)))),
        ),
        ...pinWidgets,
        Positioned(
          left: me.dx - 15,
          top: me.dy - 15,
          child: IgnorePointer(
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF2563EB).withValues(alpha: .22)),
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF2563EB),
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 4)]),
              ),
            ),
          ),
        ),
        if (!widget.interactive)
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
}

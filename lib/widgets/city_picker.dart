import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../i18n.dart';
import '../location.dart';
import '../places.dart';
import '../theme.dart';
import '../widgets.dart';

/// A city chosen in the sheet: a name from the list or one the member typed, with their position when they
/// shared it (it gives a new town a centre).
typedef PickedCity = ({String name, double? lat, double? lng});

/// A city field (web components/city-picker.tsx): shows the chosen city; a tap opens [showCitySheet].
class CityPill extends StatelessWidget {
  final String value;
  final String placeholder;

  /// offers a "no city" choice with this label (filters: "Any location")
  final String? anyLabel;
  final void Function(PickedCity city) onChanged;
  final double height;
  final bool rounded;
  final ({double lat, double lng})? near;
  const CityPill({super.key, required this.value, required this.onChanged, this.placeholder = 'Choose your city', this.anyLabel, this.height = 44, this.rounded = false, this.near});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final place = findPlace(value);
    return GestureDetector(
      onTap: () async {
        final c = await showCitySheet(context, value: value, anyLabel: anyLabel, near: near ?? (place?.lat != null ? (lat: place!.lat!, lng: place.lng!) : null));
        if (c != null) onChanged(c);
      },
      child: Container(
        height: height,
        padding: const EdgeInsets.only(left: 12, right: 10),
        decoration: BoxDecoration(color: p.card, border: Border.all(color: p.border), borderRadius: BorderRadius.circular(rounded ? height : 10)),
        child: Row(children: [
          WIcon(WI.pin, size: 16, color: p.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: value.isEmpty ? (anyLabel ?? t(placeholder)) : (value == 'Other' ? t('Other') : value)),
                if (place != null && place.tier > 0) TextSpan(text: '  ${place.stateName}', style: TextStyle(fontSize: 12, color: p.muted)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: value.isEmpty ? p.muted : p.text),
            ),
          ),
          WIcon(WI.chevronDown, size: 16, color: p.muted),
        ]),
      ),
    );
  }
}

/// Search India's tier 1-3 cities, pick one near the member (their location, or [near]), or name a town that
/// is not in the list. Returns null when closed; an empty name for [anyLabel].
Future<PickedCity?> showCitySheet(BuildContext context, {String? value, String? anyLabel, ({double lat, double lng})? near, bool startWithLocation = false}) {
  final p = Pal.of(context);
  return showModalBottomSheet<PickedCity>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: p.canvas,
    barrierColor: kInk.withValues(alpha: .6),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _CitySheet(value: value ?? '', anyLabel: anyLabel, near: near, startWithLocation: startWithLocation),
  );
}

class _CitySheet extends StatefulWidget {
  final String value;
  final String? anyLabel;
  final ({double lat, double lng})? near;
  final bool startWithLocation;
  const _CitySheet({required this.value, this.anyLabel, this.near, this.startWithLocation = false});
  @override
  State<_CitySheet> createState() => _CitySheetState();
}

class _CitySheetState extends State<_CitySheet> {
  final _q = TextEditingController();
  ({double lat, double lng})? _here;
  bool _locating = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    loadCustomPlaces(context.read<AuthProvider>().api).then((_) {
      if (mounted) setState(() {});
    });
    if (widget.startWithLocation) WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _note = null;
    });
    try {
      final h = await currentLocation(context, reason: t('To show the cities near you.'), source: 'city');
      if (mounted) setState(() => _here = (lat: h.lat, lng: h.lng));
    } on PermissionNotGiven {
      // the pop-up explained it
    } catch (_) {
      if (mounted) setState(() => _note = t('Could not get your location. Search for your city instead.'));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _pick(String name) => Navigator.pop<PickedCity>(context, (name: name, lat: _here?.lat, lng: _here?.lng));

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final q = _q.text;
    final origin = _here ?? widget.near;
    final inCity = _here == null ? null : placeAt(_here!.lat, _here!.lng);
    final nearby = origin == null ? const <({Place place, double km})>[] : nearbyPlaces(origin.lat, origin.lng, limit: 10, maxKm: 250);
    final results = searchPlaces(q);
    final typed = tidyPlaceName(q);
    final exact = typed.length >= 2 && results.any((x) => x.name.toLowerCase() == typed.toLowerCase());

    Widget header(String s) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
          child: Text(s.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.muted, letterSpacing: .8)),
        );
    Widget row(Place pl, {double? km, String? badge}) => InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _pick(pl.name),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: widget.value == pl.name ? kGold.withValues(alpha: .15) : null, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              WIcon(WI.pin, size: 16, color: p.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(pl.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  Text(pl.tier == -1 ? t('Added by members') : pl.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted)),
                ]),
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFF2F9E6B).withValues(alpha: .15), borderRadius: BorderRadius.circular(20)),
                  child: Text(badge, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.dark ? const Color(0xFF5FCF9A) : const Color(0xFF1F7A50))),
                )
              else if (km != null)
                Text(km < 1 ? '<1 km' : '${km.round()} km', style: TextStyle(fontSize: 12, color: p.muted)),
            ]),
          ),
        );

    return SizedBox(
      height: MediaQuery.of(context).size.height * .85,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(children: [
              Expanded(child: Text(t('Choose your city'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
              GestureDetector(onTap: () => Navigator.pop(context), child: WIcon(WI.close, size: 24, color: p.text)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AppField(
              controller: _q,
              hint: t('Search a city or town'),
              prefixIcon: Padding(padding: const EdgeInsets.all(12), child: WIcon(WI.search, size: 18, color: p.muted)),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (results.isNotEmpty) {
                  _pick(results.first.name);
                } else if (typed.length >= 2) {
                  _pick(typed);
                }
              },
            ),
          ),
          Expanded(
            child: ListView(padding: EdgeInsets.fromLTRB(8, 8, 8, MediaQuery.of(context).padding.bottom + 16), children: [
              if (q.trim().isEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
                    onTap: _locating ? null : _locate,
                    child: DashedBox(
                      radius: 10,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      child: Row(children: [
                        WIcon(WI.locate, size: 16, color: p.link, strokeWidth: 1.9),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _locating ? t('Locating…') : (_here != null ? t('Location found') : t('Use my location to find cities near me')),
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.link),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
                if (_note != null) Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 0), child: Text(_note!, style: TextStyle(fontSize: 12, color: p.muted))),
                if (_here != null && inCity == null)
                  Container(
                    margin: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(10)),
                    child: Text(t('Your town is not in our list yet. Type its name above and add it, or pick the nearest city.'), style: TextStyle(fontSize: 12, color: p.muted)),
                  ),
                if (widget.anyLabel != null)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _pick(''),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
                      child: Text(widget.anyLabel!, style: TextStyle(fontSize: 14, fontWeight: widget.value.isEmpty ? FontWeight.w700 : FontWeight.w500)),
                    ),
                  ),
                if (nearby.isNotEmpty) ...[
                  header(_here != null ? t('Near you') : t('Nearby')),
                  for (final x in nearby) row(x.place, km: x.km, badge: inCity?.name == x.place.name ? t('You are here') : null),
                ],
                header(t('Big cities')),
                for (final pl in kMetros) row(pl),
              ] else ...[
                for (final pl in results) row(pl, km: origin != null && pl.lat != null ? distanceKm(origin.lat, origin.lng, pl.lat!, pl.lng!) : null),
                if (typed.length >= 2 && !exact)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                    child: GestureDetector(
                      onTap: () => _pick(typed),
                      child: DashedBox(
                        radius: 10,
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: kGold.withValues(alpha: .25), shape: BoxShape.circle),
                            child: const Text('+', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(t('Use “{name}”', {'name': typed}), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                              Text(_here != null ? t('Not in our list: we add it with your location') : t('Not in our list: we add it for everyone'), style: TextStyle(fontSize: 12, color: p.muted)),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

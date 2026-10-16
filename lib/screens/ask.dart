import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../location.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/pickers.dart';
import 'find.dart' show FilterPill;

/// Starter text per category (value -> [title, description]); the API needs title >= 5 and description >= 20 characters.
const _templates = {
  'job': [
    ['Need 5 CNC operators', 'Looking for CNC operators with 2+ years of experience. Day shift. Please share salary expectation and joining date.'],
    ['Need a delivery driver', 'Looking for a delivery driver with own two-wheeler for local deliveries. Fixed salary plus fuel allowance.'],
  ],
  'supplier': [['Need a packaging supplier', 'Looking for a reliable supplier of corrugated boxes, monthly requirement. Please share rates and minimum order quantity.']],
  'buyer': [['Looking for bulk buyers', 'We supply quality products at wholesale rates. Looking for shops and distributors to connect with in Navi Mumbai.']],
  'logistics': [['Mini truck needed for a trip', 'Need a mini truck for a one-way trip. Please share rate per trip, vehicle details and availability.']],
  'funding': [['Need working capital', 'Looking for working capital for a growing business. Please refer lenders or share your experience.']],
  'advice': [['Need advice on GST filing', 'I would like opinions from people who have done this before. Please share what worked for you.']],
};

const _tips = {
  'job': 'Role, experience, salary and joining date get the most replies.',
  'supplier': 'Mention the item, quantity and delivery location.',
  'buyer': 'Say what you sell and who you are looking for.',
  'logistics': 'Pickup, drop, weight and date help transporters reply faster.',
  'funding': 'Share the amount, purpose and your business stage.',
};

/// Reach radius steps (web/src/lib/geo.ts RADIUS_STEPS); the last one covers all of India.
const _radii = [5000, 10000, 25000, 50000, 100000, 250000, 500000, 1000000, 3000000];
String _radiusLabel(int m) => m >= 3000000 ? 'Pan-India' : '${m ~/ 1000} km';

/// Ask tab: post an Ask (requirement) or an Update.
class AskScreen extends StatefulWidget {
  final VoidCallback onPosted;
  const AskScreen({super.key, required this.onPosted});
  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends State<AskScreen> {
  int _tab = 0;
  String _category = 'job';
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _budget = TextEditingController();
  final _update = TextEditingController();
  String? _location;
  String? _urgency;
  bool _detailsOpen = false;
  final List<String> _photos = [];
  final List<String> _updatePhotos = [];
  bool _busy = false;
  bool _uploading = false;
  /// Pin from "Use my location" (otherwise the server uses the area's centre).
  Here? _here;
  int _radius = 10000;
  bool _locating = false;
  int? _reach;

  @override
  void initState() {
    super.initState();
    _location = context.read<AuthProvider>().profile?.location;
    _loadReach();
  }

  /// How many members this ask reaches (same count the web shows under the form).
  Future<void> _loadReach() async {
    try {
      final d = await context.read<AuthProvider>().api.get('/users/reach', {
        if (_location != null) 'location': _location,
        if (_here != null) ...{'lat': _here!.lat, 'lng': _here!.lng, 'radiusM': _radius},
      }) as Map;
      if (mounted) setState(() => _reach = (d['members'] as num?)?.toInt());
    } catch (_) {}
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      final h = await currentLocation();
      if (!mounted) return;
      setState(() {
        _here = h;
        if (h.node != 'Other') _location = h.node;
      });
      _loadReach();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  bool get _valid => _title.text.trim().length >= 5 && _desc.text.trim().length >= 20;

  Future<void> _addPhoto(List<String> target, int max) async {
    if (target.length >= max) return;
    final api = context.read<AuthProvider>().api;
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1280, imageQuality: 75);
    if (f == null) return;
    setState(() => _uploading = true);
    try {
      final url = await api.uploadImage(await f.readAsBytes(), f.name);
      if (mounted) setState(() => target.add(url));
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _publish() async {
    setState(() => _busy = true);
    try {
      await context.read<AuthProvider>().api.post('/posts', {
        'title': _title.text.trim(),
        'description': _desc.text.trim(),
        'category': _category,
        if (_location != null) 'locationPref': _location,
        if (_budget.text.trim().isNotEmpty) 'budget': _budget.text.trim(),
        if (_urgency != null) 'urgency': _urgency,
        if (_here != null) ...{'lat': _here!.lat, 'lng': _here!.lng, 'radiusM': _radius},
        'images': _photos,
      });
      if (!mounted) return;
      _title.clear();
      _desc.clear();
      _budget.clear();
      setState(() {
        _photos.clear();
        _urgency = null;
      });
      toast(context, 'Ask published');
      widget.onPosted();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _postUpdate() async {
    setState(() => _busy = true);
    try {
      await context.read<AuthProvider>().api.post('/posts', {'kind': 'update', if (_update.text.trim().isNotEmpty) 'text': _update.text.trim(), 'images': _updatePhotos});
      if (!mounted) return;
      _update.clear();
      setState(_updatePhotos.clear);
      toast(context, 'Update posted');
      widget.onPosted();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showTemplates() {
    final list = _templates[_category] ?? const [];
    if (list.isEmpty) return toast(context, 'No templates for this category yet');
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.all(14), child: Text('Start from a template', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17))),
          for (final t in list)
            ListTile(
              title: Text(t[0], style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(t[1], maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () {
                setState(() {
                  _title.text = t[0];
                  _desc.text = t[1];
                });
                Navigator.pop(ctx);
              },
            ),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    for (final c in [_title, _desc, _budget, _update]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return SafeArea(
      bottom: false,
      child: Column(children: [
        Row(children: [
          for (final e in [(0, Icons.back_hand_outlined, 'Ask'), (1, Icons.campaign_outlined, 'Update')])
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _tab = e.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _tab == e.$1 ? p.text : p.border, width: _tab == e.$1 ? 2 : 1))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(e.$2, size: 20, color: _tab == e.$1 ? p.text : p.muted),
                    const SizedBox(width: 8),
                    Text(e.$3, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: _tab == e.$1 ? p.text : p.muted)),
                  ]),
                ),
              ),
            ),
        ]),
        Expanded(child: _tab == 0 ? _askForm(p) : _updateForm(p)),
      ]),
    );
  }

  Widget _photoRow(List<String> photos, int max, Pal p) => Wrap(spacing: 10, runSpacing: 10, children: [
        for (var i = 0; i < photos.length; i++)
          Stack(clipBehavior: Clip.none, children: [
            NetImage(photos[i], size: 80),
            Positioned(right: -6, top: -6, child: GestureDetector(onTap: () => setState(() => photos.removeAt(i)), child: const CircleAvatar(radius: 11, backgroundColor: Colors.black87, child: Icon(Icons.close, size: 14, color: Colors.white)))),
          ]),
        if (photos.length < max)
          GestureDetector(
            onTap: _uploading ? null : () => _addPhoto(photos, max),
            child: DashedBox(
              radius: 14,
              padding: EdgeInsets.zero,
              child: SizedBox(
                width: 110,
                height: 80,
                child: _uploading
                    ? const Center(child: LogoLoader(size: 28))
                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_photo_alternate_outlined, color: p.muted), const SizedBox(width: 6), Text('Add photos', style: TextStyle(color: p.muted, fontWeight: FontWeight.w600, fontSize: 12.5))]),
              ),
            ),
          ),
      ]);

  Widget _askForm(Pal p) {
    final tip = _tips[_category];
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 16), children: [
          Text('Ask the network to share a contact or an opinion for your business need.', style: TextStyle(color: p.muted, fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          Container(
            height: 52,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(30), border: Border.all(color: p.border)),
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final o in kPostCategories) Padding(padding: const EdgeInsets.only(right: 6), child: FilterPill(label: kCategoryShort[o.value]!, selected: _category == o.value, onTap: () => setState(() => _category = o.value))),
            ]),
          ),
          if (tip != null) ...[
            const SizedBox(height: 10),
            Row(children: [const Text('💡 ', style: TextStyle(fontSize: 12)), Expanded(child: Text(tip, style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w500)))]),
          ],
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _showTemplates,
            child: DashedBox(
              radius: 24,
              color: kGold.withValues(alpha: .6),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.auto_awesome, size: 16, color: kGold), SizedBox(width: 8), Text('Start from a template', style: TextStyle(color: kGold, fontWeight: FontWeight.w700))]),
            ),
          ),
          const SizedBox(height: 16),
          AppField(controller: _title, label: 'Title *', hint: 'e.g. Need 5 CNC operators in Turbhe', maxLength: 100, onChanged: (_) => setState(() {}), caps: TextCapitalization.sentences),
          const SizedBox(height: 14),
          AppField(controller: _desc, label: 'Description *', hint: 'Describe what you need: quantity, quality, area, timing (min 20 characters)', maxLines: 5, maxLength: 1000, onChanged: (_) => setState(() {}), caps: TextCapitalization.sentences),
          const SizedBox(height: 14),
          _photoRow(_photos, 10, p),
          const SizedBox(height: 14),
          InkWell(
            onTap: () => setState(() => _detailsOpen = !_detailsOpen),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Location, timing and budget', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('${_location ?? 'Anywhere'} · ${_urgency == null ? 'Any time' : labelOf(kUrgencies, _urgency)} · ${_budget.text.isEmpty ? 'No budget' : _budget.text}', style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w500)),
                ])),
                Icon(_detailsOpen ? Icons.expand_less : Icons.chevron_right, color: p.muted),
              ]),
            ),
          ),
          if (_detailsOpen) ...[
            const SizedBox(height: 12),
            PickerField(label: 'Location', options: kLocations, value: _location, hint: 'Anywhere', onChanged: (v) {
              setState(() {
                _location = v;
                _here = null; // a picked area replaces the GPS pin
              });
              _loadReach();
            }),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _locating ? null : _useMyLocation,
                icon: _locating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(_here != null ? Icons.my_location : Icons.location_searching, size: 18, color: kGold),
                label: Text(_here != null ? 'Using your current location' : 'Use my location', style: const TextStyle(color: kGold, fontWeight: FontWeight.w700)),
              ),
            ),
            if (_here != null) ...[
              Text('Reach: ${_radiusLabel(_radius)}', style: const TextStyle(fontWeight: FontWeight.w700)),
              Slider(
                value: _radii.indexOf(_radius).toDouble(),
                min: 0,
                max: (_radii.length - 1).toDouble(),
                divisions: _radii.length - 1,
                activeColor: kGold,
                label: _radiusLabel(_radius),
                onChanged: (v) => setState(() => _radius = _radii[v.round()]),
                onChangeEnd: (_) => _loadReach(),
              ),
            ],
            const SizedBox(height: 12),
            PickerField(label: 'Urgency', options: kUrgencies, value: _urgency, hint: 'Any time', onChanged: (v) => setState(() => _urgency = v)),
            const SizedBox(height: 12),
            AppField(controller: _budget, label: 'Budget', hint: 'e.g. ₹25,000 - ₹35,000', maxLength: 60, onChanged: (_) => setState(() {})),
          ],
        ]),
      ),
      Container(
        decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.border))),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Icon(Icons.people_outline, size: 15, color: p.muted),
            const SizedBox(width: 6),
            Expanded(child: Text(_reach == null ? 'Reaches members in ${_location ?? 'your area'}' : 'Reaches $_reach member${_reach == 1 ? '' : 's'} ${_here != null ? 'within ${_radiusLabel(_radius)}' : 'in ${_location ?? 'your area'}'}', style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w500))),
            Text(_title.text.trim().length < 5 ? 'Add a title' : '', style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w500)),
          ]),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: GoldButton(label: 'Publish Ask', loading: _busy, onPressed: _valid ? _publish : null)),
        ]),
      ),
    ]);
  }

  Widget _updateForm(Pal p) => ListView(padding: const EdgeInsets.all(16), children: [
        Text('Share news with your network. Text, photos, or both.', style: TextStyle(color: p.muted, fontWeight: FontWeight.w500)),
        const SizedBox(height: 16),
        AppField(controller: _update, label: 'Update', hint: "What's new?", maxLines: 5, maxLength: 1000, onChanged: (_) => setState(() {})),
        const SizedBox(height: 14),
        _photoRow(_updatePhotos, 4, p),
        const SizedBox(height: 20),
        GoldButton(label: 'Post update', loading: _busy, onPressed: (_update.text.trim().isNotEmpty || _updatePhotos.isNotEmpty) ? _postUpdate : null),
      ]);
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../auth_provider.dart';
import '../cover_default.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/reviews_card.dart' show Stars, kStar;
import '../widgets/whatsapp_icon.dart';
import 'profile.dart' show ProfileScreen, ProfileActionBtn;

/// The page of a phone number, @9876543210 (as on the website), for a contact that has no page of its own yet: one members
/// saved and WEBWEB approved, or one pushed through the Contacts API. It looks like a member's page: a cover picked from
/// the number, the name as the picture, the details there are (phone, WhatsApp, Google Business, location, website), and
/// reviews, which any member can write though the contact has not joined. The number is unique, so it is the address until
/// the owner joins; then the page moves to their own handle. [initial] is what the search already knew, shown while it loads.
class ServicePageScreen extends StatefulWidget {
  final String phone;
  final Map? initial;
  final String? shared;
  const ServicePageScreen({super.key, required this.phone, this.initial, this.shared});
  @override
  State<ServicePageScreen> createState() => _ServicePageScreenState();
}

class _ServicePageScreenState extends State<ServicePageScreen> {
  Map? _c;
  Map _reviews = const {'count': 0, 'avg': 0, 'reviews': []};
  bool _missing = false;
  bool _writing = false;
  bool _busy = false;
  int _stars = 0;
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _c = widget.initial;
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await context.read<AuthProvider>().api.get('/service-contacts/page/${widget.phone}') as Map;
      if (!mounted) return;
      final handle = (r['registered'] as Map?)?['handle'];
      if (handle != null) {
        // the owner has joined: the page is theirs now
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: '$handle')));
        return;
      }
      setState(() {
        _c = {...?widget.initial, ...(r['contact'] as Map? ?? const {})};
        _setReviews(r['reviews'] as Map?);
      });
    } catch (_) {
      if (mounted && _c == null) setState(() => _missing = true);
    }
  }

  void _setReviews(Map? r) {
    if (r == null) return;
    _reviews = r;
    final mine = r['mine'] as Map?;
    _stars = (mine?['rating'] as num?)?.toInt() ?? 0;
    _text.text = '${mine?['text'] ?? ''}';
  }

  Future<void> _save() async {
    if (_stars == 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('Choose 1 to 5 stars'))));
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await context.read<AuthProvider>().api.put('/service-contacts/page/${widget.phone}/review', {'rating': _stars, if (_text.text.trim().isNotEmpty) 'text': _text.text.trim()}) as Map;
      if (!mounted) return;
      setState(() {
        _setReviews(r);
        _writing = false;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    try {
      final r = await context.read<AuthProvider>().api.delete('/service-contacts/page/${widget.phone}/review') as Map;
      if (!mounted) return;
      setState(() {
        _stars = 0;
        _text.clear();
        _reviews = r;
        _writing = false;
      });
    } catch (_) {}
  }

  static void _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);

  Widget _row(Pal p, Widget icon, String title, String? sub, String url) => InkWell(
        onTap: () => _open(url),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Container(width: 38, height: 38, alignment: Alignment.center, decoration: BoxDecoration(color: p.chip, shape: BoxShape.circle), child: icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (sub != null && sub.isNotEmpty) Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 13)),
              ]),
            ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final c = _c;
    if (c == null) {
      return Scaffold(
        backgroundColor: p.canvas,
        appBar: AppBar(title: Text('@${widget.phone}')),
        body: Center(child: _missing ? Text(t('Page not found'), style: TextStyle(color: p.muted)) : const CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return Scaffold(backgroundColor: p.canvas, body: _page(p, c, widget.phone));
  }

  Widget _page(Pal p, Map c, String phone) {
    final top = MediaQuery.of(context).padding.top;
    final name = '${c['company'] ?? ''}'.isNotEmpty ? '${c['company']} (${c['name']})' : '${c['name']}';
    final km = c['km'] is num ? t('{n} km', {'n': (c['km'] as num) < 10 ? (c['km'] as num).toStringAsFixed(1) : (c['km'] as num).round()}) : '';
    final where = ['${c['place'] ?? ''}', km].where((x) => x.isNotEmpty).join(' · ');
    final tags = ((c['tags'] as List?) ?? const []).map((x) => '$x').take(3).toList();
    final maps = '${c['mapsUrl'] ?? ''}';
    final site = '${c['website'] ?? ''}';
    final address = '${c['address'] ?? ''}'.isNotEmpty ? '${c['address']}' : '${c['place'] ?? ''}';
    final sharers = ((c['sharedBy'] as Map?)?['count'] as num?)?.toInt() ?? 0;
    final rating = c['rating'] is num ? (c['rating'] as num).toDouble() : null;
    final count = (_reviews['count'] as num?)?.toInt() ?? 0;
    final avg = (_reviews['avg'] as num?)?.toDouble() ?? 0;
    final list = ((_reviews['reviews'] as List?) ?? const []).cast<Map>();
    final mine = _reviews['mine'] as Map?;
    final shareText = '${t('Review {name} on WEBWEB', {'name': '${c['name']}'})}: https://webweb.ai/@$phone';
    // the contact's Google Business profile (its Maps page), else a Google search for it
    final google = maps.isNotEmpty ? maps : 'https://www.google.com/search?q=${Uri.encodeComponent('${c['name']} $address')}';
    final gold = p.dark ? const Color(0xFFFFD84A) : const Color(0xFF7A5A00);
    final band = MediaQuery.sizeOf(context).width / 4;

    Widget tag(String text, {IconData? icon, VoidCallback? onTap, bool goldChip = false}) {
      final w = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: goldChip ? kGold.withValues(alpha: .18) : p.chip, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: goldChip ? gold : p.text), const SizedBox(width: 4)],
          Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: goldChip ? gold : p.text))),
        ]),
      );
      return onTap == null ? w : GestureDetector(onTap: onTap, child: w);
    }

    return ListView(padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 32), children: [
      // the cover, picked from the number so the page always looks the same, with the back arrow on it
      SizedBox(
        height: top + band,
        child: Stack(fit: StackFit.expand, children: [
          NetImg(defaultCoverUrl(phone, words: tags), alignment: Alignment.topCenter, fallback: CoverPattern(seed: phone)),
          Positioned(
            top: top,
            left: 8,
            height: 56,
            child: Semantics(
              button: true,
              label: t('Back'),
              child: GestureDetector(onTap: () => Navigator.maybePop(context), child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .75), shape: BoxShape.circle), child: const WIcon(WI.back, size: 28, color: kInk))),
            ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // the picture is the name, with who shares it and what Google says where a member's page has its numbers
          Transform.translate(
            offset: const Offset(0, -44),
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: p.canvas, shape: BoxShape.circle), child: Avatar(name: '${c['name']}', size: 96)),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '$sharers', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: gold)),
                      TextSpan(text: ' ${t('members share this')}'),
                      if (rating != null) ...[
                        const TextSpan(text: ' · '),
                        TextSpan(text: '★ ${rating.toStringAsFixed(1)}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: gold)),
                        const TextSpan(text: ' Google'),
                      ],
                    ]),
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 12, color: p.muted, height: 1.2),
                  ),
                ),
              ]),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -38),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: name),
                  // nobody has checked this contact: members saved it and WEBWEB approved it, nothing more
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(20)),
                        child: Text(t('Not verified'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.muted, height: 1.3)),
                      ),
                    ),
                  ),
                ]),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.375),
              ),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: '@$phone', style: TextStyle(fontWeight: FontWeight.w700, color: p.link)),
                  if (tags.isNotEmpty) TextSpan(text: ' · ${tags.first}'),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: p.muted, height: 1.375),
              ),
              if (address.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(address, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, height: 1.43))),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (where.isNotEmpty) tag(where, icon: Icons.place_outlined, onTap: maps.isNotEmpty ? () => _open(maps) : null),
                for (final x in tags) tag(x),
                if (rating != null) tag('★ ${rating.toStringAsFixed(1)}${c['ratings'] is num ? ' (${c['ratings']})' : ''} Google', goldChip: true, onTap: () => _open(google)),
                if (widget.shared != null) tag(widget.shared!),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: ProfileActionBtn(label: t('Call'), wi: WI.phone, gold: true, onTap: () => _open('tel:+91$phone'))),
                const SizedBox(width: 8),
                Expanded(child: ProfileActionBtn(label: 'WhatsApp', leading: const Padding(padding: EdgeInsets.only(right: 6), child: WhatsAppIcon(size: 17)), onTap: () => _open('https://wa.me/91$phone'))),
                const SizedBox(width: 8),
                SizedBox(width: 44, child: ProfileActionBtn(wi: WI.share, label: '', semantic: t('Share profile'), onTap: () => _open('https://wa.me/?text=${Uri.encodeComponent(shareText)}'))),
              ]),
            ]),
          ),
          if (site.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: GestureDetector(
                onTap: () => _open(site),
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(22)),
                  child: Text(t('Visit website'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
                ),
              ),
            ),
          const SizedBox(height: 10),
          // reviews: the same one line as on a member's page, though the contact has not joined
          Container(
            decoration: BoxDecoration(border: Border.all(color: p.border), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                child: Row(children: [
                  Text(count > 0 ? avg.toStringAsFixed(1) : '–', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  Stars(value: avg, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(t(count == 1 ? '{n} review' : '{n} reviews', {'n': count}), style: TextStyle(color: p.muted, fontSize: 12.5))),
                  if (!_writing)
                    GestureDetector(
                      onTap: () => setState(() => _writing = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(20)),
                        child: Text(t(mine != null ? 'Change your review' : 'Review'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
                      ),
                    ),
                ]),
              ),
              if (_writing) ...[
                Divider(height: 1, color: p.border),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t('Review {name}', {'name': '${c['name']}'}), style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Row(children: [
                      for (var k = 1; k <= 5; k++)
                        GestureDetector(onTap: () => setState(() => _stars = k), child: Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.star_rounded, size: 34, color: k <= _stars ? kStar : p.text.withValues(alpha: .15)))),
                    ]),
                    const SizedBox(height: 6),
                    TextField(controller: _text, maxLength: 500, minLines: 2, maxLines: 4, decoration: InputDecoration(hintText: t('What was it like to work with them? (optional)'), border: const OutlineInputBorder())),
                    Row(children: [
                      GoldButton(label: t('Post review'), height: 40, loading: _busy, onPressed: _save),
                      const SizedBox(width: 8),
                      TextButton(onPressed: () => setState(() => _writing = false), child: Text(t('Cancel'))),
                      const Spacer(),
                      if (mine != null) TextButton(onPressed: _delete, child: Text(t('Delete'), style: TextStyle(color: p.danger))),
                    ]),
                  ]),
                ),
              ],
              Divider(height: 1, color: p.border),
              if (list.isEmpty) Padding(padding: const EdgeInsets.all(14), child: Text(t('No reviews yet. Be the first to review.'), style: TextStyle(color: p.muted))),
              for (final r in list)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Avatar(name: '${(r['author'] as Map)['company'] ?? ''}'.isNotEmpty ? '${(r['author'] as Map)['company']}' : '${(r['author'] as Map)['name']}', photoUrl: (r['author'] as Map)['photoURL'] as String?, size: 30),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${(r['author'] as Map)['company'] ?? ''}'.isNotEmpty ? '${(r['author'] as Map)['company']}' : '${(r['author'] as Map)['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                      Stars(value: ((r['rating'] as num?) ?? 0).toDouble(), size: 14),
                    ]),
                    if ('${r['text'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${r['text']}', style: const TextStyle(height: 1.4))),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 16),
          // the tab strip of a member's page, with the one tab there is
          Container(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              const WIcon(WI.phone, size: 16, color: null),
              const SizedBox(width: 8),
              Text(t('Contact'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(border: Border.all(color: p.border), borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              _row(p, const Icon(Icons.call_rounded, size: 19, color: Color(0xFF1E9E5A)), t('Call'), '+91 $phone', 'tel:+91$phone'),
              Divider(height: 1, color: p.border),
              _row(p, const WhatsAppIcon(size: 22), 'WhatsApp', null, 'https://wa.me/91$phone'),
              if (rating != null || maps.isNotEmpty) ...[
                Divider(height: 1, color: p.border),
                _row(p, const Text('G', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF4285F4), fontSize: 17)), 'Google Business',
                    rating != null ? '★ ${rating.toStringAsFixed(1)}${c['ratings'] is num ? ' (${c['ratings']})' : ''}' : null, maps.isNotEmpty ? maps : 'https://www.google.com/search?q=${Uri.encodeComponent('${c['name']} $address')}'),
              ],
              if (address.isNotEmpty) ...[
                Divider(height: 1, color: p.border),
                _row(p, const Icon(Icons.place_rounded, size: 19, color: kStar), t('Directions'), address, maps.isNotEmpty ? maps : 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}'),
              ],
              if (site.isNotEmpty) ...[
                Divider(height: 1, color: p.border),
                _row(p, Icon(Icons.language_rounded, size: 19, color: p.muted), t('Website'), site.replaceFirst(RegExp(r'^https?://'), ''), site),
              ],
            ]),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => _open('https://webweb.ai/login'),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: kGold.withValues(alpha: .12), border: Border.all(color: kGold.withValues(alpha: .6)), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [Expanded(child: Text(t('Is this your business? Join WEBWEB'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)))]),
            ),
          ),
        ]),
      ),
    ]);
  }
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../auth_provider.dart';
import '../config.dart';
import '../i18n.dart';
import '../share_log.dart';
import '../theme.dart';
import '../widgets.dart';

/// The intro card templates (web lib/intro-cards.ts): id, name and the two colours of its swatch.
const kIntroCardTemplates = <(String, String, int, int)>[
  ('sunrise', 'Sunrise', 0xFFFFE84D, 0xFFFFB800),
  ('ink', 'Ink', 0xFF1E1E1E, 0xFF1E1E1E),
  ('cream', 'Cream', 0xFFF4ECD0, 0xFFFDFCF8),
  ('skyq', 'SkyQ', 0xFF0575E6, 0xFF34A853),
  ('indigo', 'Indigo', 0xFF1F2D7A, 0xFF162257),
  ('gold-split', 'Gold block', 0xFFFFE84D, 0xFFFDFCF8),
  ('indigo-split', 'Indigo block', 0xFF1F2D7A, 0xFFFFFFFF),
  ('ink-split', 'Ink block', 0xFF1E1E1E, 0xFFFDFCF8),
  ('photo-ink', 'Photo, ink', 0xFF7A7A7A, 0xFF1E1E1E),
  ('photo-indigo', 'Photo, indigo', 0xFF8A97D8, 0xFF1F2D7A),
  ('midnight-gold', 'Midnight gold', 0xFF1C2147, 0xFFD9A400),
  ('emerald', 'Emerald', 0xFF0F5A45, 0xFF06261D),
  ('plum', 'Plum', 0xFF4A1D5E, 0xFF1A0826),
  ('champagne', 'Champagne', 0xFFF8E7B0, 0xFFFFFDF6),
  ('noir-gold', 'Noir gold', 0xFFFFE84D, 0xFF101010),
  ('photo-emerald', 'Photo, emerald', 0xFF7FB59F, 0xFF0A3D2F),
];


/// The 30-second intro card: the picture the server draws (/intro-card/<handle>) with the member's photo, what they do
/// and a QR to their page. Pick a style, then share it as an update (it joins the circles for 24 hours) or as an image
/// to WhatsApp status, Instagram or print. Opened from the account menu.
class IntroCardScreen extends StatefulWidget {
  const IntroCardScreen({super.key});
  @override
  State<IntroCardScreen> createState() => _IntroCardScreenState();
}

class _IntroCardScreenState extends State<IntroCardScreen> {
  String _tpl = kIntroCardTemplates.first.$1;
  bool _busyUpdate = false, _busyImage = false;

  String get _handle => context.read<AuthProvider>().profile?.handle ?? '';
  // r: this visit, so a changed photo or detail is drawn afresh and never an older copy kept on the way
  final _visit = DateTime.now().millisecondsSinceEpoch;
  String _cardUrl(String tpl) => '$siteUrl/intro-card/$_handle?t=$tpl&r=$_visit';
  String get _url => _cardUrl(_tpl);

  Future<Uint8List> _png() async {
    final res = await http.get(Uri.parse(_url)).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw 'no card';
    return res.bodyBytes;
  }

  Future<void> _shareImage() async {
    final api = context.read<AuthProvider>().api;
    setState(() => _busyImage = true);
    try {
      final bytes = await _png();
      final name = 'webweb-$_handle-intro-card.png';
      final r = await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'image/png', name: name)],
        fileNameOverrides: [name],
        text: '$siteUrl/$_handle',
      ));
      if (r.status != ShareResultStatus.dismissed) logShare(api, 'profile', _handle, channel: 'card');
    } catch (_) {
      if (mounted) toast(context, t('Could not create the card'), error: true);
    } finally {
      if (mounted) setState(() => _busyImage = false);
    }
  }

  Future<void> _shareUpdate() async {
    final api = context.read<AuthProvider>().api;
    setState(() => _busyUpdate = true);
    try {
      final bytes = await _png();
      final url = await api.uploadImage(bytes, 'intro-card-$_tpl.png');
      await api.post('/updates', {'imageUrl': url});
      if (mounted) {
        toast(context, t('Posted as an update'));
        Navigator.maybePop(context);
      }
    } catch (_) {
      if (mounted) toast(context, t('Could not post the update'), error: true);
    } finally {
      if (mounted) setState(() => _busyUpdate = false);
    }
  }

  Widget _round(Pal p, {required WI wi, required String label, required bool busy, required bool gold, required VoidCallback? onTap}) => Semantics(
        button: true,
        label: label,
        child: Tooltip(
          message: label,
          child: Material(
            color: Colors.transparent,
            child: Ink(
              width: 40,
              height: 40,
              decoration: BoxDecoration(gradient: gold ? kGoldGradient : null, color: gold ? null : p.chip, border: gold ? null : Border.all(color: p.border), shape: BoxShape.circle),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: Center(child: busy ? const Spinner(size: 18) : WIcon(wi, size: 20, color: gold ? kInk : p.text, strokeWidth: 1.9, still: true)),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final idle = !_busyUpdate && !_busyImage;
    // the two ways to share sit in the page's header, top right
    return SubPage(
      title: t('30-second intro card'),
      actions: [
        _round(p, wi: WI.updates, label: t('Share as update'), busy: _busyUpdate, gold: true, onTap: idle ? _shareUpdate : null),
        const SizedBox(width: 8),
        _round(p, wi: WI.share, label: t('Share image'), busy: _busyImage, gold: false, onTap: idle ? _shareImage : null),
      ],
      body: _content(p),
    );
  }

  Widget _content(Pal p) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 110),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('Pick a style, then share your card as an update or as an image.'), style: TextStyle(fontSize: 13.5, color: p.muted)),
        const SizedBox(height: 14),
        // the card, centred
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: Image.network(
                  _url,
                  key: ValueKey(_url),
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, prog) => prog == null ? child : Container(color: p.chip, alignment: Alignment.center, child: const Spinner(size: 24)),
                  errorBuilder: (_, __, ___) => Container(color: p.chip, alignment: Alignment.center, padding: const EdgeInsets.all(16), child: Text(t('Could not create the card'), textAlign: TextAlign.center)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('${t('Style')} · ${kIntroCardTemplates.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted)),
        const SizedBox(height: 8),
        // every template, drawn with your own details, in one row that slides sideways: tap one to choose it
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kIntroCardTemplates.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, k) {
              final tp = kIntroCardTemplates[k];
              final on = tp.$1 == _tpl;
              final swatch = DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(tp.$3), Color(tp.$3), Color(tp.$4), Color(tp.$4)], stops: const [0, .5, .5, 1])));
              return Semantics(
                button: true,
                selected: on,
                label: '${t('Template')}: ${tp.$2}',
                child: GestureDetector(
                  onTap: () => setState(() => _tpl = tp.$1),
                  child: SizedBox(
                    width: 86,
                    child: Column(children: [
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.all(2.5),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: on ? kGold : p.border, width: on ? 2.5 : 1)),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox.expand(
                              child: Image.network(
                                _cardUrl(tp.$1),
                                fit: BoxFit.cover,
                                cacheWidth: 300,
                                loadingBuilder: (_, child, prog) => prog == null ? child : swatch,
                                errorBuilder: (_, __, ___) => swatch,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(tp.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: on ? FontWeight.w800 : FontWeight.w600)),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        Text(t('The QR on the card opens your WEBWEB AI page. An update stays for 24 hours.'), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.muted)),
      ]),
    );
  }
}

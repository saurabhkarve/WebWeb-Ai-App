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
  String get _url => '$siteUrl/intro-card/$_handle?t=$_tpl';

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

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 110),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('Pick a style, then share your card as an update or as an image.'), style: TextStyle(fontSize: 13.5, color: p.muted)),
        const SizedBox(height: 14),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: Image.network(
                  _url,
                  key: ValueKey(_tpl),
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
        // every template, drawn with your own details: tap one to choose it
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: kIntroCardTemplates.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 3 / 4.6),
          itemBuilder: (_, k) {
            final tp = kIntroCardTemplates[k];
            final on = tp.$1 == _tpl;
            return Semantics(
              button: true,
              selected: on,
              label: '${t('Template')}: ${tp.$2}',
              child: GestureDetector(
                onTap: () => setState(() => _tpl = tp.$1),
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
                            '$siteUrl/intro-card/$_handle?t=${tp.$1}',
                            fit: BoxFit.cover,
                            cacheWidth: 300,
                            loadingBuilder: (_, child, prog) => prog == null
                                ? child
                                : DecoratedBox(
                                    decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(tp.$3), Color(tp.$3), Color(tp.$4), Color(tp.$4)], stops: const [0, .5, .5, 1]))),
                            errorBuilder: (_, __, ___) => DecoratedBox(
                                decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(tp.$3), Color(tp.$3), Color(tp.$4), Color(tp.$4)], stops: const [0, .5, .5, 1]))),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(tp.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: on ? FontWeight.w800 : FontWeight.w600)),
                ]),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        GoldButton(label: t('Share as update'), wi: WI.updates, height: 48, loading: _busyUpdate, onPressed: _busyUpdate || _busyImage ? null : _shareUpdate),
        const SizedBox(height: 8),
        GoldButton(label: t('Share image'), wi: WI.share, outlined: true, height: 48, loading: _busyImage, onPressed: _busyUpdate || _busyImage ? null : _shareImage),
        const SizedBox(height: 10),
        Text(t('The QR on the card opens your WEBWEB AI page. An update stays for 24 hours.'), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.muted)),
      ]),
    );
  }
}

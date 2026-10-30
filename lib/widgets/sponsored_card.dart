import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../i18n.dart';
import '../links.dart';
import '../screens/profile.dart';
import '../theme.dart';
import '../widgets.dart';

/// An ad pushed from Admin > Ads (GET /feed/ads?placement=home|updates).
class FeedAd {
  final String id, headline, ctaUrl;
  final String? body, imageUrl, ctaLabel, advertiserHandle, advertiserPhoto;
  final String advertiserName;
  final bool advertiserVerified;
  FeedAd.fromJson(Map j)
      : id = '${j['id']}',
        headline = '${j['headline'] ?? ''}',
        body = j['body'] as String?,
        imageUrl = j['imageUrl'] as String?,
        ctaUrl = '${(j['cta'] as Map?)?['url'] ?? ''}',
        ctaLabel = (j['cta'] as Map?)?['label'] as String?,
        advertiserName = '${(j['advertiser'] as Map?)?['name'] ?? ''}',
        advertiserHandle = (j['advertiser'] as Map?)?['handle'] as String?,
        advertiserPhoto = (j['advertiser'] as Map?)?['photoURL'] as String?,
        advertiserVerified = (j['advertiser'] as Map?)?['verified'] == true;
}

/// Always labelled "Ad", with a menu to see why it is shown or hide it; counts an impression once it has been on screen.
class SponsoredCard extends StatefulWidget {
  final FeedAd ad;
  const SponsoredCard({super.key, required this.ad});
  @override
  State<SponsoredCard> createState() => _SponsoredCardState();
}

class _SponsoredCardState extends State<SponsoredCard> {
  bool _why = false, _hidden = false;
  Timer? _seen;

  @override
  void initState() {
    super.initState();
    // on screen for a second counts as seen
    _seen = Timer(const Duration(seconds: 1), () => _track('impression'));
  }

  @override
  void dispose() {
    _seen?.cancel();
    super.dispose();
  }

  void _track(String event) {
    if (!mounted) return;
    context.read<AuthProvider>().api.post('/feed/ads/${widget.ad.id}/event', {'event': event}).catchError((_) {});
  }

  void _menu() {
    final p = Pal.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.card,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(t('Why am I seeing this?'), style: const TextStyle(fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(ctx);
              setState(() => _why = true);
            },
          ),
          ListTile(
            title: Text(t('Hide this ad'), style: const TextStyle(fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(ctx);
              _track('hide');
              setState(() => _hidden = true);
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final ad = widget.ad;
    if (_hidden) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(t('Ad hidden'), style: TextStyle(fontSize: 14, color: p.muted)),
          GestureDetector(onTap: () => setState(() => _hidden = false), child: Text(t('Undo'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.link))),
        ]),
      );
    }
    final name = Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(child: Text(ad.advertiserName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
      if (ad.advertiserVerified) ...[const SizedBox(width: 6), const VerifiedBadge(level: 1)],
    ]);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Avatar(name: ad.advertiserName, photoUrl: ad.advertiserPhoto, size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              (ad.advertiserHandle ?? '').isNotEmpty
                  ? GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: ad.advertiserHandle!))), child: name)
                  : name,
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: p.text.withValues(alpha: .25))),
                child: Text(t('Ad').toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .5, color: p.text.withValues(alpha: .7))),
              ),
            ]),
          ),
          IconButton(onPressed: _menu, icon: Icon(Icons.more_horiz, color: p.muted), tooltip: t('More')),
        ]),
        if (_why)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(12)),
            child: Text(t('This is a paid ad. The business chose to reach members like you. Ads are always marked Ad, and your number is never shared with them.'), style: TextStyle(fontSize: 12, height: 1.4, color: p.muted)),
          ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () {
            _track('click');
            if (ad.ctaUrl.isNotEmpty) openExternal(context, ad.ctaUrl);
          },
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.border),
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [p.text.withValues(alpha: .06), p.text.withValues(alpha: 0)]),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if ((ad.imageUrl ?? '').isNotEmpty) AspectRatio(aspectRatio: 1.91, child: Image.network(ad.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink())),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(ad.headline, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.25)),
                  if ((ad.body ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(ad.body!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: p.muted))),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: Text(Uri.tryParse(ad.ctaUrl)?.host.replaceFirst('www.', '') ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted))),
                    const SizedBox(width: 12),
                    Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(18)),
                      child: Text((ad.ctaLabel ?? '').isNotEmpty ? ad.ctaLabel! : t('Learn more'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: kInk)),
                    ),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// An ad in the Updates strip: a circle like a business's, tagged "Ad"; tapping it shows the ad (the same card as in the feed).
class AdCircle extends StatefulWidget {
  final FeedAd ad;
  const AdCircle({super.key, required this.ad});
  @override
  State<AdCircle> createState() => _AdCircleState();
}

class _AdCircleState extends State<AdCircle> {
  Timer? _seen;

  @override
  void initState() {
    super.initState();
    // on screen for a second counts as seen
    _seen = Timer(const Duration(seconds: 1), () {
      if (mounted) context.read<AuthProvider>().api.post('/feed/ads/${widget.ad.id}/event', {'event': 'impression'}).catchError((_) {});
    });
  }

  @override
  void dispose() {
    _seen?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final ad = widget.ad;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: p.canvas,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 16), child: SponsoredCard(ad: ad))),
      ),
      child: Container(
        width: 84,
        margin: const EdgeInsets.only(right: 12),
        child: Column(children: [
          Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            Container(
              width: 74,
              height: 74,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(shape: BoxShape.circle, color: p.border),
              child: Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(shape: BoxShape.circle, color: p.canvas),
                child: ClipOval(child: Avatar(name: ad.advertiserName, photoUrl: ad.advertiserPhoto, size: 64)),
              ),
            ),
            Positioned(
              bottom: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: p.canvas, borderRadius: BorderRadius.circular(6), border: Border.all(color: p.text.withValues(alpha: .25))),
                child: Text(t('Ad').toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: .5, color: p.text.withValues(alpha: .7))),
              ),
            ),
          ]),
          const SizedBox(height: 7),
          Text(ad.advertiserName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }
}

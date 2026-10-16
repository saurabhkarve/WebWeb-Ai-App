import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../auth_provider.dart';
import '../models.dart';
import '../screens/contact_picker.dart';
import '../screens/profile.dart';
import '../screens/talk.dart';
import '../theme.dart';
import '../widgets.dart';

/// One business and what it offers, shown inside the Connect feed after every third ask
/// (web/src/components/catalog-strip.tsx).
class CatalogStrip extends StatelessWidget {
  final CatalogGroup group;
  const CatalogStrip({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final o = group.owner;
    final name = o.userType == 'entrepreneur' && o.company.isNotEmpty ? o.company : o.name;
    void openOwner() => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: o.handle)));
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border.withValues(alpha: .6)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: openOwner,
          child: Row(children: [
            Avatar(name: name, photoUrl: o.photoUrl, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5))),
                  if (group.verification != 'none') const VerifiedBadge(),
                ]),
                Text('@${o.handle}${group.location == null ? '' : ' · ${group.location}'}', overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w500)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(20)),
              child: Text('${group.total} offered', style: TextStyle(color: p.muted, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 268,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final it in group.items) _ItemCard(item: it, owner: o, ownerName: name),
            if (group.total > group.items.length)
              GestureDetector(
                onTap: openOwner,
                child: Container(
                  width: 110,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
                  child: const Text('View all', style: TextStyle(color: kGold, fontWeight: FontWeight.w700)),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// A catalog item with the same controls an ask has: React, Refer, Save, plus Enquire.
class _ItemCard extends StatefulWidget {
  final FeedProduct item;
  final Peer owner;
  final String ownerName;
  const _ItemCard({required this.item, required this.owner, required this.ownerName});
  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  FeedProduct get it => widget.item;
  Api get _api => context.read<AuthProvider>().api;
  bool _busy = false;

  Future<void> _react() async {
    final on = it.myReaction == null;
    setState(() {
      it.myReaction = on ? 'heart' : null;
      it.reactionsCount += on ? 1 : -1;
    });
    try {
      on ? await _api.post('/products/${it.id}/react', {'type': 'heart'}) : await _api.delete('/products/${it.id}/react');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        it.myReaction = on ? null : 'heart';
        it.reactionsCount += on ? -1 : 1;
      });
      toast(context, '$e', error: true);
    }
  }

  Future<void> _save() async {
    final on = !it.bookmarked;
    setState(() => it.bookmarked = on);
    try {
      on ? await _api.post('/products/${it.id}/bookmark', {}) : await _api.delete('/products/${it.id}/bookmark');
      if (mounted) toast(context, on ? 'Saved' : 'Removed from saved');
    } catch (e) {
      if (!mounted) return;
      setState(() => it.bookmarked = !on);
      toast(context, '$e', error: true);
    }
  }

  /// Refer people from the phone book who may want this item (max 5 per item, like asks).
  Future<void> _refer() async {
    final picked = await Navigator.push<List<PickedContact>>(context, MaterialPageRoute(builder: (_) => ContactPicker(askerName: widget.ownerName)));
    if (picked == null || picked.isEmpty || !mounted) return;
    var ok = 0;
    String? err;
    for (final c in picked) {
      try {
        await _api.post('/products/${it.id}/refer', {'name': c.name, 'phone': c.phone});
        ok++;
      } catch (e) {
        err = '$e';
      }
    }
    if (!mounted) return;
    if (ok > 0) setState(() => it.referralsCount += ok);
    toast(context, ok > 0 ? '$ok contact${ok == 1 ? '' : 's'} referred to ${widget.ownerName}' : (err ?? 'Could not refer'), error: ok == 0);
  }

  /// Opens the chat with a ready-made enquiry about this item.
  Future<void> _enquire() async {
    setState(() => _busy = true);
    try {
      final chatId = (await _api.post('/chats', {'userId': widget.owner.uid}) as Map)['id'] as String;
      await _api.post('/chats/$chatId/messages', {
        'text': 'Hi, I am interested in "${it.name}"${it.price == null ? '' : ' (${it.price})'}.',
        'attachment': {'type': 'item', 'name': it.name, 'kind': it.kind, if (it.price != null) 'price': it.price, if (it.imageUrl != null) 'imageUrl': it.imageUrl},
      });
      _api.post('/products/${it.id}/enquire', {}).catchError((_) => null);
      it.enquiriesCount++;
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatThread(chatId: chatId, peer: widget.owner)));
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      width: 170,
      margin: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onDoubleTap: it.myReaction == null ? _react : null,
          child: SizedBox(
            height: 112,
            width: double.infinity,
            child: it.imageUrl == null
                ? Container(color: p.chip, child: Icon(it.kind == 'service' ? Icons.handyman_outlined : Icons.inventory_2_outlined, color: p.muted, size: 34))
                : Image.network(mediaUrl(it.imageUrl!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: p.chip)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(it.price ?? (it.kind == 'service' ? 'Service' : 'Product'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
        ),
        const Spacer(),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _icon(it.myReaction == null ? Icons.favorite_border : Icons.favorite, it.reactionsCount, it.myReaction != null ? Colors.pinkAccent : p.muted, _react),
          _icon(Icons.person_add_alt, it.referralsCount, p.muted, _refer),
          _icon(it.bookmarked ? Icons.bookmark : Icons.bookmark_border, 0, it.bookmarked ? kGold : p.muted, _save),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: SizedBox(width: double.infinity, height: 34, child: GoldButton(label: 'Enquire', loading: _busy, onPressed: _enquire)),
        ),
      ]),
    );
  }

  Widget _icon(IconData icon, int count, Color color, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 19, color: color),
            if (count > 0) ...[const SizedBox(width: 3), Text('$count', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))],
          ]),
        ),
      );
}

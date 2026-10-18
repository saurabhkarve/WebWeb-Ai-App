import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../auth_provider.dart';
import '../i18n.dart';
import '../models.dart';
import '../screens/contact_picker.dart';
import '../screens/profile.dart';
import '../screens/talk.dart';
import '../theme.dart';
import '../widgets.dart';
import 'reaction_picker.dart';

/// One business and what it offers, shown inside the Connect feed (web catalog-strip.tsx).
class CatalogStrip extends StatelessWidget {
  final CatalogGroup group;
  const CatalogStrip({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final o = group.owner;
    final name = displayName(o.userType, o.name, o.company);
    void openOwner() => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: o.handle)));
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: openOwner,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Avatar(name: name, photoUrl: o.photoUrl, size: 44, type: o.userType),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.25))),
                    const SizedBox(width: 6),
                    VerifiedBadge(level: group.verification),
                  ]),
                  Text('@${o.handle}${(group.location ?? '').isEmpty ? '' : ' · ${group.location}'}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted, height: 1.25)),
                ]),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  WIcon(WI.business, size: 12, strokeWidth: 2, color: p.muted),
                  const SizedBox(width: 4),
                  Text(t('{n} offered', {'n': group.total}), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.muted)),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final it in group.items) ...[_ItemCard(item: it, owner: o, ownerName: name, openOwner: openOwner), const SizedBox(width: 12)],
              if (group.total > group.items.length)
                GestureDetector(
                  onTap: openOwner,
                  child: Container(
                    width: 112,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
                    child: Text(t('View all'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.link)),
                  ),
                ),
            ]),
          ),
        ),
        // border-b inside the feed's gutter
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Container(height: 1, color: p.border)),
      ]),
    );
  }
}

/// A catalog item with the same controls an ask has (React, Refer, Repost, Reply, Share, Save) plus Enquire now.
/// Tap opens the business; double tap gives the item a thumbs up.
class _ItemCard extends StatefulWidget {
  final FeedProduct item;
  final Peer owner;
  final String ownerName;
  final VoidCallback openOwner;
  const _ItemCard({required this.item, required this.owner, required this.ownerName, required this.openOwner});
  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> with SingleTickerProviderStateMixin {
  FeedProduct get it => widget.item;
  Api get _api => context.read<AuthProvider>().api;
  late final AnimationController _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
  bool _busy = false;

  String get _defaultText => '${t('Hi, I am interested in')} "${it.name}"${(it.price ?? '').isEmpty ? '' : ' (${it.price})'}.';

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  Future<void> _react(String? next) async {
    final prev = it.myReaction;
    int delta(String? a, String? b) => a != null && b == null ? 1 : (a == null && b != null ? -1 : 0);
    setState(() {
      it.myReaction = next;
      it.reactionsCount = (it.reactionsCount + delta(next, prev)).clamp(0, 1 << 30);
    });
    try {
      next != null ? await _api.post('/products/${it.id}/react', {'type': next}) : await _api.delete('/products/${it.id}/react');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        it.myReaction = prev;
        it.reactionsCount = (it.reactionsCount - delta(next, prev)).clamp(0, 1 << 30);
      });
    }
  }

  void _doubleTap() {
    _burst.forward(from: 0);
    if (it.myReaction == null) _react('thumbs');
  }

  Future<void> _toggleRepost() async {
    final on = !it.reposted;
    setState(() {
      it.reposted = on;
      it.repostsCount = (it.repostsCount + (on ? 1 : -1)).clamp(0, 1 << 30);
    });
    try {
      on ? await _api.post('/products/${it.id}/repost', {}) : await _api.delete('/products/${it.id}/repost');
      if (mounted) toast(context, t(on ? 'Reposted to your page' : 'Repost removed'));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        it.reposted = !on;
        it.repostsCount = (it.repostsCount + (on ? -1 : 1)).clamp(0, 1 << 30);
      });
    }
  }

  Future<void> _toggleSave() async {
    final on = !it.bookmarked;
    setState(() => it.bookmarked = on);
    try {
      on ? await _api.post('/products/${it.id}/bookmark', {}) : await _api.delete('/products/${it.id}/bookmark');
      if (mounted) toast(context, t(on ? 'Saved' : 'Removed from saved'));
    } catch (_) {
      if (mounted) setState(() => it.bookmarked = !on);
    }
  }

  /// Refer people from the phone book who may want this item (max 5, like asks).
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
        err = e is ApiException ? e.message : '$e';
      }
    }
    if (!mounted) return;
    if (ok > 0) setState(() => it.referralsCount += ok);
    toast(context, ok > 0 ? t('Referral sent') : (err ?? t('Could not refer')), error: ok == 0);
  }

  /// Sends [text] about this item to the owner; [open] goes to the chat, else a short note.
  Future<void> _send(String text, bool open) async {
    setState(() => _busy = true);
    try {
      final chatId = (await _api.post('/chats', {'userId': widget.owner.uid}) as Map)['id'] as String;
      await _api.post('/chats/$chatId/messages', {
        'text': text,
        'attachment': {'type': 'item', 'name': it.name, 'kind': it.kind, if (it.price != null) 'price': it.price, if (it.imageUrl != null) 'imageUrl': it.imageUrl},
      });
      _api.post('/products/${it.id}/enquire', {}).catchError((_) => null);
      setState(() => it.enquiriesCount++);
      if (!mounted) return;
      if (open) {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatThread(chatId: chatId, peer: widget.owner)));
      } else {
        toast(context, t('Message sent'));
      }
    } catch (_) {
      if (mounted) toast(context, t('Could not open chat'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reply() async {
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.of(context).canvas,
      barrierColor: kInk.withValues(alpha: .6),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _ReplySheet(title: it.name, owner: widget.ownerName, initial: _defaultText),
    );
    if (text != null && mounted) _send(text, false);
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final typeIcon = it.kind == 'service' ? WI.service : WI.box;
    const emerald = Color(0xFF059669);

    Widget action({required Widget icon, int count = 0, required String label, required Color color, VoidCallback? onTap}) {
      final content = Container(
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: 20,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              icon,
              if (count > 0) ...[const SizedBox(width: 4), Text('$count', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color))],
            ]),
          ),
          const SizedBox(height: 2),
          Text(t(label), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, height: 1, color: color)),
        ]),
      );
      return Expanded(child: onTap == null ? content : InkWell(borderRadius: BorderRadius.circular(8), onTap: onTap, child: content));
    }

    Widget overlayPill(Widget child) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: p.canvas.withValues(alpha: .9),
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1))],
          ),
          child: child,
        );

    return Container(
      width: 240,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(fit: StackFit.expand, children: [
            GestureDetector(
              onTap: widget.openOwner,
              onDoubleTap: _doubleTap,
              child: (it.imageUrl ?? '').isNotEmpty
                  ? NetImg(it.imageUrl!, fit: BoxFit.cover)
                  : Container(color: p.chip, alignment: Alignment.center, child: WIcon(typeIcon, size: 32, color: p.muted)),
            ),
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _burst,
                builder: (_, __) {
                  if (!_burst.isAnimating) return const SizedBox.shrink();
                  final v = _burst.value;
                  final scale = v < .25 ? .4 + .85 * (v / .25) : (v < .6 ? 1.25 - .25 * ((v - .25) / .35) : 1 + .1 * ((v - .6) / .4));
                  final opacity = v < .25 ? v / .25 : (v < .6 ? 1.0 : 1 - (v - .6) / .4);
                  return Center(
                    child: Transform.translate(
                      offset: Offset(0, v < .6 ? 0 : -14 * ((v - .6) / .4)),
                      child: Opacity(opacity: opacity.clamp(0.0, 1.0), child: Transform.scale(scale: scale, child: const Text('👍', style: TextStyle(fontSize: 36)))),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: IgnorePointer(
                child: overlayPill(Row(mainAxisSize: MainAxisSize.min, children: [
                  WIcon(typeIcon, size: 10, strokeWidth: 2.4, color: p.text),
                  const SizedBox(width: 4),
                  Text(t(it.kind == 'service' ? 'Service' : 'Product'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, height: 1, color: p.text)),
                ])),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: GestureDetector(
                onTap: _toggleSave,
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.canvas.withValues(alpha: .9),
                    boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1))],
                  ),
                  child: WIcon(WI.bookmark, size: 18, fill: it.bookmarked, color: it.bookmarked ? p.link : p.muted),
                ),
              ),
            ),
            if ((it.price ?? '').isNotEmpty)
              Positioned(
                right: 8,
                bottom: 8,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: kGoldGradient,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1))],
                    ),
                    child: Text(it.price!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1, color: kInk)),
                  ),
                ),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.openOwner,
              onDoubleTap: _doubleTap,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.25)),
                const SizedBox(height: 2),
                SizedBox(
                  height: 32,
                  child: Text(it.description ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, height: 1.33, color: p.muted)),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            GoldButton(label: t('Enquire now'), height: 32, loading: _busy, onPressed: () => _send(_defaultText, true)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: ReactionPicker(
                  quick: true,
                  value: it.myReaction,
                  onChange: _react,
                  trigger: (_) => Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    alignment: Alignment.center,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(
                        height: 20,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          it.myReaction != null
                              ? SizedBox(width: 20, height: 20, child: Center(child: ReactionGlyph(it.myReaction!, size: 14)))
                              : WIcon(WI.heart, size: 20, color: p.muted),
                          if (it.reactionsCount > 0) ...[
                            const SizedBox(width: 4),
                            Text('${it.reactionsCount}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: it.myReaction != null ? p.text : p.muted)),
                          ],
                        ]),
                      ),
                      const SizedBox(height: 2),
                      Text(t('React'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, height: 1, color: it.myReaction != null ? p.text : p.muted)),
                    ]),
                  ),
                ),
              ),
              action(icon: WIcon(WI.refer, size: 20, color: p.muted), count: it.referralsCount, label: 'Refer', color: p.muted, onTap: _refer),
              action(
                icon: WIcon(WI.repost, size: 20, color: it.reposted ? emerald : p.muted),
                count: it.repostsCount,
                label: it.reposted ? 'Reposted' : 'Repost',
                color: it.reposted ? emerald : p.muted,
                onTap: _toggleRepost,
              ),
              action(icon: WIcon(WI.reply, size: 20, color: p.muted), count: it.enquiriesCount, label: 'Reply', color: p.muted, onTap: _reply),
              action(
                icon: WIcon(WI.share, size: 20, color: p.muted),
                label: 'Share',
                color: p.muted,
                onTap: () => showShareItemSheetFor(context, it, handle: widget.owner.handle, business: widget.ownerName),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Message the business about one item, prefilled with an enquiry (web ReplySheet).
class _ReplySheet extends StatefulWidget {
  final String title, owner, initial;
  const _ReplySheet({required this.title, required this.owner, required this.initial});
  @override
  State<_ReplySheet> createState() => _ReplySheetState();
}

class _ReplySheetState extends State<_ReplySheet> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          WIcon(WI.reply, size: 20, color: p.text),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          GestureDetector(onTap: () => Navigator.pop(context), child: WIcon(WI.close, size: 24, color: p.text)),
        ]),
        const SizedBox(height: 12),
        Text(t('Message {name} about this item.', {'name': widget.owner}), style: TextStyle(fontSize: 14, color: p.muted)),
        const SizedBox(height: 8),
        AppField(controller: _text, maxLines: 4, maxLength: 500, autofocus: true, caps: TextCapitalization.sentences, onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        GoldButton(label: t('Send message'), onPressed: _text.text.trim().length < 2 ? null : () => Navigator.pop(context, _text.text.trim())),
      ]),
    );
  }
}

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import '../auth_provider.dart';
import '../models.dart';
import '../screens/contact_picker.dart';
import '../screens/post_detail.dart';
import '../screens/profile.dart';
import '../theme.dart';
import '../widgets.dart';
import 'image_grid.dart';

/// Feed row for an ask ("requirement") or an update, same layout as the web PostCard:
/// who + why you see it, what is needed, the essentials as chips, a compact response log, then the actions.
class PostCard extends StatefulWidget {
  final Post post;
  final VoidCallback? onChanged;
  /// Detail page mode: full text, no navigation on tap, and Reply calls [onReply] (opens the respond sheet).
  final bool detail;
  final VoidCallback? onReply;
  const PostCard({super.key, required this.post, this.onChanged, this.detail = false, this.onReply});
  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late Post post = widget.post;

  @override
  void didUpdateWidget(covariant PostCard old) {
    super.didUpdateWidget(old);
    if (old.post.id != widget.post.id) post = widget.post;
  }

  Api get _api => context.read<AuthProvider>().api;
  bool get _isOwner => context.read<AuthProvider>().profile?.uid == post.authorUid;

  void _openAuthor() {
    if (post.authorHandle.isNotEmpty) Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: post.authorHandle)));
  }

  void _openDetail({bool reply = false}) async {
    if (widget.detail) {
      if (reply) widget.onReply?.call();
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailScreen(postId: post.id, openReply: reply)));
    widget.onChanged?.call();
  }

  // ---------- actions (optimistic, roll back on error) ----------
  Future<void> _react(String? next) async {
    final prev = post.myReaction;
    setState(() {
      post.myReaction = next;
      post.reacted = next != null;
      post.reactionsCount = (post.reactionsCount + (next != null && prev == null ? 1 : (next == null && prev != null ? -1 : 0))).clamp(0, 1 << 30);
    });
    try {
      next == null ? await _api.delete('/posts/${post.id}/react') : await _api.post('/posts/${post.id}/react', {'type': next});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        post.myReaction = prev;
        post.reacted = prev != null;
        post.reactionsCount = (post.reactionsCount + (next != null && prev == null ? -1 : (next == null && prev != null ? 1 : 0))).clamp(0, 1 << 30);
      });
      toast(context, '$e', error: true);
    }
  }

  Future<void> _pickReaction() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, mainAxisSize: MainAxisSize.min, children: [
            for (final r in kReactions)
              GestureDetector(
                onTap: () => Navigator.pop(ctx, r),
                child: Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Pal.of(ctx).chip, shape: BoxShape.circle, border: post.myReaction == r ? Border.all(color: kGold, width: 2) : null),
                  child: Text(kReactionEmoji[r]!, style: const TextStyle(fontSize: 30)),
                ),
              ),
          ]),
        ),
      ),
    );
    if (v != null) _react(v == post.myReaction ? null : v);
  }

  Future<void> _toggleRepost() async {
    final on = !post.reposted;
    setState(() {
      post.reposted = on;
      post.repostsCount = (post.repostsCount + (on ? 1 : -1)).clamp(0, 1 << 30);
    });
    try {
      on ? await _api.post('/posts/${post.id}/repost') : await _api.delete('/posts/${post.id}/repost');
      if (mounted) toast(context, on ? 'Reposted to your page' : 'Repost removed');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        post.reposted = !on;
        post.repostsCount = (post.repostsCount + (on ? -1 : 1)).clamp(0, 1 << 30);
      });
      toast(context, '$e', error: true);
    }
  }

  Future<void> _toggleBookmark() async {
    final on = !post.bookmarked;
    setState(() => post.bookmarked = on);
    try {
      on ? await _api.post('/posts/${post.id}/bookmark') : await _api.delete('/posts/${post.id}/bookmark');
      if (mounted) toast(context, on ? 'Saved' : 'Removed from saved');
    } catch (e) {
      if (!mounted) return;
      setState(() => post.bookmarked = !on);
      toast(context, '$e', error: true);
    }
  }

  /// Refer contacts from the phone book (one API call per contact, max 5 per ask).
  Future<void> _refer() async {
    final api = _api;
    int mine = 0;
    try {
      mine = ((await api.get('/app/posts/${post.id}/referrals/mine')) as List).length;
    } catch (_) {}
    final left = 5 - mine;
    if (left <= 0) return toast(context, 'You already referred 5 contacts on this ask');
    if (!mounted) return;

    List<Map<String, String>>? picked;
    if (kIsWeb) {
      picked = await _typeContact();
    } else {
      final r = await Navigator.push<List<PickedContact>>(context, MaterialPageRoute(builder: (_) => ContactPicker(askerName: post.authorName, maxSelect: left)));
      picked = r?.map((c) => c.toJson()).toList();
    }
    if (picked == null || picked.isEmpty || !mounted) return;
    var ok = 0;
    String? err;
    for (final c in picked) {
      try {
        await api.post('/posts/${post.id}/refer', {'name': c['name'], 'phone': c['phone']});
        ok++;
      } catch (e) {
        err = '$e';
      }
    }
    if (!mounted) return;
    if (ok > 0) setState(() => post.referralsCount += ok);
    toast(context, ok > 0 ? '$ok contact${ok == 1 ? '' : 's'} referred to ${post.authorName}${err != null ? ' ($err)' : ''}' : (err ?? 'Could not refer'), error: ok == 0);
  }

  Future<List<Map<String, String>>?> _typeContact() {
    final n = TextEditingController(), ph = TextEditingController();
    return showDialog<List<Map<String, String>>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Refer a contact'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          AppField(controller: n, hint: 'Name', autofocus: true),
          const SizedBox(height: 10),
          AppField(controller: ph, hint: '10-digit mobile number', keyboard: TextInputType.phone),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, [{'name': n.text.trim(), 'phone': ph.text.trim()}]), child: const Text('Send')),
        ],
      ),
    );
  }

  Future<void> _share() async {
    final title = post.title ?? post.description ?? 'a post';
    final text = 'Check this on WebWeb Ai:\n\n"$title"${post.locationPref == null ? '' : ' in ${post.locationPref}'}\n\nhttps://webweb.ai/post/${post.id}';
    try {
      await Share.share(text, subject: title);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) toast(context, 'Message copied');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final isReq = post.isRequirement;
    final urgency = post.urgency == null ? null : labelOf(kUrgencies, post.urgency);
    return Container(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border.withValues(alpha: .6)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(onTap: _openAuthor, child: Avatar(name: post.authorName, photoUrl: post.authorPhotoUrl, ring: post.authorHasUpdate)),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: _openAuthor,
              behavior: HitTestBehavior.opaque,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(post.authorName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                  const SizedBox(width: 6),
                  Text(timeAgo(post.createdAt), style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w500)),
                ]),
                Text('@${post.authorHandle} · ${post.authorCompany}', overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w500)),
              ]),
            ),
          ),
          InkWell(onTap: _share, borderRadius: BorderRadius.circular(20), child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.share_outlined, size: 18, color: p.muted))),
        ]),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _openDetail,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (isReq) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFFF4F2EC), borderRadius: BorderRadius.circular(8)),
                  child: Text((kCategoryShort[post.category] ?? 'Ask').toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF1E1E1E))),
                ),
                if ((post.matchReason ?? '').isNotEmpty) GoldTag(post.matchReason!),
              ]),
              const SizedBox(height: 8),
              Text(post.title ?? '', style: const TextStyle(fontSize: 18.5, fontWeight: FontWeight.w700, height: 1.25)),
            ],
            if ((post.description ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(post.description!, maxLines: isReq && !widget.detail ? 2 : null, overflow: isReq && !widget.detail ? TextOverflow.ellipsis : null, style: TextStyle(color: isReq ? p.muted : p.text, fontSize: 15, height: 1.35, fontWeight: FontWeight.w500)),
            ],
            ImageGrid(post.images),
            if (isReq && ((post.locationPref ?? '').isNotEmpty || (post.budget ?? '').isNotEmpty || urgency != null)) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if ((post.locationPref ?? '').isNotEmpty) InfoPill(icon: Icons.location_on_outlined, text: post.locationPref!),
                if ((post.budget ?? '').isNotEmpty) InfoPill(icon: Icons.currency_rupee, text: post.budget!.replaceAll('₹', '')),
                if (urgency != null) InfoPill(icon: Icons.schedule, text: urgency),
              ]),
            ],
          ]),
        ),
        if (isReq && !(widget.detail && _isOwner)) ResponseActivity(items: post.recentResponses, total: post.sharesCount),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _action(
            post.myReaction != null ? null : Icons.favorite_border,
            emoji: post.myReaction == null ? null : kReactionEmoji[post.myReaction],
            label: 'React',
            count: post.reactionsCount,
            active: post.myReaction != null,
            activeColor: Colors.pinkAccent,
            onTap: () => _react(post.myReaction == null ? 'heart' : null),
            onLongPress: _pickReaction,
          ),
          if (isReq && !_isOwner) _action(Icons.person_add_alt, label: 'Refer', count: post.referralsCount, onTap: _refer),
          _action(Icons.repeat, label: post.reposted ? 'Reposted' : 'Repost', count: post.repostsCount, active: post.reposted, activeColor: kGreen, onTap: _toggleRepost),
          _action(Icons.reply, label: 'Reply', count: isReq ? post.sharesCount : 0, onTap: () => _openDetail(reply: true)),
          _action(post.bookmarked ? Icons.bookmark : Icons.bookmark_border, label: post.bookmarked ? 'Saved' : 'Save', active: post.bookmarked, activeColor: kGold, onTap: _toggleBookmark),
        ]),
      ]),
    );
  }

  Widget _action(IconData? icon, {String? emoji, required String label, int count = 0, bool active = false, Color activeColor = kGold, required VoidCallback onTap, VoidCallback? onLongPress}) {
    final p = Pal.of(context);
    final c = active ? activeColor : p.muted;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (emoji != null) Text(emoji, style: const TextStyle(fontSize: 19)) else Icon(icon, size: 20, color: c),
            if (count > 0) ...[const SizedBox(width: 4), Text('$count', style: TextStyle(color: p.text, fontWeight: FontWeight.w700, fontSize: 14))],
          ]),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

/// Responses on an ask as a compact log: a count, then the latest few as "who did what, when".
/// Never shows the contact, photo or opinion itself.
class ResponseActivity extends StatelessWidget {
  final List<ResponseLog> items;
  final int total;
  const ResponseActivity({super.key, required this.items, required this.total});

  static const _verb = {'contact': 'shared a contact', 'media': 'shared a photo', 'info': 'shared an opinion'};

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    if (total == 0) {
      return Padding(padding: const EdgeInsets.only(top: 12), child: Text('Be the first to respond', style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w600)));
    }
    final more = total - items.length;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.people_outline, size: 16, color: p.muted),
          const SizedBox(width: 6),
          Text('$total ${total == 1 ? 'response' : 'responses'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
        const SizedBox(height: 6),
        Container(
          margin: const EdgeInsets.only(left: 8),
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: p.border, width: 2))),
          child: Column(children: [
            for (final r in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Avatar(name: r.name, size: 22, photoUrl: r.photoUrl),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(text: ' ${_verb[r.kind] ?? 'responded'}', style: TextStyle(color: p.muted)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  if (r.rating != null || r.reaction != null) Text('${r.rating == 1 ? '👍' : r.rating == -1 ? '👎' : ''}${r.reaction == null ? '' : kReactionEmoji[r.reaction] ?? ''}', style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 6),
                  Text(timeAgo(r.createdAt), style: TextStyle(color: p.muted, fontSize: 11.5, fontWeight: FontWeight.w500)),
                ]),
              ),
            if (more > 0) Align(alignment: Alignment.centerLeft, child: Text('+$more more', style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600))),
          ]),
        ),
      ]),
    );
  }
}

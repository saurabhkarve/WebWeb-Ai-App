import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import '../auth_provider.dart';
import '../i18n.dart';
import '../models.dart';
import '../safety.dart';
import '../screens/contact_picker.dart';
import '../screens/find.dart';
import '../screens/post_detail.dart';
import '../screens/profile.dart';
import '../screens/talk.dart' show openChat;
import '../theme.dart';
import '../widgets.dart';
import 'image_grid.dart';
import 'reaction_picker.dart';
import 'response_sheet.dart';

/// Feed row, same layout as the web PostCard (post-card.tsx): avatar on the left; who + why you see it;
/// the category chip, title and two lines of description; photos; location / budget / timing chips;
/// a compact response log; then React · Refer · Repost · Reply · Save. Tap opens the ask, double tap
/// gives it a thumbs up.
class PostCard extends StatefulWidget {
  final Post post;
  final VoidCallback? onChanged;
  /// Detail page mode: full text, no navigation on tap, and Reply calls [onReply].
  final bool detail;
  final VoidCallback? onReply;
  /// Called after the author was blocked from this card's menu (the list drops their posts).
  final VoidCallback? onBlocked;
  const PostCard({super.key, required this.post, this.onChanged, this.detail = false, this.onReply, this.onBlocked});
  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> with SingleTickerProviderStateMixin {
  late Post post = widget.post;
  late final AnimationController _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));

  @override
  void didUpdateWidget(covariant PostCard old) {
    super.didUpdateWidget(old);
    // a refreshed feed hands in new data for the same post (e.g. my reaction from another device)
    if (!identical(old.post, widget.post)) post = widget.post;
  }

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  bool get _isOwner => context.read<AuthProvider>().profile?.uid == post.authorUid;

  void _openAuthor() {
    if (post.authorHandle.isNotEmpty) Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: post.authorHandle)));
  }

  Future<void> _openDetail() async {
    if (widget.detail) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailScreen(postId: post.id)));
    widget.onChanged?.call();
  }

  void _openFind({String? location, String? budget, String? urgency}) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => FindScreen(standalone: true, initialLocation: location, initialBudget: budget, initialUrgency: urgency)),
      );

  final _actionsKey = GlobalKey<PostActionsState>();

  /// Double tap on the body: a thumbs up unless already reacted, with the burst.
  void _quickReact() {
    _burst.forward(from: 0);
    if (post.myReaction == null) _actionsKey.currentState?.react('thumbs');
  }

  /// Reply stays in the feed: asks open the respond sheet, updates start a chat with the post attached.
  Future<void> _reply() async {
    if (widget.detail && widget.onReply != null) return widget.onReply!();
    if (_isOwner) return toast(context, t('Responses to your ask are on its page'));
    if (post.isRequirement) {
      if (await showResponseSheet(context, post.id) && mounted) {
        setState(() => post = _withShares(post, post.sharesCount + 1));
        toast(context, t('Response sent'));
      }
      return;
    }
    await openChat(
      context,
      Peer(uid: post.authorUid, name: post.authorName, company: post.authorCompany, handle: post.authorHandle, userType: post.authorType, photoUrl: post.authorPhotoUrl),
      attachment: {
        'type': 'post',
        'postId': post.id,
        'kind': 'update',
        'title': (post.title ?? post.description ?? 'Update').substring(0, ((post.title ?? post.description ?? 'Update').length).clamp(0, 100)),
        if (post.images.isNotEmpty) 'imageUrl': post.images.first,
        'by': post.authorCompany.isNotEmpty ? post.authorCompany : post.authorName,
        'path': Uri.parse(post.webUrl).path,
      },
    );
  }

  static Post _withShares(Post p, int n) => Post(
        id: p.id, kind: p.kind, authorUid: p.authorUid, authorName: p.authorName, authorCompany: p.authorCompany, authorHandle: p.authorHandle,
        authorPhotoUrl: p.authorPhotoUrl, title: p.title, description: p.description, category: p.category, locationPref: p.locationPref,
        budget: p.budget, urgency: p.urgency, matchReason: p.matchReason, slug: p.slug, categoryLabel: p.categoryLabel, authorType: p.authorType,
        authorVerification: p.authorVerification, distanceM: p.distanceM, images: p.images, sharesCount: n, authorHasUpdate: p.authorHasUpdate,
        createdAt: p.createdAt, recentResponses: p.recentResponses, reactionsCount: p.reactionsCount, repostsCount: p.repostsCount,
        referralsCount: p.referralsCount, reacted: p.reacted, reposted: p.reposted, bookmarked: p.bookmarked, myReaction: p.myReaction,
      );

  Future<void> _share() async {
    try {
      await SharePlus.instance.share(ShareParams(text: post.webUrl, subject: post.title ?? 'WebWeb AI ask'));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final isAsk = post.isRequirement;
    final mine = _isOwner;
    final urgency = post.urgency == null || post.urgency!.isEmpty ? null : labelOf(kUrgencies, post.urgency);
    final isBusiness = post.authorType == 'entrepreneur';
    // phones: a smaller author photo leaves more width for the ask
    final small = MediaQuery.sizeOf(context).width < 600;
    final match = (post.matchReason ?? '').isEmpty ? null : '${post.matchReason}${post.distanceM == null ? '' : ' · ${formatDistance(post.distanceM!)}'}';

    final body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (isAsk) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            WIcon(categoryIcon(post.category), size: 12, color: p.onInk),
            const SizedBox(width: 4),
            Text(t(post.categoryText).toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0, color: p.onInk)),
          ]),
        ),
        const SizedBox(height: 4),
        Text(post.title ?? '', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.375)),
      ],
      if ((post.description ?? '').isNotEmpty)
        Padding(
          padding: EdgeInsets.only(top: isAsk ? 4 : 0),
          child: Text(
            post.description!,
            maxLines: isAsk && !widget.detail ? 2 : null,
            overflow: isAsk && !widget.detail ? TextOverflow.ellipsis : null,
            style: TextStyle(fontSize: 15, height: 1.375, color: isAsk ? p.text.withValues(alpha: .75) : p.text),
          ),
        ),
      ImageGrid(post.images, shareUrl: post.webUrl),
    ]);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      foregroundDecoration: _HairlineDecoration(p.border),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: _openAuthor,
          child: Avatar(name: post.shownName, photoUrl: post.authorPhotoUrl, size: small ? 36 : 44, ring: post.authorHasUpdate, type: post.authorType, badge: small ? 15 : 18),
        ),
        SizedBox(width: small ? 10 : 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: GestureDetector(
                  onTap: _openAuthor,
                  behavior: HitTestBehavior.opaque,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text(post.shownName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.25))),
                      if (post.authorVerification > 0) ...[const SizedBox(width: 6), VerifiedBadge(level: post.authorVerification)],
                      const SizedBox(width: 6),
                      Text(timeAgo(post.createdAt), style: TextStyle(fontSize: 12, color: p.muted)),
                    ]),
                    Text('@${post.authorHandle} · ${isBusiness ? post.authorName : post.authorCompany}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted, height: 1.3)),
                  ]),
                ),
              ),
              // the AI's "why you see this" sits top right, like the web on wide screens
              if (match != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 6),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .38),
                    child: GoldTag(match),
                  ),
                ),
              Semantics(
                button: true,
                label: t('Share'),
                child: InkResponse(
                  onTap: _share,
                  radius: 18,
                  child: SizedBox(width: 32, height: 32, child: Center(child: WIcon(WI.share, size: 18, color: p.muted))),
                ),
              ),
              if (!mine)
                Semantics(
                  button: true,
                  label: 'Report or block',
                  child: InkResponse(
                    onTap: () async {
                      if (await showSafetySheet(context, uid: post.authorUid, name: post.shownName, postId: post.id) && mounted) widget.onBlocked?.call();
                    },
                    radius: 18,
                    child: SizedBox(width: 28, height: 32, child: Center(child: Icon(Icons.more_vert, size: 18, color: p.muted))),
                  ),
                ),
            ]),
            if (mine && isAsk) Padding(padding: const EdgeInsets.only(top: 6), child: GoldTag(t('Your ask'))),
            const SizedBox(height: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openDetail,
              onDoubleTap: _quickReact,
              child: Stack(children: [
                body,
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _burst,
                      builder: (_, __) {
                        if (!_burst.isAnimating) return const SizedBox.shrink();
                        // like-burst: 0 -> 1.25x (25 %) -> 1x (60 %) -> fades rising 14 px
                        final v = _burst.value;
                        final scale = v < .25 ? .4 + .85 * (v / .25) : (v < .6 ? 1.25 - .25 * ((v - .25) / .35) : 1 + .1 * ((v - .6) / .4));
                        final opacity = v < .25 ? v / .25 : (v < .6 ? 1.0 : 1 - (v - .6) / .4);
                        return Center(
                          child: Transform.translate(
                            offset: Offset(0, v < .6 ? 0 : -14 * ((v - .6) / .4)),
                            child: Opacity(opacity: opacity.clamp(0.0, 1.0), child: Transform.scale(scale: scale, child: const Text('👍', style: TextStyle(fontSize: 48)))),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ]),
            ),
            if (isAsk && ((post.locationPref ?? '').isNotEmpty || (post.budget ?? '').isNotEmpty || urgency != null))
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  if ((post.locationPref ?? '').isNotEmpty) InfoPill(wi: WI.pin, text: t(post.locationPref!), onTap: () => _openFind(location: post.locationPref)),
                  if ((post.budget ?? '').isNotEmpty) InfoPill(wi: WI.rupee, text: post.budget!, onTap: () => _openFind(budget: post.budget)),
                  if (urgency != null) InfoPill(wi: WI.clock, text: t(urgency), onTap: () => _openFind(urgency: post.urgency)),
                ]),
              ),
            if (mine && isAsk)
              GestureDetector(
                onTap: _openDetail,
                child: Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: p.chip.withValues(alpha: .5), borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
                  child: Row(children: [
                    WIcon(WI.users, size: 16, color: p.text),
                    const SizedBox(width: 4),
                    Text(t(post.sharesCount == 1 ? '{n} response' : '{n} responses', {'n': post.sharesCount}), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    WIcon(WI.refer, size: 16, color: p.text),
                    const SizedBox(width: 4),
                    Text(t(post.referralsCount == 1 ? '{n} reference' : '{n} references', {'n': post.referralsCount}), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text(t('Review'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.link)),
                    const SizedBox(width: 2),
                    WIcon(WI.arrow, size: 14, color: p.link),
                  ]),
                ),
              ),
            if (isAsk)
              ResponseActivity(
                items: post.recentResponses,
                total: post.sharesCount + post.referralsCount,
                referrals: post.referralsCount,
                hideHeader: mine,
                onMore: _openDetail,
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Transform.translate(offset: const Offset(-6, 0), child: PostActions(key: _actionsKey, post: post, onReply: _reply, onChanged: () => setState(() {}))),
            ),
          ]),
        ),
      ]),
    );
  }

}

/// React · Refer · Repost · Reply · Save under an ask or update (web post-actions.tsx). Counts sit in
/// a small pill next to the icon; labels never shift when the state flips.
class PostActions extends StatefulWidget {
  final Post post;
  final VoidCallback onReply;
  /// after a count changed (the card redraws its response log)
  final VoidCallback? onChanged;
  const PostActions({super.key, required this.post, required this.onReply, this.onChanged});
  @override
  State<PostActions> createState() => PostActionsState();
}

class PostActionsState extends State<PostActions> {
  Post get post => widget.post;
  Api get _api => context.read<AuthProvider>().api;
  bool get _isOwner => context.read<AuthProvider>().profile?.uid == post.authorUid;

  void _changed() {
    if (mounted) setState(() {});
    widget.onChanged?.call();
  }

  // ---------- actions (optimistic, roll back on error) ----------
  Future<void> react(String? next) async {
    final prev = post.myReaction;
    int delta(String? a, String? b) => a != null && b == null ? 1 : (a == null && b != null ? -1 : 0);
    post.myReaction = next;
    post.reacted = next != null;
    post.reactionsCount = (post.reactionsCount + delta(next, prev)).clamp(0, 1 << 30);
    _changed();
    try {
      next == null ? await _api.delete('/posts/${post.id}/react') : await _api.post('/posts/${post.id}/react', {'type': next});
    } catch (_) {
      if (!mounted) return;
      setState(() {
        post.myReaction = prev;
        post.reacted = prev != null;
        post.reactionsCount = (post.reactionsCount - delta(next, prev)).clamp(0, 1 << 30);
      });
    }
  }

  Future<void> _toggleRepost() async {
    final on = !post.reposted;
    setState(() {
      post.reposted = on;
      post.repostsCount = (post.repostsCount + (on ? 1 : -1)).clamp(0, 1 << 30);
    });
    try {
      on ? await _api.post('/posts/${post.id}/repost') : await _api.delete('/posts/${post.id}/repost');
      if (mounted) toast(context, t(on ? 'Reposted to your page' : 'Repost removed'));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        post.reposted = !on;
        post.repostsCount = (post.repostsCount + (on ? -1 : 1)).clamp(0, 1 << 30);
      });
    }
  }

  Future<void> _toggleBookmark() async {
    final on = !post.bookmarked;
    setState(() => post.bookmarked = on);
    try {
      on ? await _api.post('/posts/${post.id}/bookmark') : await _api.delete('/posts/${post.id}/bookmark');
      if (mounted) toast(context, t(on ? 'Saved' : 'Removed from saved'));
    } catch (_) {
      if (mounted) setState(() => post.bookmarked = !on);
    }
  }

  /// Refer contacts from the phone book (one call per contact, max 5 per ask).
  Future<void> _refer() async {
    final api = _api;
    var mine = 0;
    try {
      mine = ((await api.get('/app/posts/${post.id}/referrals/mine')) as List).length;
    } catch (_) {}
    if (!mounted) return;
    final left = 5 - mine;
    if (left <= 0) return toast(context, t('You can refer up to 5 contacts on one ask'));
    final picked = await Navigator.push<List<PickedContact>>(context, MaterialPageRoute(builder: (_) => ContactPicker(askerName: post.shownName, maxSelect: left)));
    if (picked == null || picked.isEmpty || !mounted) return;
    var ok = 0;
    String? err;
    for (final c in picked) {
      try {
        await api.post('/posts/${post.id}/refer', {'name': c.name, 'phone': c.phone});
        ok++;
      } catch (e) {
        err = '$e';
      }
    }
    if (!mounted) return;
    if (ok > 0) {
      post.referralsCount += ok;
      _changed();
    }
    toast(context, ok > 0 ? t('Referral sent') : (err ?? t('Could not refer')), error: ok == 0);
  }

  @override
  Widget build(BuildContext context) => _actions(Pal.of(context), post.isRequirement, _isOwner);

  Widget _actions(Pal p, bool isAsk, bool mine) {
    Widget num(int n) => Container(
          margin: const EdgeInsets.only(left: 2),
          constraints: const BoxConstraints(minWidth: 18),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(10)),
          child: Text('$n', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, height: 1, color: p.text, fontFeatures: const [FontFeature.tabularFigures()])),
        );
    Widget btn({required Widget icon, int? count, required String label, String? altLabel, bool alt = false, required Color color, required VoidCallback onTap, bool wrap = true}) {
      final content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(height: 24, child: Row(mainAxisSize: MainAxisSize.min, children: [icon, if (count != null && count > 0) num(count)])),
          const SizedBox(height: 2),
          // both labels share one cell so the row never shifts when the state flips
          Stack(alignment: Alignment.center, children: [
            Opacity(opacity: alt ? 0 : 1, child: Text(t(label), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, height: 1, color: color))),
            if (altLabel != null) Opacity(opacity: alt ? 1 : 0, child: Text(t(altLabel), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, height: 1, color: color))),
          ]),
        ]),
      );
      return wrap ? InkWell(onTap: onTap, borderRadius: BorderRadius.circular(10), child: content) : content;
    }

    final reacted = post.myReaction != null;
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      ReactionPicker(
        quick: true,
        value: post.myReaction,
        onChange: react,
        trigger: (_) => btn(
          icon: reacted
              ? SizedBox(width: 20, height: 20, child: Center(child: ReactionGlyph(post.myReaction!, size: 15)))
              : WIcon(WI.heart, size: 20, color: p.muted),
          count: post.reactionsCount,
          label: 'React',
          color: reacted ? p.text : p.muted,
          onTap: () {},
          wrap: false,
        ),
      ),
      if (isAsk && !mine) btn(icon: WIcon(WI.refer, size: 20, color: p.muted), count: post.referralsCount, label: 'Refer', color: p.muted, onTap: _refer),
      btn(
        icon: WIcon(WI.repost, size: 20, color: post.reposted ? const Color(0xFF059669) : p.muted),
        count: post.repostsCount,
        label: 'Repost',
        altLabel: 'Reposted',
        alt: post.reposted,
        color: post.reposted ? const Color(0xFF059669) : p.muted,
        onTap: _toggleRepost,
      ),
      btn(icon: WIcon(WI.reply, size: 20, color: p.muted), count: isAsk ? post.sharesCount : null, label: 'Reply', color: p.muted, onTap: widget.onReply),
      btn(
        icon: WIcon(WI.bookmark, size: 20, color: post.bookmarked ? p.link : p.muted, fill: post.bookmarked),
        label: 'Save',
        altLabel: 'Saved',
        alt: post.bookmarked,
        color: post.bookmarked ? p.link : p.muted,
        onTap: _toggleBookmark,
      ),
    ]);
  }
}

/// Bottom hairline that fades out at both ends (web: after:bg-gradient-to-r from-transparent via-border).
class _HairlineDecoration extends Decoration {
  final Color color;
  const _HairlineDecoration(this.color);
  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _HairlinePainter(color);
}

class _HairlinePainter extends BoxPainter {
  final Color color;
  _HairlinePainter(this.color);
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final size = cfg.size!;
    final rect = Rect.fromLTWH(offset.dx, offset.dy + size.height - 1, size.width, 1);
    canvas.drawRect(rect, Paint()..shader = LinearGradient(colors: [color.withValues(alpha: 0), color, color.withValues(alpha: 0)]).createShader(rect));
  }
}

/// Responses on an ask as a compact log (web response-activity.tsx): a count header, then the latest few
/// as "who did what, when" with the owner's feedback. Never shows the contact, photo or opinion itself.
class ResponseActivity extends StatelessWidget {
  final List<ResponseLog> items;
  final int total, referrals;
  final bool hideHeader;
  final VoidCallback? onMore;
  const ResponseActivity({super.key, required this.items, required this.total, this.referrals = 0, this.hideHeader = false, this.onMore});

  static const _verb = {'referral': 'referred a contact', 'contact': 'shared a contact', 'media': 'shared a photo', 'info': 'shared an opinion'};

  static String countLabel(int responses, int referred) {
    final parts = <String>[];
    if (responses > 0 || referred == 0) parts.add(t(responses == 1 ? '{n} response' : '{n} responses', {'n': responses}));
    if (referred > 0) parts.add(t('{n} referred', {'n': referred}));
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    if (total == 0) {
      if (hideHeader) return const SizedBox.shrink();
      return Padding(padding: const EdgeInsets.only(top: 10), child: Text(t('Be the first to respond'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.muted)));
    }
    final more = total - items.length;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!hideHeader)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              WIcon(WI.users, size: 16, color: p.text),
              const SizedBox(width: 6),
              Text(countLabel(total - referrals, referrals), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        Container(
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: p.border, width: 2))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final r in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Avatar(name: displayName(r.userType, r.name, r.company), size: 20, photoUrl: r.photoUrl),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: displayName(r.userType, r.name, r.company), style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (r.verification > 0) WidgetSpan(alignment: PlaceholderAlignment.middle, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: VerifiedBadge(level: r.verification, size: 13))),
                        TextSpan(text: ' ${t(_verb[r.kind] ?? 'responded')}', style: TextStyle(color: p.muted)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  if (r.rating != null || r.reaction != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text('${r.rating == 1 ? '👍' : r.rating == -1 ? '👎' : ''}${r.reaction == null ? '' : kReactionEmoji[r.reaction] ?? ''}', style: const TextStyle(fontSize: 12)),
                    ),
                  const SizedBox(width: 6),
                  Text(timeAgo(r.createdAt), style: TextStyle(fontSize: 12, color: p.muted)),
                ]),
              ),
            if (more > 0)
              GestureDetector(
                onTap: onMore,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(t('+{n} more', {'n': more}), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: onMore != null ? p.link : p.muted)),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

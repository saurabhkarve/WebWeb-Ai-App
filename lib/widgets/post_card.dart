import 'package:flutter/material.dart';
import 'hashtag_text.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../auth_provider.dart';
import '../i18n.dart';
import '../models.dart';
import '../safety.dart';
import '../screens/ask.dart';
import '../screens/contact_picker.dart';
import '../screens/find.dart';
import '../screens/post_detail.dart';
import '../screens/profile.dart';
import '../screens/talk.dart' show openChat;
import '../theme.dart';
import '../widgets.dart';
import 'area_map.dart';
import 'image_grid.dart';
import 'reaction_picker.dart';
import 'reply_thread.dart';
import 'response_sheet.dart';
import 'tour.dart';
import '../share_log.dart';
import '../views.dart';

/// Feed row, same layout as the web PostCard (post-card.tsx): avatar on the left; who + why you see it;
/// the category chip, title and two lines of description; photos; location / budget / timing chips;
/// a compact response log; then React · Refer · Reply · Share. Tap opens the ask, double tap
/// gives it a thumbs up.
class PostCard extends StatefulWidget {
  final Post post;
  final VoidCallback? onChanged;

  /// Detail page mode: full text, no navigation on tap, and Reply calls [onReply].
  final bool detail;
  final VoidCallback? onReply;

  /// Called after the author was blocked from this card's menu (the list drops their posts).
  final VoidCallback? onBlocked;

  /// The card the Connect tour points at (its chips, Reply and Refer carry the tour keys).
  final bool tourTarget;
  const PostCard({super.key, required this.post, this.onChanged, this.detail = false, this.onReply, this.onBlocked, this.tourTarget = false});
  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> with SingleTickerProviderStateMixin {
  late Post post = widget.post;
  bool _gone = false; // deleted from its ⋯ menu
  late final AnimationController _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));

  @override
  void initState() {
    super.initState();
    // views: someone else's post counts as seen once its card is built on screen (the feed builds just ahead of it)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.detail && !_isOwner) ViewTracker.record(context.read<AuthProvider>().api, post.id);
    });
  }

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

  Future<void> _openDetail({bool expandResponses = false}) async {
    if (widget.detail) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailScreen(postId: post.id, expandResponses: expandResponses)));
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
        id: p.id,
        kind: p.kind,
        authorUid: p.authorUid,
        authorName: p.authorName,
        authorCompany: p.authorCompany,
        authorHandle: p.authorHandle,
        authorPhotoUrl: p.authorPhotoUrl,
        title: p.title,
        description: p.description,
        category: p.category,
        locationPref: p.locationPref,
        budget: p.budget,
        urgency: p.urgency,
        matchReason: p.matchReason,
        slug: p.slug,
        categoryLabel: p.categoryLabel,
        authorType: p.authorType,
        authorVerification: p.authorVerification,
        distanceM: p.distanceM,
        radiusM: p.radiusM,
        lat: p.lat,
        lng: p.lng,
        editedAt: p.editedAt,
        repostedByName: p.repostedByName,
        repostedByHandle: p.repostedByHandle,
        repostedAt: p.repostedAt,
        images: p.images,
        sharesCount: n,
        authorHasUpdate: p.authorHasUpdate,
        createdAt: p.createdAt,
        recentResponses: p.recentResponses,
        latestReplies: p.latestReplies,
        referrers: p.referrers,
        reactionsCount: p.reactionsCount,
        repostsCount: p.repostsCount,
        referralsCount: p.referralsCount,
        reacted: p.reacted,
        reposted: p.reposted,
        bookmarked: p.bookmarked,
        myReaction: p.myReaction,
      );

  /// ⋯ on my own ask: edit it in the Ask editor, or delete it (a soft delete: it leaves every feed,
  /// including where it was reposted).
  Future<void> _ownerMenu() async {
    final p = Pal.of(context);
    final isAsk = post.isRequirement;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: p.canvas,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: WIcon(WI.bookmark, size: 20, color: p.text, fill: post.bookmarked),
            title: Text(t(post.bookmarked ? 'Remove from saved' : (isAsk ? 'Save ask' : 'Save'))),
            onTap: () => Navigator.pop(ctx, 'save'),
          ),
          // saving is for you; what follows changes the ask
          Divider(height: 1, color: p.border),
          if (isAsk) ListTile(leading: WIcon(WI.edit, size: 20, color: p.text), title: Text(t('Edit ask')), onTap: () => Navigator.pop(ctx, 'edit')),
          ListTile(
            leading: WIcon(WI.trash, size: 20, color: p.danger),
            title: Text(t(isAsk ? 'Delete ask' : 'Delete'), style: TextStyle(color: p.danger)),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'save') return _actionsKey.currentState?.toggleBookmark();
    if (choice == 'edit') {
      final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => SubPage(title: t('Edit ask'), body: AskScreen(onPosted: () {}, edit: post))));
      if (saved == true) widget.onChanged?.call();
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t(isAsk ? 'Delete this ask?' : 'Delete this post?'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        content: Text(t('It will be removed from the feed, including where it was reposted, along with its responses and referrals.'), style: TextStyle(fontSize: 14, color: p.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Keep'), style: TextStyle(color: p.text, fontWeight: FontWeight.w700))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Delete'), style: TextStyle(color: p.danger, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await context.read<AuthProvider>().api.delete('/posts/${post.id}');
      if (!mounted) return;
      setState(() => _gone = true);
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return const SizedBox.shrink();
    final p = Pal.of(context);
    final isAsk = post.isRequirement;
    final mine = _isOwner;
    final urgency = askTimeLeft(post);
    final isBusiness = post.authorType == 'entrepreneur';
    // phones: a smaller author photo leaves more width for the ask
    final small = MediaQuery.sizeOf(context).width < 600;
    // the distance sits on the location chip
    final match = (post.matchReason ?? '').isEmpty ? null : post.matchReason!;

    final body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (isAsk) HashtagText(post.title ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.375, letterSpacing: -0.18)),
      if ((post.description ?? '').isNotEmpty)
        Padding(
          padding: EdgeInsets.only(top: isAsk ? 4 : 0),
          child: HashtagText(
            post.description!,
            maxLines: isAsk && !widget.detail ? 2 : null,
            overflow: isAsk && !widget.detail ? TextOverflow.ellipsis : null,
            style: TextStyle(fontSize: 15, height: isAsk ? 1.6 : 1.375, color: isAsk ? p.text.withValues(alpha: .7) : p.text),
          ),
        ),
      ImageGrid(post.images, shareUrl: post.webUrl, shareRef: post.id),
    ]);

    // ⋯: my own ask's menu (save, edit, delete), or save / report / block on someone else's
    final more = <Widget>[
      if (mine && !widget.detail)
        Semantics(
          button: true,
          label: t('More options'),
          child: InkResponse(
            onTap: _ownerMenu,
            radius: 18,
            child: SizedBox(width: 28, height: 32, child: Center(child: Icon(Icons.more_vert, size: 18, color: p.muted))),
          ),
        ),
      if (!mine)
        Semantics(
          button: true,
          label: 'Report or block',
          child: InkResponse(
            onTap: () async {
              if (await showSafetySheet(context, uid: post.authorUid, name: post.shownName, postId: post.id, saved: post.bookmarked, onToggleSave: () => _actionsKey.currentState?.toggleBookmark()) && mounted) {
                widget.onBlocked?.call();
              }
            },
            radius: 18,
            child: SizedBox(width: 28, height: 32, child: Center(child: Icon(Icons.more_vert, size: 18, color: p.muted))),
          ),
        ),
    ];
    // the ask's words and photos: tap opens it, double tap gives it a thumbs up (with the burst)
    final tappable = GestureDetector(
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
    );

    final framed = post.repostedByName != null && !widget.detail;
    // asks: the Spotlight layout (web post-card.tsx), open on the feed with the hairline between rows: who asked, the
    // category with why you see it, the ask, chips for place, budget, time left and reach, the latest replies in public,
    // then Refer as the gold button with Reply beside it.
    if (isAsk && !widget.detail) {
      final why = mine ? t('Your ask') : (match == null ? null : t(match));
      final spotlight = Container(
        padding: framed ? const EdgeInsets.only(top: 8, bottom: 20) : const EdgeInsets.symmetric(vertical: 20),
        foregroundDecoration: framed ? null : _HairlineDecoration(kGold.withValues(alpha: .6)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: EdgeInsets.zero,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                GestureDetector(
                  onTap: _openAuthor,
                  child: Avatar(name: post.shownName, photoUrl: post.authorPhotoUrl, size: 40, ring: post.authorHasUpdate, type: post.authorType, uid: post.authorUid, badge: 15),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: _openAuthor,
                    behavior: HitTestBehavior.opaque,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(child: Text(post.shownName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.25))),
                        if (post.authorVerification > 0 || post.authorPremium || post.authorPlan != null) ...[const SizedBox(width: 6), VerifiedBadge(level: post.authorVerification, premium: post.authorPremium, plan: post.authorPlan)],
                      ]),
                      Text('${isBusiness ? post.authorName : post.authorCompany} · ${timeAgo(post.createdAt)}${post.editedAt != null ? ' · ${editedLabel(post.editedAt!)}' : ''}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted, height: 1.3)),
                    ]),
                  ),
                ),
                ...more,
              ]),
              const SizedBox(height: 10),
              // the category as a small heading, why you see this ask on the right
              Row(children: [
                WIcon(categoryIcon(post.category), size: 14, color: p.link, still: true),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(t(post.categoryText).toUpperCase(),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .6, color: p.link)),
                ),
                // "Near you" opens the ask's area map, like its place chip
                if (why != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: !mine && match != null && ((post.locationPref ?? '').isNotEmpty || post.lat != null)
                        ? GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => showAskAreaSheet(context, post), child: GoldTag(why))
                        : GoldTag(why),
                  ),
                ],
              ]),
              const SizedBox(height: 4),
              tappable,
              // where, budget, time left, reach, photos as chips (the category is shown above)
              Padding(
                key: widget.tourTarget ? Tours.key('chips') : null,
                padding: const EdgeInsets.only(top: 10),
                child: ChipLine(children: [
                  if ((post.locationPref ?? '').isNotEmpty)
                    InfoPill(
                      small: true,
                      wi: WI.pin,
                      text: '${t(post.locationPref!)}${post.distanceM == null ? '' : ' · ${formatDistance(post.distanceM!)}'}',
                      onTap: () => showAskAreaSheet(context, post),
                    ),
                  if ((post.budget ?? '').isNotEmpty) InfoPill(small: true, gold: true, wi: WI.rupee, text: post.budget!, onTap: () => _openFind(budget: post.budget)),
                  if (urgency != null) InfoPill(small: true, gold: true, wi: WI.clock, text: urgency),
                  if ((post.radiusM ?? 0) > 0) InfoPill(small: true, gold: true, wi: WI.locate, text: t('{d} reach', {'d': formatDistance(post.radiusM!)}), onTap: () => showAskAreaSheet(context, post)),
                  if (post.images.isNotEmpty) InfoPill(small: true, gold: true, wi: WI.camera, text: t(post.images.length == 1 ? '1 photo' : '{n} photos', {'n': post.images.length})),
                ]),
              ),
              LatestReplies(post: post, onMore: () => _openDetail(expandResponses: true)),
              const SizedBox(height: 12),
              PostActions(key: _actionsKey, post: post, onReply: _reply, onReview: _openDetail, spotlight: true, onChanged: () => setState(() {}), tourTarget: widget.tourTarget),
            ]),
          ),
        ]),
      );
      if (!framed) return spotlight;
      // reposted (Connect, a member's page): no frame, so the ask keeps its full width and every control stays where it
      // always is; it is marked behind and beside it instead (_reposted)
      return _reposted(p, spotlight, top: 16, gap: 0);
    }

    final card = Container(
      padding: framed ? const EdgeInsets.fromLTRB(12, 12, 12, 8) : const EdgeInsets.symmetric(vertical: 16),
      foregroundDecoration: framed ? null : _HairlineDecoration(kGold.withValues(alpha: .6)),
      decoration: framed ? BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: p.border)) : null,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: _openAuthor,
          child: Avatar(name: post.shownName, photoUrl: post.authorPhotoUrl, size: small ? 36 : 44, ring: post.authorHasUpdate, type: post.authorType, uid: post.authorUid, badge: small ? 15 : 18),
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
                      if (post.authorVerification > 0 || post.authorPremium || post.authorPlan != null) ...[const SizedBox(width: 6), VerifiedBadge(level: post.authorVerification, premium: post.authorPremium, plan: post.authorPlan)],
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text('${timeAgo(post.createdAt)}${post.editedAt != null ? ' · ${editedLabel(post.editedAt!)}' : ''}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted)),
                      ),
                    ]),
                    Text(isBusiness ? post.authorName : post.authorCompany, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted, height: 1.3)),
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
              ...more,
            ]),
            if (mine && isAsk) Padding(padding: const EdgeInsets.only(top: 6), child: GoldTag(t('Your ask'))),
            const SizedBox(height: 8),
            tappable,
            // the essentials as chips: what, where (and how far), budget, timing, reach, photos
            if (isAsk)
              Padding(
                key: widget.tourTarget ? Tours.key('chips') : null,
                padding: const EdgeInsets.only(top: 8),
                // one line that scrolls sideways
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  child: Row(
                      children: [
                    InfoPill(small: true, wi: categoryIcon(post.category), text: t(post.categoryText)),
                    if ((post.locationPref ?? '').isNotEmpty)
                      InfoPill(
                        small: true,
                        wi: WI.pin,
                        text: '${t(post.locationPref!)}${post.distanceM == null ? '' : ' · ${formatDistance(post.distanceM!)}'}',
                        onTap: () => showAskAreaSheet(context, post),
                      ),
                    if ((post.budget ?? '').isNotEmpty) InfoPill(small: true, wi: WI.rupee, text: post.budget!, onTap: () => _openFind(budget: post.budget)),
                    if (urgency != null) InfoPill(small: true, wi: WI.clock, text: urgency, onTap: () => _openFind(urgency: post.urgency)),
                    if ((post.radiusM ?? 0) > 0) InfoPill(small: true, wi: WI.locate, text: t('{d} reach', {'d': formatDistance(post.radiusM!)}), onTap: () => showAskAreaSheet(context, post)),
                    if (post.images.isNotEmpty) InfoPill(small: true, wi: WI.camera, text: t(post.images.length == 1 ? '1 photo' : '{n} photos', {'n': post.images.length})),
                  ].expand((w) => [w, const SizedBox(width: 6)]).toList()),
                ),
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
                onMore: () => _openDetail(expandResponses: true),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child:
                  Transform.translate(offset: const Offset(-6, 0), child: PostActions(key: _actionsKey, post: post, onReply: _reply, onChanged: () => setState(() {}), tourTarget: widget.tourTarget)),
            ),
          ]),
        ),
      ]),
    );
    if (!framed) return card;
    return _reposted(p, card, top: 16, gap: 8, bottom: 16);
  }

  /// A reposted post, marked without touching its layout (web post-card.tsx): a green "X reposted" tag on top with when
  /// on the right, then a green quote line in the gutter and a green wash fading down, both beside the ask alone.
  Widget _reposted(Pal p, Widget child, {required double top, required double gap, double bottom = 0}) {
    const green = Color(0xFF2F9E6E);
    final ink = Theme.of(context).brightness == Brightness.dark ? const Color(0xFF7FD6AD) : const Color(0xFF1F7A52);
    return Container(
      padding: EdgeInsets.only(top: top, bottom: bottom),
      foregroundDecoration: _HairlineDecoration(kGold.withValues(alpha: .6)),
      // the tag on top; the quote line and the wash cover the ask alone, from just under it
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.only(bottom: gap),
          child: Row(children: [
            Flexible(
              child: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: post.repostedByHandle ?? ''))),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(6, 2, 10, 2),
                  decoration: BoxDecoration(color: green.withValues(alpha: .15), borderRadius: BorderRadius.circular(99)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    WIcon(WI.repost, size: 14, color: ink),
                    const SizedBox(width: 5),
                    Flexible(child: Text(t('{name} reposted', {'name': post.repostedByName!}), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ink))),
                  ]),
                ),
              ),
            ),
            if (post.repostedAt != null) ...[
              const Spacer(),
              Padding(padding: const EdgeInsets.only(right: 4), child: Text(timeAgo(post.repostedAt!), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ink))),
            ],
          ]),
        ),
        Stack(clipBehavior: Clip.none, children: [
          // one rounded block: a thin green edge on the left that follows the corners, and the wash fading down
          Positioned(
            left: -10,
            right: -10,
            top: 0,
            bottom: 12,
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: const [0, .45], colors: [green.withValues(alpha: .09), green.withValues(alpha: 0)]),
                  ),
                  child: Align(alignment: Alignment.centerLeft, child: SizedBox(width: 2, height: double.infinity, child: ColoredBox(color: green.withValues(alpha: .4)))),
                ),
              ),
            ),
          ),
          child,
        ]),
      ]),
    );
  }
}

/// React · Refer · Reply · Share under an ask or update (web post-actions.tsx). Share opens a sheet that also
/// holds Repost, WhatsApp and Copy link; Save is in the ⋯ menu. Counts sit in a small pill next to the icon;
/// labels never shift when the state flips.
class PostActions extends StatefulWidget {
  final Post post;
  final VoidCallback onReply;

  /// after a count changed (the card redraws its response log)
  final VoidCallback? onChanged;
  final bool tourTarget;
  /// the ask card's row: one gold Reply (Review responses on my own ask) with React, Refer and Share as pills
  final bool spotlight;
  final VoidCallback? onReview;
  const PostActions({super.key, required this.post, required this.onReply, this.onChanged, this.tourTarget = false, this.spotlight = false, this.onReview});
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

  /// Save / remove from saved (from the ⋯ menu and the Share menu).
  Future<void> toggleBookmark() async {
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

  String get _subject => post.title ?? (post.isRequirement ? 'WebWeb AI ask' : 'WebWeb AI update');

  /// Share: repost to your page, WhatsApp, the phone's share sheet, copy link.
  Future<void> _share() async {
    final p = Pal.of(context);
    const green = Color(0xFF059669);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: p.canvas,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: WIcon(WI.repost, size: 20, color: post.reposted ? green : p.text),
            title: Text('${t(post.reposted ? 'Undo repost' : 'Repost')}${post.repostsCount > 0 ? ' · ${post.repostsCount}' : ''}'),
            onTap: () => Navigator.pop(ctx, 'repost'),
          ),
          ListTile(leading: SvgPicture.string(whatsAppSvg, width: 20, height: 20), title: const Text('WhatsApp'), onTap: () => Navigator.pop(ctx, 'whatsapp')),
          ListTile(leading: WIcon(WI.share, size: 20, color: p.text), title: Text(t('More ways to share')), onTap: () => Navigator.pop(ctx, 'native')),
          ListTile(leading: WIcon(WI.link, size: 20, color: p.text), title: Text(t('Copy link')), onTap: () => Navigator.pop(ctx, 'copy')),
          // Save is here as well as in the ⋯ menu
          ListTile(
            leading: WIcon(WI.bookmark, size: 20, color: p.text, fill: post.bookmarked),
            title: Text(t(post.bookmarked ? 'Remove from saved' : (post.isRequirement ? 'Save ask' : 'Save'))),
            onTap: () => Navigator.pop(ctx, 'save'),
          ),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'repost':
        await _toggleRepost();
      case 'whatsapp':
        final ok = await launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent('$_subject\n${post.webUrl}')}'), mode: LaunchMode.externalApplication).catchError((_) => false);
        if (ok) logShare(_api, 'post', post.id, channel: 'whatsapp');
      case 'native':
        try {
          await shareAndLog(_api, entity: 'post', ref: post.id, text: post.webUrl, subject: _subject);
        } catch (_) {}
      case 'save':
        await toggleBookmark();
      case 'copy':
        await Clipboard.setData(ClipboardData(text: post.webUrl));
        logShare(_api, 'post', post.id, channel: 'copy');
        if (mounted) toast(context, t('Link copied'));
    }
  }

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

    Widget tour(String target, Widget child) => widget.tourTarget ? KeyedSubtree(key: Tours.key(target), child: child) : child;
    final reacted = post.myReaction != null;
    const green = Color(0xFF059669);
    if (widget.spotlight) {
      // as on the web: on a phone a small tile (the icon with its count badge to the right, a short title under); on a
      // tablet a pill with the icon, the title and the count in one line. A soft card with a light outline (gold on Refer)
      final wide = MediaQuery.sizeOf(context).width >= 600;
      Widget pill({required Widget icon, int count = 0, Color? color, VoidCallback? onTap, required String label, Color? fill, Color? edge, String? text, Color? badge, Color? splash}) {
        final c0 = color ?? p.muted;
        final title = Text(text ?? t(label), maxLines: 1, style: TextStyle(fontSize: wide ? 11.5 : 10, height: 1, fontWeight: FontWeight.w700, color: c0));
        final chip = count > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(color: badge ?? p.chip, borderRadius: BorderRadius.circular(9)),
                child: Text(compactCount(count), style: TextStyle(fontSize: 11, height: 1.45, fontWeight: FontWeight.w700, color: c0, fontFeatures: const [FontFeature.tabularFigures()])),
              )
            : null;
        final radius = BorderRadius.circular(wide ? 18 : 12);
        final c = Container(
          constraints: BoxConstraints(minWidth: wide ? 0 : 56, minHeight: wide ? 32 : 0),
          padding: wide ? const EdgeInsets.symmetric(horizontal: 10) : const EdgeInsets.fromLTRB(10, 6, 10, 4),
          decoration: BoxDecoration(
            color: fill ?? p.card,
            borderRadius: radius,
            border: Border.all(color: edge ?? p.border),
            boxShadow: const [BoxShadow(color: Color(0x0D1E1E1E), blurRadius: 2, offset: Offset(0, 1))],
          ),
          // centred in its share of the row (every control is the same width, count or not)
          child: wide
              ? Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                  icon,
                  const SizedBox(width: 6),
                  title,
                  if (chip != null) ...[const SizedBox(width: 6), chip],
                ])
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(height: 18, child: Row(mainAxisSize: MainAxisSize.min, children: [icon, if (chip != null) ...[const SizedBox(width: 4), chip]])),
                  const SizedBox(height: 4),
                  title,
                ]),
        );
        return Semantics(button: true, label: t(label), excludeSemantics: true, child: onTap == null ? c : InkWell(onTap: onTap, borderRadius: radius, hoverColor: splash, highlightColor: splash, child: c));
      }

      // React, Reply, Refer, Views, Share at every size (as on the web), so Refer sits in the middle: in gold, since asks
      // are answered by referring someone (the asker reviews responses instead). Equal widths, as on the web: each is as
      // wide as the widest needs, count or not, so nothing shifts when a count appears; 6 apart
      final kids = <Widget>[
        // React first
        ReactionPicker(
          quick: true,
          value: post.myReaction,
          onChange: react,
          // a rose tint while the picker is open, like the web's hover
          trigger: (open) => pill(
            label: 'React',
            fill: open ? const Color(0xFFF43F5E).withValues(alpha: .1) : null,
            icon: reacted ? SizedBox(width: 18, height: 18, child: Center(child: ReactionGlyph(post.myReaction!, size: 15))) : WIcon(WI.heart, size: 18, color: p.muted),
            count: post.reactionsCount,
            color: reacted ? p.text : p.muted,
          ),
        ),
        if (mine)
          pill(label: 'Review responses', icon: WIcon(WI.talk, size: 18, color: p.tagText), count: post.sharesCount, badge: p.tagBg, color: p.tagText, edge: kGold.withValues(alpha: .45), fill: kGold.withValues(alpha: .1), onTap: widget.onReview ?? widget.onReply)
        else ...[
          tour('reply', pill(label: 'Reply', icon: WIcon(WI.talk, size: 18, color: p.muted), count: isAsk ? post.sharesCount : 0, color: p.muted, onTap: widget.onReply)),
          if (isAsk)
            // plain like the rest, in deep gold so it still leads (as on the web)
            tour(
              'refer',
              pill(
                label: 'Refer',
                icon: WIcon(WI.refer, size: 18, color: p.tagText),
                count: post.referralsCount,
                color: p.tagText,
                badge: p.tagBg,
                splash: kGold.withValues(alpha: .15),
                edge: kGold.withValues(alpha: .45),
                fill: kGold.withValues(alpha: .1),
                onTap: _refer,
              ),
            ),
        ],
        // views, as on x.com: people who saw it (a count, not a button). Shown at 0 too, so every tile keeps its place
        Semantics(
          label: t(post.viewsCount == 1 ? '1 view' : '{n} views', {'n': post.viewsCount}),
          excludeSemantics: true,
          child: pill(label: 'Views', icon: WIcon(WI.views, size: 18, color: p.muted), count: post.viewsCount),
        ),
        pill(
          label: post.reposted ? 'Reposted' : 'Share',
          icon: WIcon(post.reposted ? WI.repost : WI.share, size: 18, color: post.reposted ? green : p.muted),
          count: post.repostsCount,
          color: post.reposted ? green : p.muted,
          badge: post.reposted ? green.withValues(alpha: .1) : null,
          edge: post.reposted ? green.withValues(alpha: .4) : null,
          onTap: _share,
        ),
      ];
      // equal shares: every control is as wide as the widest needs (IntrinsicWidth), spread over the full width
      final row = Row(spacing: 6, children: [for (final k in kids) Expanded(child: k)]);
      // scrolls sideways when it is wider than the screen (a narrow phone, a long translation); at least the full width,
      // so the spacing still spreads the buttons when they fit
      return LayoutBuilder(
        builder: (_, box) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          // the tiles' shadow shows below the row
          clipBehavior: Clip.none,
          child: ConstrainedBox(constraints: BoxConstraints(minWidth: box.maxWidth), child: IntrinsicWidth(child: row)),
        ),
      );
    }
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      ReactionPicker(
        quick: true,
        value: post.myReaction,
        onChange: react,
        trigger: (_) => btn(
          icon: reacted ? SizedBox(width: 20, height: 20, child: Center(child: ReactionGlyph(post.myReaction!, size: 15))) : WIcon(WI.heart, size: 20, color: p.muted),
          count: post.reactionsCount,
          label: 'React',
          color: reacted ? p.text : p.muted,
          onTap: () {},
          wrap: false,
        ),
      ),
      if (isAsk && !mine) tour('refer', btn(icon: WIcon(WI.refer, size: 20, color: p.muted), count: post.referralsCount, label: 'Refer', color: p.muted, onTap: _refer)),
      tour('reply', btn(icon: WIcon(WI.talk, size: 20, color: p.muted), count: isAsk ? post.sharesCount : null, label: 'Reply', color: p.muted, onTap: widget.onReply)),
      // Share holds Repost too: green with the repost icon once you have reposted it
      btn(
        icon: WIcon(post.reposted ? WI.repost : WI.share, size: 20, color: post.reposted ? const Color(0xFF059669) : p.muted),
        count: post.repostsCount,
        label: 'Share',
        altLabel: 'Reposted',
        alt: post.reposted,
        color: post.reposted ? const Color(0xFF059669) : p.muted,
        onTap: _share,
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
    canvas.drawRect(rect, Paint()..shader = LinearGradient(colors: [color.withValues(alpha: 0), color, color, color.withValues(alpha: 0)], stops: const [0, .12, .88, 1]).createShader(rect));
  }
}

/// Responses on an ask as a compact log (web response-activity.tsx): a count header, then the latest few
/// as "who did what, when" with the owner's feedback. Never shows the contact, photo or opinion itself.
/// The ask card's "Latest replies" (web latest-replies.tsx): the 3 newest replies with what they said, open to every
/// member. A text reply shows its words and a photo reply its picture; a shared contact shows only that it was shared
/// (the number is for the asker alone). Referrals follow as one line of who referred; the people referred never show.
class LatestReplies extends StatelessWidget {
  final Post post;
  final VoidCallback onMore;
  const LatestReplies({super.key, required this.post, required this.onMore});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final replies = post.latestReplies;
    final referrers = post.referrers;
    final total = post.sharesCount + post.referralsCount;
    if (total == 0) {
      return Padding(padding: const EdgeInsets.only(top: 12), child: Text(t('Be the first to respond'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.muted)));
    }
    final shown = replies.length + referrers.fold<int>(0, (n, r) => n + r.n);
    const bubble = BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(14), bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14));
    void openProfile(String handle) => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: handle)));
    // open on the card (no panel of its own): a heading at the card's edge (talk icon, label, count, a hairline that
    // fades out), then the replies as compact bubbles set in under the author's name as a thread (the author avatar's 40
    // plus its 10 gap), and Show all n last, as on the web
    final any = replies.isNotEmpty || referrers.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const WIcon(WI.talk, size: 16, color: kGold),
          const SizedBox(width: 8),
          Text(any ? t('Latest replies') : ResponseActivity.countLabel(post.sharesCount, post.referralsCount), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          if (any) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: kGold.withValues(alpha: .15), borderRadius: BorderRadius.circular(99)),
              child: Text('$total', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: p.tagText, fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ],
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, decoration: BoxDecoration(gradient: LinearGradient(colors: [kGold.withValues(alpha: .5), p.border, p.border.withValues(alpha: 0)])))),
        ]),
        Padding(
          // set in less on a phone, as on the web
          padding: const EdgeInsets.only(left: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final r in replies)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              GestureDetector(onTap: () => openProfile(r.handle), child: Avatar(name: r.userType == 'entrepreneur' && r.company.isNotEmpty ? r.company : r.name, photoUrl: r.photoUrl, size: 24)),
              const SizedBox(width: 8),
              Expanded(
                // react and reply from the name line, as on the web
                child: ReplySocial(
                  key: ValueKey('${post.id}-${r.uid}'),
                  postId: post.id,
                  reply: r,
                  meta: [
                    Flexible(
                      child: GestureDetector(
                        onTap: () => openProfile(r.handle),
                        child: Text(r.userType == 'entrepreneur' && r.company.isNotEmpty ? r.company : r.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    if (r.verification > 0) ...[const SizedBox(width: 4), VerifiedBadge(level: r.verification, size: 12)],
                    const SizedBox(width: 6),
                    Text(timeAgo(r.createdAt), style: TextStyle(fontSize: 11, color: p.muted)),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: r.kind == 'info' && (r.text ?? '').isNotEmpty
                        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            // the bubble is ReplySocial's, with the name and time on top
                            HashtagText(r.text!, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, height: 1.35)),
                            // a photo sent with the note
                            if ((r.imageUrl ?? '').isNotEmpty)
                              Padding(padding: const EdgeInsets.only(top: 4), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: NetImg(r.imageUrl!, width: 96, height: 64))),
                          ])
                        : r.kind == 'media' && (r.imageUrl ?? '').isNotEmpty
                            ? ClipRRect(borderRadius: BorderRadius.circular(8), child: NetImg(r.imageUrl!, width: 96, height: 64))
                            : Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                                Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                decoration: BoxDecoration(borderRadius: bubble, border: Border.all(color: p.border)),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  WIcon(WI.lock, size: 13, color: p.muted),
                                  const SizedBox(width: 4),
                                  Flexible(child: Text(t('Shared a contact privately'), style: TextStyle(fontSize: 11, color: p.muted))),
                                ]),
                              ),
                                // the number went to the asker alone: anyone else can ask the replier for it
                                RequestShare(
                                  replyUid: r.uid,
                                  askerUid: post.authorUid,
                                  postId: post.id,
                                  peer: Peer(uid: r.uid, name: r.name, company: r.company, handle: r.handle, userType: r.userType, photoUrl: r.photoUrl, verification: r.verification),
                                ),
                              ]),
                  ),
                ),
              ),
            ]),
          ),
        if (referrers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: referrers.first.name, style: TextStyle(fontWeight: FontWeight.w700, color: p.text)),
                TextSpan(text: ' ${t(referrers.first.n == 1 ? 'referred a contact' : 'referred {n} contacts', {'n': referrers.first.n})}'),
                if (referrers.length > 1) TextSpan(text: ' · ${t('+{n} more', {'n': referrers.length - 1})}'),
              ]),
              style: TextStyle(fontSize: 12, color: p.muted),
            ),
          ),
        // last, after the replies and who referred: the rest are on the ask page
        if (total > shown || post.sharesCount > replies.length)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            // a gold pill, as on the web
            child: Material(
              color: kGold.withValues(alpha: .1),
              shape: StadiumBorder(side: BorderSide(color: kGold.withValues(alpha: .45))),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: onMore,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
                  child: Text('${t('Show all {n}', {'n': total})}  →', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.tagText)),
                ),
              ),
            ),
          ),
          ]),
        ),
      ]),
    );
  }
}

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
              // who responded: tapping the row opens their page
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: r.handle.isEmpty ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: r.handle))),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Avatar(name: displayName(r.userType, r.name, r.company), size: 20, photoUrl: r.photoUrl),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: displayName(r.userType, r.name, r.company), style: const TextStyle(fontWeight: FontWeight.w700)),
                          if (r.verification > 0)
                            WidgetSpan(
                                alignment: PlaceholderAlignment.middle, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: VerifiedBadge(level: r.verification, size: 13))),
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
                        child: Text(
                            '${r.rating == 1 ? '👍' : r.rating == -1 ? '👎' : ''}${r.reaction == null ? '' : kReactionEmoji[r.reaction] ?? ''}',
                            style: const TextStyle(fontSize: 12)),
                      ),
                    const SizedBox(width: 6),
                    Text(timeAgo(r.createdAt), style: TextStyle(fontSize: 12, color: p.muted)),
                  ]),
                ),
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

/// WhatsApp's mark, in its green (the Share sheet).
/// WhatsApp's mark, for share menus.
const whatsAppSvg = '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path fill="#25D366" d="M12 2a10 10 0 0 0-8.6 15.1L2 22l5-1.3A10 10 0 1 0 12 2zm0 18.2a8.2 8.2 0 0 1-4.2-1.2l-.3-.2-3 .8.8-2.9-.2-.3A8.2 8.2 0 1 1 12 20.2zm4.5-6.1c-.2-.1-1.5-.7-1.7-.8-.2-.1-.4-.1-.6.1l-.8 1c-.1.2-.3.2-.5.1a6.7 6.7 0 0 1-3.3-2.9c-.3-.4.2-.4.7-1.3.1-.2 0-.3 0-.4l-.8-1.8c-.2-.5-.4-.4-.6-.4h-.5a1 1 0 0 0-.7.3 2.9 2.9 0 0 0-.9 2.2 5.1 5.1 0 0 0 1.1 2.7 11.6 11.6 0 0 0 4.4 3.9c1.6.7 2.3.8 3.1.6.5-.1 1.5-.6 1.7-1.2.2-.6.2-1.1.2-1.2-.1-.1-.3-.2-.5-.3z"/></svg>';

/// An ask's chips on one line that scrolls sideways (a phone has no room to wrap them), as on the web.
class ChipLine extends StatelessWidget {
  final List<Widget> children;
  const ChipLine({super.key, required this.children});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 6), children[i]],
        ]),
      );
}

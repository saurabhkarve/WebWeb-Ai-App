import 'package:flutter/material.dart';
import 'hashtag_text.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../auth_provider.dart';
import '../ask_types.dart';
import '../card_colors.dart';
import 'ask_deck.dart';
import '../i18n.dart';
import '../links.dart';
import '../models.dart';
import '../safety.dart';
import '../screens/ask.dart';
import '../screens/contact_picker.dart';
import '../screens/find.dart';
import '../screens/p2.dart' show showAlertSheet;
import '../screens/post_detail.dart';
import '../screens/profile.dart';
import '../screens/talk.dart' show openChat;
import '../theme.dart';
import '../widgets.dart';
import 'area_map.dart';
import 'image_grid.dart';
import 'reaction_picker.dart';
import 'reply_thread.dart';
import 'p1.dart';
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

  Future<void> _openDetail({bool expandResponses = false, bool askOutcome = false}) async {
    if (widget.detail) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailScreen(postId: post.id, expandResponses: expandResponses, askOutcome: askOutcome)));
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
    if (_isOwner) return post.isRequirement ? toast(context, t('Responses to your ask are on its page')) : _openDetail();
    // the owner found someone (or no longer needs it): no new replies
    if (post.isRequirement && post.closed) return toast(context, t('This ask is closed'));
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
        repostedBy: p.repostedBy,
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
        outcome: p.outcome,
        wonBy: p.wonBy,
        leadReason: p.leadReason,
        leadNew: p.leadNew,
        fact: p.fact,
      );

  /// "Alert me for similar asks": the alert sheet, with this ask's category and place.
  Future<void> _alertSimilar() async {
    final r = await showAlertSheet(context, category: post.category, place: (post.locationPref ?? '').isEmpty ? null : post.locationPref);
    if (r != null && mounted) toast(context, t("Alert saved. We'll tell you when a similar ask comes in."));
  }

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
      if (isAsk && post.leadNew)
        // on "Leads for you": not seen yet, a NEW tag leading the title
        Text.rich(
          TextSpan(children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: kGold, borderRadius: BorderRadius.circular(4)),
                child: Text(t('NEW'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .4, color: kInk)),
              ),
            ),
            TextSpan(text: post.title ?? ''),
          ]),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.375, letterSpacing: -0.18),
        )
      else if (isAsk)
        HashtagText(post.title ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.375, letterSpacing: -0.18)),
      if (post.fact != null)
        FactCard(post.fact!)
      else if ((post.description ?? '').isNotEmpty)
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
    // the first link in the text gets a preview card (not a fact's: its source shows under it; not inside a repost's quote)
    final link = post.fact != null || post.repostedByName != null ? null : firstLink([post.title, post.description]);
    final extra = <Widget>[
      if (link != null) LinkPreviewCard(link, key: ValueKey(link)),
      if (post.fact != null && post.fact!.sourceUrl.isNotEmpty)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => openExternal(context, post.fact!.sourceUrl),
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              WIcon(WI.link, size: 13, color: p.muted),
              const SizedBox(width: 4),
              Flexible(
                child: Text('${t('Source')}: ${(post.fact!.sourceName ?? '').isNotEmpty ? post.fact!.sourceName : hostOf(post.fact!.sourceUrl)}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted)),
              ),
            ]),
          ),
        ),
    ];

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
              if (await showSafetySheet(
                    context,
                    uid: post.authorUid,
                    name: post.shownName,
                    postId: post.id,
                    saved: post.bookmarked,
                    onToggleSave: () => _actionsKey.currentState?.toggleBookmark(),
                    onAlert: post.isRequirement ? _alertSimilar : null,
                  ) &&
                  mounted) {
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
      // on "Leads for you" the card says why it is a lead for this member
      final why = mine ? t('Your ask') : ((post.leadReason ?? '').isNotEmpty ? leadReasonText(post.leadReason!) : (match == null ? null : t(match)));
      final tint = kCardColors[cardColorOf(post)]!;
      final spotlight = Container(
        padding: framed ? const EdgeInsets.fromLTRB(12, 12, 12, 0) : const EdgeInsets.symmetric(vertical: 20),
        // the asker's colour: a soft wash from the top-left corner and a hairline in the same colour
        decoration: framed ? null : BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tint.withValues(alpha: .16), tint.withValues(alpha: 0)], stops: const [0, .55])),
        foregroundDecoration: framed ? null : _HairlineDecoration(tint.withValues(alpha: .6)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: EdgeInsets.zero,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                GestureDetector(
                  onTap: _openAuthor,
                  child: Avatar(name: post.shownName, photoUrl: post.authorPhotoUrl, size: framed ? 32 : 40, ring: post.authorHasUpdate, type: post.authorType, uid: post.authorUid, badge: framed ? 14 : 15),
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
                if (!framed) ...more,
              ]),
              const SizedBox(height: 10),
              ...[
                // why you see this ask (or that it is closed), then the ask as swipeable cards
                // the ask type pinned above the cards, and why you see this ask (or that it is closed) on the right
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    WIcon(categoryIcon(askTypeDef(askTypeOf(post))?.icon ?? post.category), size: 14, color: p.link, still: true),
                    const SizedBox(width: 6),
                    Expanded(child: Text(askLabel(post).toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .4, color: p.link))),
                    if (post.closed || why != null) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: post.closed
                            ? ClosedChip(post)
                            : (!mine && match != null && post.leadReason == null && ((post.locationPref ?? '').isNotEmpty || post.lat != null)
                                ? GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => showAskAreaSheet(context, post), child: GoldTag(why!))
                                : GoldTag(why!)),
                      ),
                    ],
                  ]),
                ),
                // double tap gives it a thumbs up (with the burst), as on the text card
                GestureDetector(
                  onDoubleTap: _quickReact,
                  child: Stack(children: [
                    KeyedSubtree(
                      key: widget.tourTarget ? Tours.key('chips') : null,
                      child: AskDeck(
                        post: post,
                        mine: mine,
                        onOpen: _openDetail,
                        onReply: _reply,
                        onReplies: () => _openDetail(expandResponses: true),
                        onQuickReact: _quickReact,
                        onVoted: (v) => setState(() => post = v),
                        typeAbove: true,
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _burst,
                          builder: (_, __) {
                            if (!_burst.isAnimating) return const SizedBox.shrink();
                            final v = _burst.value;
                            final scale = v < .25 ? .4 + .85 * (v / .25) : (v < .6 ? 1.25 - .25 * ((v - .25) / .35) : 1 + .1 * ((v - .6) / .4));
                            final opacity = v < .25 ? v / .25 : (v < .6 ? 1.0 : 1 - (v - .6) / .4);
                            return Center(child: Opacity(opacity: opacity.clamp(0.0, 1.0), child: Transform.scale(scale: scale, child: const Text('👍', style: TextStyle(fontSize: 48)))));
                          },
                        ),
                      ),
                    ),
                  ]),
                ),
                ...extra,
              ],
              // a lead: how much competition there is, so the first few know to move
              if (!framed && post.leadReason != null) Competition(post.sharesCount),
              // my own ask, a few days in: "Did you find someone?"
              if (!framed && mine) OutcomeNudge(post: post, onTap: () => _openDetail(askOutcome: true)),
              // quoted in a repost: the replies and the controls are the repost's (below)
              if (!framed) ...[
                // the replies are on the ask page, not on the card
                PostActions(key: _actionsKey, post: post, onReply: _reply, onReview: _openDetail, spotlight: true, onChanged: () => setState(() {}), tourTarget: widget.tourTarget),
              ],
            ]),
          ),
        ]),
      );
      if (!framed) return spotlight;
      // reposted (Connect, a member's page), as on x.com: the repost is the row (who reposted, when, the menu), the ask sits
      // inside it as a quote set in from the left, and the replies and every control belong to the repost, at the row's
      // full width where they always are
      return _quoteRepost(p, spotlight, more);
    }

    final card = Container(
      padding: framed ? const EdgeInsets.all(12) : EdgeInsets.zero,
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
              if (!framed) ...more,
            ]),
            if (mine && isAsk) Padding(padding: const EdgeInsets.only(top: 6), child: GoldTag(t('Your ask'))),
            const SizedBox(height: 8),
            tappable,
            ...extra,
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
                    if (urgency != null && askDeadline(post) != null) InfoPill(small: true, wi: WI.calendar, text: askDeadline(post)!),
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
          ]),
        ),
      ]),
    );
    // an update has the same five controls as an ask (React · Reply · Refer · Views · Share), across the row's full
    // width under it, as on the web; quoted in a repost, the controls are the repost's
    if (!framed) {
      return Container(
        padding: const EdgeInsets.only(top: 16, bottom: 16),
        foregroundDecoration: _HairlineDecoration(kGold.withValues(alpha: .6)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          card,
          const SizedBox(height: 12),
          PostActions(key: _actionsKey, post: post, onReply: _reply, onReview: _openDetail, spotlight: true, onChanged: () => setState(() {}), tourTarget: widget.tourTarget),
        ]),
      );
    }
    return _quoteRepost(p, card, more, ask: false);
  }

  /// An ask someone reposted (x.com style): the reposter's row, the ask quoted in a light frame set in by the avatar's
  /// width and its gap, then the replies and the controls at full width.
  Widget _quoteRepost(Pal p, Widget quote, List<Widget> more, {bool ask = true}) {
    final r = post.repostedBy ?? const {};
    const green = Color(0xFF1F7A52);
    final ink = Theme.of(context).brightness == Brightness.dark ? const Color(0xFF7FD6AD) : green;
    void open() => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: post.repostedByHandle ?? '')));
    return Container(
      padding: EdgeInsets.symmetric(vertical: ask ? 16 : 20),
      foregroundDecoration: _HairlineDecoration(kGold.withValues(alpha: .6)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (ask)
          // an ask: one slim line says who reposted it (the ask below has its own author row, so a second big avatar and
          // name would read as the same person twice)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
            WIcon(WI.repost, size: 16, color: ink),
            const SizedBox(width: 8),
            GestureDetector(onTap: open, child: Avatar(name: post.repostedByName ?? '', photoUrl: r['photoURL'] as String?, size: 20)),
            const SizedBox(width: 6),
            Expanded(
              child: GestureDetector(
                onTap: open,
                behavior: HitTestBehavior.opaque,
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: post.repostedByName ?? '', style: TextStyle(fontWeight: FontWeight.w700, color: p.text)),
                    TextSpan(text: ' ${t('Reposted')}', style: TextStyle(fontWeight: FontWeight.w600, color: ink)),
                    if (post.repostedAt != null) TextSpan(text: ' · ${timeAgo(post.repostedAt!)}'),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.muted),
                ),
              ),
            ),
            ...more,
          ]),
            // the line under it bends down at both ends, over the ask it quotes
            Container(
              margin: const EdgeInsets.only(top: 8),
              height: 10,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(top: BorderSide(color: p.border.withValues(alpha: .7)), left: BorderSide(color: p.border.withValues(alpha: .7)), right: BorderSide(color: p.border.withValues(alpha: .7))),
              ),
            ),
          ])
        else
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: open,
            child: Avatar(name: post.repostedByName ?? '', photoUrl: r['photoURL'] as String?, size: 40, type: r['userType'] as String?, uid: r['uid'] as String?, badge: 15),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: open,
              behavior: HitTestBehavior.opaque,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(post.repostedByName ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.25))),
                  const SizedBox(width: 6),
                  VerifiedBadge(level: (r['verification'] as num?)?.toInt() ?? 0, premium: r['premium'] == true, plan: r['plan'] as String?),
                ]),
                Row(children: [
                  WIcon(WI.repost, size: 14, color: ink),
                  const SizedBox(width: 4),
                  Text(t('Reposted'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ink, height: 1.3)),
                  if (post.repostedAt != null) Text(' · ${timeAgo(post.repostedAt!)}', style: TextStyle(fontSize: 12, color: p.muted, height: 1.3)),
                ]),
              ]),
            ),
          ),
          ...more,
        ]),
        Padding(
          padding: EdgeInsets.only(left: ask ? 0 : 50, top: ask ? 0 : 4),
          // as on x.com (and the web) the whole quote is one link to the ask: a tap anywhere in it, the name and chips
          // included, opens the ask, so the quote's own taps are absorbed (an ask's cards still swipe, their taps open the ask)
          child: Material(
            color: Colors.transparent,
            // clipped, so the chips stay inside the frame
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: ask ? BorderSide.none : BorderSide(color: p.border)),
            child: ask ? quote : InkWell(onTap: _openDetail, child: AbsorbPointer(child: quote)),
          ),
        ),
        if (ask) ...[
          PostActions(key: _actionsKey, post: post, onReply: _reply, onReview: _openDetail, spotlight: true, onChanged: () => setState(() {}), tourTarget: widget.tourTarget),
        ] else ...[
          const SizedBox(height: 12),
          PostActions(key: _actionsKey, post: post, onReply: _reply, onReview: _openDetail, spotlight: true, onChanged: () => setState(() {}), tourTarget: widget.tourTarget),
        ],
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
    if (widget.post.closed) return toast(context, t('This ask is closed'));
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

  String get _subject => post.title ?? post.fact?.title ?? (post.isRequirement ? 'WebWeb AI ask' : 'WebWeb AI update');

  /// Refer on an update: pass it on to someone over WhatsApp.
  Future<void> _whatsApp() async {
    // for an ask, a group message that says what is wanted, where, and that replying is free
    final text = post.isRequirement
        ? '🔎 $_subject${(post.locationPref ?? '').isNotEmpty ? '\n📍 ${post.locationPref}' : ''}${(post.budget ?? '').isNotEmpty ? ' · ${post.budget}' : ''}\n${t('Can you help? Reply free on WEBWEB:')}\n${post.webUrl}'
        : '$_subject\n${post.webUrl}';
    final ok = await launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication).catchError((_) => false);
    if (ok) logShare(_api, 'post', post.id, channel: 'whatsapp');
  }

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
            // dark mode on a phone: no fill or outline at all, seamless as in light mode
            color: !wide && p.dark ? null : fill ?? p.card,
            borderRadius: radius,
            // on a phone no outline or shadow (Refer keeps its gold fill), as on the web
            border: wide ? Border.all(color: edge ?? p.border) : null,
            boxShadow: wide ? const [BoxShadow(color: Color(0x0D1E1E1E), blurRadius: 2, offset: Offset(0, 1))] : null,
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
            icon: reacted ? SizedBox(width: 18, height: 18, child: Center(child: ReactionGlyph(post.myReaction!, size: 15))) : WIcon(WI.thumbsUp, size: 18, color: p.muted),
            count: post.reactionsCount,
            color: reacted ? p.text : p.muted,
          ),
        ),
        if (mine && isAsk)
          pill(label: 'Review responses', icon: WIcon(WI.talk, size: 18, color: p.tagText), count: post.sharesCount, badge: p.tagBg, color: p.tagText, edge: kGold.withValues(alpha: .45), fill: kGold.withValues(alpha: .1), onTap: widget.onReview ?? widget.onReply)
        else ...[
          tour('reply', pill(label: 'Reply', icon: WIcon(WI.talk, size: 18, color: p.muted), count: isAsk ? post.sharesCount : 0, color: p.muted, onTap: widget.onReply)),
          // plain like the rest, in deep gold so it still leads (as on the web). An update has no one to put a contact in
          // touch with, so there Refer passes it on to someone over WhatsApp
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
                onTap: isAsk ? _refer : _whatsApp,
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
      // the full width, scrolling sideways only when the controls can't fit at all (FitRow)
      return FitRow(children: kids);
    }
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      ReactionPicker(
        quick: true,
        value: post.myReaction,
        onChange: react,
        trigger: (_) => btn(
          icon: reacted ? SizedBox(width: 20, height: 20, child: Center(child: ReactionGlyph(post.myReaction!, size: 15))) : WIcon(WI.thumbsUp, size: 20, color: p.muted),
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
  /// a repost doesn't invite "Be the first to respond": nothing shows until there are replies
  final bool hideEmpty;
  const LatestReplies({super.key, required this.post, required this.onMore, this.hideEmpty = false});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    // two on the card: the ask (title, words, chips) leads and the conversation follows a step quieter, as on the web
    final replies = post.latestReplies.take(2).toList();
    final referrers = post.referrers;
    final total = post.sharesCount + post.referralsCount;
    if (total == 0) {
      if (hideEmpty) return const SizedBox.shrink();
      return Padding(padding: const EdgeInsets.only(top: 12), child: Text(t('Be the first to respond'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.muted)));
    }
    final shown = replies.length + referrers.fold<int>(0, (n, r) => n + r.n);
    // open on the card (no panel of its own): a heading at the card's edge (talk icon, label, count, a hairline that
    // fades out), then the replies as compact bubbles set in under the author's name as a thread (the author avatar's 40
    // plus its 10 gap), and Show all n last, as on the web
    final any = replies.isNotEmpty || referrers.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(left: 20), child: Row(children: [
          WIcon(WI.talk, size: 16, color: kGold.withValues(alpha: .8)),
          const SizedBox(width: 8),
          Text(any ? t('Latest replies') : ResponseActivity.countLabel(post.sharesCount, post.referralsCount), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.muted)),
          if (any) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(99)),
              child: Text('$total', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: p.muted, fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ],
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, decoration: BoxDecoration(gradient: LinearGradient(colors: [kGold.withValues(alpha: .3), p.border, p.border.withValues(alpha: 0)])))),
        ])),
        Padding(
          // set in less on a phone, as on the web
          padding: const EdgeInsets.only(left: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final r in replies) Padding(padding: const EdgeInsets.only(top: 6), child: ReplyBubble(post: post, r: r)),
        if (referrers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: referrers.first.name, style: TextStyle(fontWeight: FontWeight.w600, color: p.text.withValues(alpha: .85))),
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
            // a quiet link, as on the web: the gold on the card is the ask's own
            child: InkWell(
              borderRadius: BorderRadius.circular(99),
              onTap: onMore,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 4, 8, 4),
                child: Text('${t('Show all {n}', {'n': total})}  →', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.muted)),
              ),
            ),
          ),
          ]),
        ),
      ]),
    );
  }
}

/// One reply as a compact bubble (web latest-replies.tsx ReplyBubble): who and when with the asker's feedback, what
/// they said (or that a contact was shared), and React and Reply from the name line.
class ReplyBubble extends StatelessWidget {
  final Post post;
  final ResponseLog r;
  const ReplyBubble({super.key, required this.post, required this.r});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    const bubble = BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(14), bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14));
    void openProfile(String handle) => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: handle)));
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.text.withValues(alpha: .85))),
                ),
              ),
              if (r.verification > 0) ...[const SizedBox(width: 4), VerifiedBadge(level: r.verification, size: 12)],
              const SizedBox(width: 6),
              Text(timeAgo(r.createdAt), style: TextStyle(fontSize: 11, color: p.muted)),
              // the asker's feedback on this reply
              if (r.rating != null || r.reaction != null) ...[
                const SizedBox(width: 4),
                Text('${r.rating == 1 ? '👍' : r.rating == -1 ? '👎' : ''}${r.reaction == null ? '' : kReactionEmoji[r.reaction] ?? ''}', style: const TextStyle(fontSize: 11)),
              ],
            ],
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: r.kind == 'info' && ((r.text ?? '').isNotEmpty || r.canDo)
                  ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      OfferChips(canDo: r.canDo, quote: r.quote, readyWhen: r.readyWhen),
                      // the bubble is ReplySocial's, with the name and time on top
                      if ((r.text ?? '').isNotEmpty)
                        HashtagText(r.text!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, height: 1.35, color: p.text.withValues(alpha: .75))),
                      // a link in the reply: its small preview card
                      if (firstLink([r.text]) case final link?) LinkPreviewCard(link, key: ValueKey(link), compact: true, margin: const EdgeInsets.only(top: 6)),
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
      ]);
  }
}

/// Every reply and referral on an ask ("Show all n" on the card opens it on the ask page; web AllReplies), drawn like
/// the card's latest replies: the same heading, the replies as bubbles members can react and reply to, and who referred.
/// 10 at a time: the next two pages load as the end comes into view, after that a button asks for each 10 more.
class AllReplies extends StatefulWidget {
  final Post post;
  final List<ResponseLog> items;
  const AllReplies({super.key, required this.post, required this.items});

  @override
  State<AllReplies> createState() => _AllRepliesState();
}

class _AllRepliesState extends State<AllReplies> {
  static const _page = 10, _autoPages = 3;
  int _shown = _page;
  final _end = GlobalKey();
  ScrollPosition? _pos;

  bool get _auto => _shown < _page * _autoPages;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pos?.removeListener(_check);
    _pos = Scrollable.maybeOf(context)?.position;
    _pos?.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _pos?.removeListener(_check);
    super.dispose();
  }

  /// the end marker is within 300 px of the screen: show the next page
  void _check() {
    if (!mounted || !_auto || _shown >= widget.items.length) return;
    final box = _end.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final y = box.localToGlobal(Offset.zero).dy;
    if (y < MediaQuery.of(context).size.height + 300) {
      setState(() => _shown += _page);
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final rest = items.length - _shown;
    final p = Pal.of(context);
    void openProfile(String handle) => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: handle)));
    String shown(ResponseLog r) => r.userType == 'entrepreneur' && r.company.isNotEmpty ? r.company : r.name;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          WIcon(WI.talk, size: 16, color: kGold.withValues(alpha: .8)),
          const SizedBox(width: 8),
          Text(ResponseActivity.countLabel(post.sharesCount, post.referralsCount), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.muted)),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, decoration: BoxDecoration(gradient: LinearGradient(colors: [kGold.withValues(alpha: .3), p.border, p.border.withValues(alpha: 0)])))),
        ]),
        Padding(
          padding: const EdgeInsets.only(left: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final r in items.take(_shown))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: r.kind == 'referral'
                    ? Row(children: [
                        GestureDetector(onTap: () => openProfile(r.handle), child: Avatar(name: shown(r), photoUrl: r.photoUrl, size: 24)),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(text: shown(r), style: TextStyle(fontWeight: FontWeight.w600, color: p.text.withValues(alpha: .85))),
                              TextSpan(text: ' ${t('referred a contact')} · ${timeAgo(r.createdAt)}'),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: p.muted),
                          ),
                        ),
                      ])
                    : ReplyBubble(post: post, r: r),
              ),
            if (rest > 0)
              _auto
                  ? SizedBox(key: _end, height: 24)
                  : Padding(
                      padding: const EdgeInsets.only(top: 8, left: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _shown += _page),
                        child: Text(t('Show {n} more replies', {'n': rest < _page ? rest : _page}), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kGold)),
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
                          TextSpan(text: ' ${t(r.canDo ? 'can do this' : (_verb[r.kind] ?? 'responded'))}', style: TextStyle(color: p.muted)),
                          if ((r.quote ?? '').isNotEmpty) TextSpan(text: ' · ${r.quote}', style: const TextStyle(fontWeight: FontWeight.w600)),
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

/// A WEBWEB Facts post as a data card (web post-card.tsx FactCard): the big figure, what it counts, the fact and why it
/// matters, on a soft gold glow.
class FactCard extends StatelessWidget {
  final PostFact fact;
  const FactCard(this.fact, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kGold.withValues(alpha: .4)),
        gradient: RadialGradient(center: const Alignment(1, -1), radius: 1.2, colors: [kGold.withValues(alpha: .28), kGold.withValues(alpha: 0)], stops: const [0, .6]),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('📊 ${t('Facts & figures near you')}'.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.3, color: p.tagText)),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(fact.emoji, style: const TextStyle(fontSize: 36, height: 1)),
          const SizedBox(width: 12),
          Expanded(child: Text(fact.figure, style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, height: 1, letterSpacing: -1, color: p.text))),
        ]),
        const SizedBox(height: 6),
        Text(fact.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.3)),
        const SizedBox(height: 12),
        Text(fact.title, style: const TextStyle(fontSize: 15, height: 1.35)),
        if ((fact.body ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(fact.body!, style: TextStyle(fontSize: 14, height: 1.35, color: p.text.withValues(alpha: .7))),
        ],
      ]),
    );
  }
}

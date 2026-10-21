import 'package:flutter/material.dart';
import '../widgets/hashtag_text.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../auth_provider.dart';
import '../i18n.dart';
import '../views.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/city_picker.dart';
import '../widgets/area_map.dart';
import '../widgets/image_grid.dart';
import '../widgets/p1.dart';
import '../widgets/post_card.dart';
import '../widgets/reaction_picker.dart';
import '../widgets/response_sheet.dart';
import 'ask.dart';
import 'find.dart';
import 'profile.dart';
import 'talk.dart' show openChat;

const _kindWord = {'contact': 'your contact', 'media': 'a photo', 'info': 'some information'};

/// One ask or update (web post/[id]). Visitors respond (contact / photo / info), then see the status
/// and the owner's feedback; the owner sees who responded, rates them, and the referred contacts.
class PostDetailScreen extends StatefulWidget {
  final String postId;
  final bool openReply;

  /// "+N more" from the feed: open with the whole response log shown
  final bool expandResponses;

  /// "Did you find someone?" (the push, or the line on the feed): open with the question in view
  final bool askOutcome;
  const PostDetailScreen({super.key, required this.postId, this.openReply = false, this.expandResponses = false, this.askOutcome = false});
  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  Post? _post;
  // the owner's responses section, where "Review responses" scrolls to
  final _responsesKey = GlobalKey();
  // the owner's "Did you find someone?"
  final _outcomeKey = GlobalKey();
  bool _scrolledToOutcome = false;
  // the full response log, once "+N more" is tapped
  List<ResponseLog>? _allResponses;
  bool _missing = false;
  MyResponse? _mine;
  List<ContactShare> _shares = [];
  List<Referral> _referrals = []; // owner: everyone's referrals; visitor: just mine
  bool _busy = false;
  bool _openedReply = false;

  Api get _api => context.read<AuthProvider>().api;
  String? get _me => context.read<AuthProvider>().profile?.uid;
  bool get _isOwner => _post != null && _post!.authorUid == _me;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _loadAllResponses() async {
    try {
      final list = ((await _api.get('/posts/${_post!.id}/activity')) as List).map((e) => ResponseLog.fromJson(e as Map)).toList();
      if (mounted) setState(() => _allResponses = list);
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final p = Post.fromJson(await _api.get('/posts/${widget.postId}') as Map);
      // opening someone else's post counts as seeing it
      if (p.authorUid != _me) ViewTracker.record(_api, p.id);
      List<ContactShare> shares = [];
      List<Referral> refs = [];
      MyResponse? mine;
      if (p.isRequirement) {
        if (p.authorUid == _me) {
          shares = ((await _api.get('/posts/${p.id}/shares')) as List).map((e) => ContactShare.fromJson(e as Map)).toList();
          refs = ((await _api.get('/posts/${p.id}/referrals')) as List).map((e) => Referral.fromJson(e as Map)).toList();
        } else {
          mine = MyResponse.fromJson(await _api.get('/posts/${p.id}/share/me') as Map);
          refs = ((await _api.get('/app/posts/${p.id}/referrals/mine')) as List).map((e) => Referral.fromJson(e as Map)).toList();
        }
      }
      if (!mounted) return;
      setState(() {
        _post = p;
        _mine = mine;
        _shares = shares;
        _referrals = refs;
      });
      if (widget.expandResponses && _allResponses == null && p.isRequirement && p.authorUid != _me) _loadAllResponses();
      if (widget.askOutcome && !_scrolledToOutcome && p.authorUid == _me) {
        _scrolledToOutcome = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final c = _outcomeKey.currentContext;
          if (c != null) Scrollable.ensureVisible(c, alignment: .3, duration: const Duration(milliseconds: 300));
        });
      }
      if (widget.openReply && !_openedReply && p.isRequirement && !p.closed && p.authorUid != _me && mine != null && !mine.shared) {
        _openedReply = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _respond());
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _missing = e.status == 404 || _post == null);
    }
  }

  Future<void> _respond({ExistingResponse? existing}) async {
    // the owner found someone (or no longer needs it): no new replies, though a reply already sent can still be edited
    if (existing == null && _post!.closed) return toast(context, t('This ask is closed'));
    if (await showResponseSheet(context, _post!.id, existing: existing)) _load();
  }

  ExistingResponse _existing(MyResponse m) =>
      ExistingResponse(m.kind ?? 'contact', text: m.text, imageUrl: m.imageUrl, canDo: m.canDo, quote: m.quote, readyWhen: m.readyWhen);

  /// Who the owner can say they chose: everyone who replied or referred, once each.
  List<Responder> get _responders {
    final out = <Responder>[];
    void add(String? uid, String? name, String? photo) {
      if (uid == null || out.any((r) => r.uid == uid)) return;
      out.add(Responder(uid, name ?? '', photo));
    }
    for (final s in _shares) {
      add(s.sharerUid, s.sharerName, s.sharerPhotoUrl);
    }
    for (final r in _referrals) {
      add(r.referrerUid, r.referrerName, r.referrerPhotoUrl);
    }
    return out;
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
      await _load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withdraw() async {
    if (!await _confirm(t('Delete your response?'), t('The owner will no longer see it.'), t('Delete'))) return;
    await _run(() async => _api.delete('/posts/${_post!.id}/share'));
  }

  /// Save / remove from saved (it left the row under the ask; on this page it sits by the author).
  Future<void> _toggleSave() async {
    final post = _post!;
    final on = !post.bookmarked;
    setState(() => post.bookmarked = on);
    try {
      on ? await _api.post('/posts/${post.id}/bookmark') : await _api.delete('/posts/${post.id}/bookmark');
      if (mounted) toast(context, t(on ? 'Saved' : 'Removed from saved'));
    } catch (_) {
      if (mounted) setState(() => post.bookmarked = !on);
    }
  }

  Future<void> _removeAsk() async {
    if (!await _confirm(t('Delete this ask?'), t("It will be removed from the feed along with its responses and referrals. This can't be undone."), t('Delete'), cancel: t('Keep'))) return;
    setState(() => _busy = true);
    try {
      await _api.delete('/posts/${_post!.id}');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, '$e', error: true);
      }
    }
  }

  Future<void> _deleteReferral(Referral r) async {
    if (!await _confirm(t('Remove this contact?'), t('{name} will no longer be shared with {owner}.', {'name': r.name, 'owner': _post!.authorName}), t('Remove'))) return;
    try {
      await _api.delete('/app/posts/${_post!.id}/referrals/${r.id}');
      if (mounted) {
        toast(context, t('Removed'));
        _load();
      }
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  Future<bool> _confirm(String title, String body, String yes, {String? cancel}) async {
    final p = Pal.of(context);
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        content: Text(body, style: TextStyle(fontSize: 14, color: p.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(cancel ?? t('Cancel'), style: TextStyle(color: p.text, fontWeight: FontWeight.w700))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(yes, style: TextStyle(color: p.danger, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    return r == true;
  }

  void _message(String uid, {String name = '', String company = '', String handle = '', String? photo, String? type}) =>
      openChat(context, Peer(uid: uid, name: name, company: company, handle: handle, photoUrl: photo, userType: type ?? 'entrepreneur'));

  Future<void> _editAsk() async {
    // an ask is edited in the full Ask editor; an update in the small sheet
    if (_post!.isRequirement) {
      final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => SubPage(title: t('Edit ask'), body: AskScreen(onPosted: () {}, edit: _post))));
      if (saved == true) _load();
      return;
    }
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.of(context).canvas,
      barrierColor: kInk.withValues(alpha: .6),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _EditAskSheet(post: _post!),
    );
    if (saved == true) _load();
  }

  /// A chip opens Find with every ask sharing that city / budget / timing (as on the feed card).
  void _openFind({String? location, String? budget, String? urgency}) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => FindScreen(standalone: true, initialLocation: location, initialBudget: budget, initialUrgency: urgency)),
      );

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final post = _post;
    if (post == null) {
      return SubPage(
        title: '',
        body: _missing ? EmptyState(title: t('Not found')) : const Center(child: LogoLoader()),
      );
    }
    final isAsk = post.isRequirement;
    final owner = _isOwner;
    final hasDetails = (post.locationPref ?? '').isNotEmpty || (post.budget ?? '').isNotEmpty || (post.urgency ?? '').isNotEmpty;
    // why you see this ask, as on the feed card
    final why = owner ? t('Your ask') : ((post.matchReason ?? '').isEmpty ? null : t(post.matchReason!));
    final won = post.closed && post.wonBy != null && post.wonBy == _me;

    Widget iconBtn(WI icon, String label, VoidCallback onTap, {Color? color}) => Semantics(
          button: true,
          label: label,
          child: InkResponse(onTap: onTap, radius: 20, child: Padding(padding: const EdgeInsets.all(8), child: WIcon(icon, size: 20, color: color ?? p.muted))),
        );

    return SubPage(
      title: t(isAsk ? 'Ask' : 'Update'),
      body: LogoRefresh(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 32),
          // an ask reads like its feed card (post_card.dart): who asked, the category with why you see it, the ask, its
          // essentials as chips, the latest replies, then Refer and Reply
          children: [
            // author row
            Row(children: [
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: post.authorHandle))),
                child: Avatar(name: post.shownName, photoUrl: post.authorPhotoUrl, size: 40, ring: post.authorHasUpdate, type: post.authorType, uid: post.authorUid, badge: 15),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: post.authorHandle))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text(post.shownName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.25))),
                      if (post.authorVerification > 0 || post.authorPremium || post.authorPlan != null) ...[const SizedBox(width: 6), VerifiedBadge(level: post.authorVerification, premium: post.authorPremium, plan: post.authorPlan)],
                    ]),
                    Text('${post.authorType == 'entrepreneur' ? post.authorName : post.authorCompany} · ${timeAgo(post.createdAt)}${post.editedAt != null ? ' · ${editedLabel(post.editedAt!)}' : ''}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted, height: 1.3)),
                  ]),
                ),
              ),
              Semantics(
                button: true,
                label: t(post.bookmarked ? 'Remove from saved' : 'Save'),
                child: InkResponse(
                  onTap: _toggleSave,
                  radius: 20,
                  child: Padding(padding: const EdgeInsets.all(8), child: WIcon(WI.bookmark, size: 20, color: post.bookmarked ? p.link : p.muted, fill: post.bookmarked)),
                ),
              ),
              if (owner) ...[
                iconBtn(WI.edit, t('Edit ask'), _editAsk),
                iconBtn(WI.trash, t('Delete ask'), _removeAsk, color: p.danger),
              ],
            ]),
            SizedBox(height: isAsk ? 12 : 20),
            if (isAsk) ...[
              // the category as a small heading, why you see this ask on the right
              Row(children: [
                WIcon(categoryIcon(post.category), size: 14, color: p.link, still: true),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(t(post.categoryText).toUpperCase(),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .6, color: p.link)),
                ),
                if (post.closed) ...[const SizedBox(width: 8), Flexible(child: ClosedChip(post))]
                else if (why != null) ...[const SizedBox(width: 8), Flexible(child: GoldTag(why))],
              ]),
              const SizedBox(height: 4),
              HashtagText(post.title ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.3)),
              const SizedBox(height: 4),
            ],
            if ((post.description ?? '').isNotEmpty)
              HashtagText(post.description!, selectable: true,
                  style: isAsk ? TextStyle(fontSize: 15, height: 1.375, color: p.text.withValues(alpha: .75)) : const TextStyle(fontSize: 18, height: 1.375)),
            ImageGrid(post.images, shareUrl: post.webUrl, shareRef: post.id),
            // the essentials as chips, like the feed card (the category is the heading above)
            if (hasDetails || (post.radiusM ?? 0) > 0) ...[
              const SizedBox(height: 12),
              ChipLine(children: [
                if ((post.locationPref ?? '').isNotEmpty)
                  InfoPill(
                    gold: true,
                    wi: WI.pin,
                    text: '${t(post.locationPref!)}${post.distanceM == null ? '' : ' · ${formatDistance(post.distanceM!)}'}',
                    onTap: () => showAskAreaSheet(context, post),
                  ),
                if ((post.budget ?? '').isNotEmpty) InfoPill(gold: true, wi: WI.rupee, text: post.budget!, onTap: () => _openFind(budget: post.budget)),
                if ((post.urgency ?? '').isNotEmpty)
                  InfoPill(gold: true, wi: WI.clock, text: askTimeLeft(post)!, onTap: () => _openFind(urgency: post.urgency)),
                if ((post.radiusM ?? 0) > 0) InfoPill(gold: true, wi: WI.locate, text: t('{d} reach', {'d': formatDistance(post.radiusM!)}), onTap: () => showAskAreaSheet(context, post)),
              ]),
            ],
            if (won) ...[const SizedBox(height: 12), WinnerBanner(ownerName: post.shownName)],
            if (isAsk) ...[
              // the latest replies in public, as on the card; "Show all" opens every reply and referral in the same style
              if (!owner && _allResponses == null) LatestReplies(post: post, onMore: _loadAllResponses),
              if (!owner && _allResponses != null) AllReplies(post: post, items: _allResponses!),
            ],
            SizedBox(height: isAsk ? 12 : 20),
            if (isAsk)
              PostActions(
                post: post,
                spotlight: true,
                onChanged: () => setState(() {}),
                onReview: () {
                  final c = _responsesKey.currentContext;
                  if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 300));
                },
                onReply: () {
                  final mine = _mine;
                  if (mine?.shared == true) {
                    _respond(existing: _existing(mine!));
                  } else {
                    _respond();
                  }
                },
              )
            else
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: p.border))),
              child: PostActions(
                post: post,
                onChanged: () => setState(() {}),
                onReply: () {
                  if (owner) return toast(context, t('Responses to your ask are on its page'));
                  if (isAsk && _mine?.shared != true) {
                    _respond();
                    return;
                  }
                  _message(post.authorUid, name: post.authorName, company: post.authorCompany, handle: post.authorHandle, photo: post.authorPhotoUrl, type: post.authorType);
                },
              ),
            ),
            const SizedBox(height: 20),
            // updates have no response flow: just offer a message
            if (!owner && !isAsk)
              GoldButton(
                label: '${t('Message')} ${post.authorName.split(' ').first}',
                wi: WI.talk,
                outlined: true,
                onPressed: () => _message(post.authorUid, name: post.authorName, company: post.authorCompany, handle: post.authorHandle, photo: post.authorPhotoUrl, type: post.authorType),
              ),
            if (!owner && isAsk) _visitor(post, p),
            // the owner: how the ask ended, or "Did you find someone?" (prominent once it is due, or when the push led here)
            if (owner && isAsk)
              Padding(
                key: _outcomeKey,
                padding: const EdgeInsets.only(bottom: 16),
                child: OutcomeCard(post: post, responders: _responders, prominent: widget.askOutcome || outcomeDue(post), onChanged: _load),
              ),
            if (owner && isAsk) KeyedSubtree(key: _responsesKey, child: _ownerSection(post, p)),
            if (!owner && _referrals.isNotEmpty) _myReferrals(p),
          ],
        ),
      ),
    );
  }

  // ---------- visitor ----------
  Widget _visitor(Post post, Pal p) {
    final mine = _mine;
    // Reply in the row above opens the sheet; once you replied, its status and what you can do with it
    if (mine == null || !mine.shared) return const SizedBox.shrink();
    final kind = _kindWord[mine.kind ?? 'contact'] ?? 'your contact';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          const WIcon(WI.checkCircle, size: 20, color: Color(0xFF059669)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${t('You shared')} ${t(kind)}${mine.rating == 1 ? ' · 👍 ${t('from owner')}' : ''}${mine.rating == -1 ? ' · 👎 ${t('from owner')}' : ''}${mine.ownerReaction != null ? ' · ${kReactionEmoji[mine.ownerReaction]}' : ''}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ]),
      ),
      if (mine.askStatus == 'asked') ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t('{name} asked you to share it with them.', {'name': post.authorName}), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            Text(t('Approve to reveal {what} to the owner.', {'what': t(kind)}), style: TextStyle(fontSize: 12, color: p.muted)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: GoldButton(label: t('Approve'), height: 40, loading: _busy, onPressed: () => _run(() async => _api.post('/posts/${post.id}/share/answer', {'approve': true})))),
              const SizedBox(width: 8),
              Expanded(
                  child:
                      GoldButton(label: t('Decline'), height: 40, outlined: true, onPressed: _busy ? null : () => _run(() async => _api.post('/posts/${post.id}/share/answer', {'approve': false})))),
            ]),
          ]),
        ),
      ],
      if (mine.askStatus == 'approved') Padding(padding: const EdgeInsets.only(top: 12), child: Text(t('The owner can see what you shared.'), style: TextStyle(fontSize: 14, color: p.muted))),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: GoldButton(
            label: t('Edit response'),
            height: 40,
            outlined: true,
            onPressed: _busy ? null : () => _respond(existing: _existing(mine)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: _DangerButton(label: t('Delete response'), onPressed: _busy ? null : _withdraw)),
      ]),
      const SizedBox(height: 12),
      GoldButton(
        label: '${t('Message')} ${post.authorName.split(' ').first}',
        wi: WI.talk,
        outlined: true,
        onPressed: () => _message(post.authorUid, name: post.authorName, company: post.authorCompany, handle: post.authorHandle, photo: post.authorPhotoUrl, type: post.authorType),
      ),
    ]);
  }

  Widget _myReferrals(Pal p) => Container(
        margin: const EdgeInsets.only(top: 20),
        padding: const EdgeInsets.only(top: 16),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('Contacts you referred'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          for (var i = 0; i < _referrals.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: i == 0 ? null : BoxDecoration(border: Border(top: BorderSide(color: p.border))),
              child: Row(children: [
                Avatar(name: _referrals[i].name, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_referrals[i].name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    Text(_referrals[i].phone, style: TextStyle(fontSize: 14, color: p.link)),
                  ]),
                ),
                InkResponse(onTap: () => _deleteReferral(_referrals[i]), radius: 20, child: Padding(padding: const EdgeInsets.all(8), child: WIcon(WI.trash, size: 20, color: p.danger))),
              ]),
            ),
        ]),
      );

  // ---------- owner ----------
  Widget _ownerSection(Post post, Pal p) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.only(top: 16),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('Responses'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (_shares.isEmpty)
            EmptyState(title: t('No responses yet'), hint: t('People who respond will appear here.'))
          else
            for (var i = 0; i < _shares.length; i++) _ShareTile(postId: post.id, share: _shares[i], first: i == 0, onChanged: _load),
        ]),
      ),
      if (_referrals.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 20),
          padding: const EdgeInsets.only(top: 16),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t('Referred contacts'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            for (var i = 0; i < _referrals.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: i == 0 ? null : BoxDecoration(border: Border(top: BorderSide(color: p.border))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '${_referrals[i].name} · ', style: const TextStyle(fontWeight: FontWeight.w700)),
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () => launchUrl(Uri(scheme: 'tel', path: _referrals[i].phone.replaceAll(' ', ''))),
                            child: Text(_referrals[i].phone, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.link)),
                          ),
                        ),
                      ]),
                      style: const TextStyle(fontSize: 16)),
                  if ((_referrals[i].note ?? '').isNotEmpty) Text(_referrals[i].note!, style: const TextStyle(fontSize: 14)),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${t('Referred by')} '),
                      TextSpan(text: _referrals[i].referrerName ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: ' · ${timeAgo(_referrals[i].createdAt)}'),
                    ]),
                    style: TextStyle(fontSize: 12, color: p.muted),
                  ),
                ]),
              ),
          ]),
        ),
    ]);
  }
}

class _DangerButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const _DangerButton({required this.label, this.onPressed});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Opacity(
      opacity: onPressed == null ? .5 : 1,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          height: 40,
          decoration: BoxDecoration(color: p.chip, border: Border.all(color: p.border.withValues(alpha: .7)), borderRadius: BorderRadius.circular(20)),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onPressed,
            child: Center(child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.danger))),
          ),
        ),
      ),
    );
  }
}

/// Owner's row for one responder (web response-log.tsx): who + what type, the content once they
/// approved, thumbs up / down, a reaction and Message.
class _ShareTile extends StatefulWidget {
  final String postId;
  final ContactShare share;
  final bool first;
  final VoidCallback onChanged;
  const _ShareTile({required this.postId, required this.share, required this.first, required this.onChanged});
  @override
  State<_ShareTile> createState() => _ShareTileState();
}

class _ShareTileState extends State<_ShareTile> {
  bool _busy = false;
  ContactShare get s => widget.share;
  Api get _api => context.read<AuthProvider>().api;

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
      widget.onChanged();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rate(Map<String, dynamic> body) => _run(() async => _api.post('/posts/${widget.postId}/shares/${s.sharerUid}/rate', body));

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    const label = {'contact': 'Contact', 'media': 'Photo', 'info': 'Info'};
    Widget thumb(WI icon, bool on, Color onBg, Color onFg, VoidCallback onTap) => GestureDetector(
          onTap: _busy ? null : onTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(shape: BoxShape.circle, color: on ? onBg : Colors.transparent),
            child: WIcon(icon, size: 20, color: on ? onFg : p.muted),
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: widget.first ? null : BoxDecoration(border: Border(top: BorderSide(color: p.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          // photo and name both open their page
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: (s.sharerHandle ?? '').isEmpty ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: s.sharerHandle!))),
              child: Row(children: [
                Avatar(name: s.sharerName, photoUrl: s.sharerPhotoUrl, size: 44, type: s.sharerType, badge: 18, uid: s.sharerUid),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.sharerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.25)),
                    Text(s.sharerCompany, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: p.muted, height: 1.25)),
                  ]),
                ),
              ]),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(6)),
            child: Text(s.canDo ? t('Offer') : '${t(label[s.kind] ?? s.kind)} ${t('shared')}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 8),
        OfferChips(canDo: s.canDo, quote: s.quote, readyWhen: s.readyWhen),
        // what they shared: the owner only, once revealed
        if ((s.payload ?? '').isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.field, borderRadius: BorderRadius.circular(8)),
            child: s.kind == 'media'
                ? GestureDetector(
                    onTap: () => openImageViewer(context, [s.payload!], 0),
                    child: ClipRRect(borderRadius: BorderRadius.circular(8), child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 256), child: NetImg(s.payload!, fit: BoxFit.contain))),
                  )
                : s.kind == 'contact'
                    ? GestureDetector(
                        onTap: () => launchUrl(Uri(scheme: 'tel', path: s.payload!.replaceAll(' ', ''))),
                        child: Row(children: [WIcon(WI.phone, size: 16, color: p.text), const SizedBox(width: 8), Text(s.payload!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))]),
                      )
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        HashtagText(s.payload!, selectable: true, style: const TextStyle(fontSize: 14)),
                        // a photo sent with the note
                        if ((s.imageUrl ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: GestureDetector(
                              onTap: () => openImageViewer(context, [s.imageUrl!], 0),
                              child: ClipRRect(borderRadius: BorderRadius.circular(8), child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 256), child: NetImg(s.imageUrl!, fit: BoxFit.contain))),
                            ),
                          ),
                      ]),
          )
        else if (!s.canDo)
          Row(children: [
            Expanded(
              child: Text(
                t(s.askStatus == 'asked' ? 'Waiting for them to approve.' : (s.askStatus == 'declined' ? 'They declined. You can ask again.' : 'Content is private until they approve.')),
                style: TextStyle(fontSize: 12, color: p.muted),
              ),
            ),
            GestureDetector(
              onTap: s.askStatus == 'asked' || _busy ? null : () => _run(() async => _api.post('/posts/${widget.postId}/shares/${s.sharerUid}/ask')),
              child: Text(t(s.askStatus == 'asked' ? 'Asked ✓' : 'Ask to share'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: s.askStatus == 'asked' ? p.muted : p.link)),
            ),
          ]),
        const SizedBox(height: 4),
        Row(children: [
          thumb(WI.thumbsUp, s.rating == 1, const Color(0xFFD1FAE5), const Color(0xFF047857), () => _rate({'rating': s.rating == 1 ? null : 1})),
          const SizedBox(width: 4),
          thumb(WI.thumbsDown, s.rating == -1, const Color(0xFFFFE4E6), const Color(0xFFBE123C), () => _rate({'rating': s.rating == -1 ? null : -1})),
          const SizedBox(width: 4),
          ReactionPicker(
            value: s.ownerReaction,
            onChange: (r) => _rate({'reaction': r}),
            trigger: (_) => Container(
              height: 36,
              constraints: const BoxConstraints(minWidth: 36),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              // the React heart used everywhere else (an emoji once a reaction is picked)
              child: s.ownerReaction == null || kReactionEmoji[s.ownerReaction] == null
                  ? WIcon(WI.heart, size: 20, color: p.muted)
                  : Text(kReactionEmoji[s.ownerReaction]!, style: const TextStyle(fontSize: 18)),
            ),
          ),
          const Spacer(),
          GoldButton(
            label: t('Message'),
            wi: WI.talk,
            height: 32,
            outlined: true,
            onPressed: () => openChat(
                context, Peer(uid: s.sharerUid, name: s.sharerName, company: s.sharerCompany, handle: s.sharerHandle ?? '', photoUrl: s.sharerPhotoUrl, userType: s.sharerType ?? 'entrepreneur')),
          ),
        ]),
      ]),
    );
  }
}

/// Owner edits an ask (web edit-ask-sheet.tsx): title, category, description, location, urgency, budget.
class _EditAskSheet extends StatefulWidget {
  final Post post;
  const _EditAskSheet({required this.post});
  @override
  State<_EditAskSheet> createState() => _EditAskSheetState();
}

class _EditAskSheetState extends State<_EditAskSheet> {
  late final _title = TextEditingController(text: widget.post.title ?? '');
  late final _desc = TextEditingController(text: widget.post.description ?? '');
  late final _budget = TextEditingController(text: widget.post.budget ?? '');
  late String _category = widget.post.category ?? 'other';
  late String _location = widget.post.locationPref ?? '';
  late String _urgency = widget.post.urgency ?? '';
  bool _busy = false;
  String? _error;

  bool get _isAsk => widget.post.isRequirement;
  bool get _ready => _isAsk ? _title.text.trim().length >= 5 && _desc.text.trim().length >= 20 : _desc.text.trim().isNotEmpty || widget.post.images.isNotEmpty;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = context.read<AuthProvider>().api;
      await api.patch(
        '/posts/${widget.post.id}',
        _isAsk
            ? {'title': _title.text.trim(), 'description': _desc.text.trim(), 'category': _category, 'locationPref': _location, 'budget': _budget.text.trim(), 'urgency': _urgency}
            : {'text': _desc.text.trim(), 'images': widget.post.images},
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _budget.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .92),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(t(_isAsk ? 'Edit ask' : 'Edit update'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            GestureDetector(onTap: () => Navigator.pop(context), child: WIcon(WI.close, size: 24, color: p.text)),
          ]),
          const SizedBox(height: 16),
          if (_isAsk) ...[
            AppField(controller: _title, label: t('Title *'), maxLength: 100, onChanged: (_) => setState(() {})),
            const SizedBox(height: 12),
            Text(t('Category'), style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 6),
            SelectPill(
                value: _category,
                placeholder: t('Category'),
                rounded: false,
                height: 44,
                options: [for (final o in kPostCategories) Option(o.value, t(o.label))],
                onChanged: (v) => setState(() => _category = v.isEmpty ? _category : v)),
            const SizedBox(height: 12),
          ],
          AppField(controller: _desc, label: t(_isAsk ? 'Description *' : 'Description'), maxLines: 5, maxLength: _isAsk ? 300 : 1000, onChanged: (_) => setState(() {})),
          if (_isAsk) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('Location'), style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 6),
                  CityPill(value: _location, anyLabel: t('Anywhere'), onChanged: (c) => setState(() => _location = c.name)),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('Urgency'), style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 6),
                  SelectPill(
                      value: _urgency,
                      placeholder: t('Any time'),
                      rounded: false,
                      height: 44,
                      options: [for (final o in kUrgencies) Option(o.value, t(o.label))],
                      onChanged: (v) => setState(() => _urgency = v)),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            AppField(controller: _budget, label: t('Budget'), hint: 'e.g. ₹25,000 - ₹35,000', maxLength: 60),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(fontSize: 14, color: p.danger))),
          const SizedBox(height: 16),
          GoldButton(label: t('Save changes'), loading: _busy, onPressed: _ready ? _save : null),
        ]),
      ),
    );
  }
}

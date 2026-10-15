import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../auth_provider.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/post_card.dart';
import 'profile.dart';
import 'talk.dart' show openChat;

/// One post. Visitors can respond (share contact / photo / info) and answer the owner's "ask to share";
/// the owner sees who responded (content only after approval), can rate them, and sees referred contacts.
class PostDetailScreen extends StatefulWidget {
  final String postId;
  final bool openReply;
  const PostDetailScreen({super.key, required this.postId, this.openReply = false});
  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  Post? _post;
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

  Future<void> _load() async {
    try {
      final p = Post.fromJson(await _api.get('/posts/${widget.postId}') as Map);
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
      if (widget.openReply && !_openedReply && p.isRequirement && p.authorUid != _me && mine != null && !mine.shared) {
        _openedReply = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _respond());
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _missing = e.status == 404 || _post == null);
    }
  }

  Future<void> _respond() async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RespondSheet(postId: _post!.id),
    );
    if (done == true) _load();
  }

  Future<void> _answer(bool approve) async {
    setState(() => _busy = true);
    try {
      await _api.post('/posts/${_post!.id}/share/answer', {'approve': approve});
      await _load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteReferral(Referral r) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this contact?'),
        content: Text('${r.name} will no longer be shared with ${_post!.authorName}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await _api.delete('/app/posts/${_post!.id}/referrals/${r.id}');
      if (mounted) {
        toast(context, 'Removed');
        _load();
      }
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final post = _post;
    return Scaffold(
      appBar: AppBar(title: Text(post == null ? '' : (post.isRequirement ? 'Ask' : 'Update'), style: const TextStyle(fontWeight: FontWeight.w700))),
      body: post == null
          ? (_missing ? Center(child: Text('Post not found', style: TextStyle(color: p.muted, fontWeight: FontWeight.w600))) : const PageLoader())
          : RefreshIndicator(
              color: kGold,
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
                PostCard(post: post, detail: true, onReply: _isOwner || !post.isRequirement ? null : _respond, onChanged: () {}),
                const SizedBox(height: 14),
                if (!_isOwner && !post.isRequirement)
                  SizedBox(
                    width: double.infinity,
                    child: GoldButton(label: 'Message ${post.authorName.split(' ').first}', outlined: true, icon: Icons.chat_bubble_outline, onPressed: () => openChat(context, Peer(uid: post.authorUid, name: post.authorName, company: post.authorCompany, handle: post.authorHandle, photoUrl: post.authorPhotoUrl))),
                  ),
                if (!_isOwner && post.isRequirement) _visitorSection(post, p),
                if (_isOwner && post.isRequirement) _ownerSection(post, p),
                if (!_isOwner && _referrals.isNotEmpty) _myReferrals(p),
              ]),
            ),
    );
  }

  // ---------- visitor ----------
  Widget _visitorSection(Post post, Pal p) {
    final mine = _mine;
    const word = {'contact': 'your contact', 'media': 'a photo', 'info': 'some information'};
    if (mine == null) return const SizedBox.shrink();
    if (!mine.shared) {
      return SizedBox(width: double.infinity, child: GoldButton(label: 'Respond · share contact, photo or info', onPressed: _respond));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(Icons.check_circle, color: kGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'You shared ${word[mine.kind ?? 'contact']}${mine.rating == 1 ? ' · 👍 from owner' : mine.rating == -1 ? ' · 👎 from owner' : ''}${mine.ownerReaction == null ? '' : ' · ${kReactionEmoji[mine.ownerReaction]}'}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ]),
      ),
      if (mine.askStatus == 'asked') ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${post.authorName} asked you to share it with them.', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('Approve to reveal ${word[mine.kind ?? 'contact']} to the owner.', style: TextStyle(color: p.muted, fontSize: 13)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: GoldButton(label: 'Approve', loading: _busy, onPressed: () => _answer(true))),
              const SizedBox(width: 10),
              Expanded(child: GoldButton(label: 'Decline', outlined: true, onPressed: _busy ? null : () => _answer(false))),
            ]),
          ]),
        ),
      ],
      if (mine.askStatus == 'approved') Padding(padding: const EdgeInsets.only(top: 8), child: Text('The owner can see what you shared.', style: TextStyle(color: p.muted))),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: GoldButton(label: 'Message ${post.authorName.split(' ').first}', outlined: true, icon: Icons.chat_bubble_outline, onPressed: () => openChat(context, Peer(uid: post.authorUid, name: post.authorName, company: post.authorCompany, handle: post.authorHandle, photoUrl: post.authorPhotoUrl))),
      ),
    ]);
  }

  Widget _myReferrals(Pal p) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Contacts you referred', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 4),
          for (final r in _referrals)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Avatar(name: r.name, size: 40),
              title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(r.phone, style: const TextStyle(color: kGold, fontWeight: FontWeight.w600)),
              trailing: IconButton(tooltip: 'Remove', icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => _deleteReferral(r)),
            ),
        ]),
      );

  // ---------- owner ----------
  Widget _ownerSection(Post post, Pal p) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Responses', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
      const SizedBox(height: 6),
      if (_shares.isEmpty)
        Padding(padding: const EdgeInsets.symmetric(vertical: 18), child: Text('No responses yet. People who respond will appear here.', style: TextStyle(color: p.muted, fontWeight: FontWeight.w500)))
      else
        for (final s in _shares) _ShareTile(postId: post.id, share: s, onChanged: _load),
      if (_referrals.isNotEmpty) ...[
        const SizedBox(height: 18),
        const Text('Referred contacts', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        for (final r in _referrals)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: '${r.name} · ', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: r.phone, style: const TextStyle(color: kGold, fontWeight: FontWeight.w700)),
              ])),
              if ((r.note ?? '').isNotEmpty) Text(r.note!),
              Row(children: [
                Expanded(child: Text('Referred by ${r.referrerName ?? ''} · ${timeAgo(r.createdAt)}', style: TextStyle(color: p.muted, fontSize: 12.5))),
                IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.call, color: kGreen, size: 20), onPressed: () => launchUrl(Uri(scheme: 'tel', path: r.phone.replaceAll(' ', '')))),
              ]),
            ]),
          ),
      ],
    ]);
  }
}

/// Owner's row for one responder: who + what type; content only after they approve.
class _ShareTile extends StatefulWidget {
  final String postId;
  final ContactShare share;
  final VoidCallback onChanged;
  const _ShareTile({required this.postId, required this.share, required this.onChanged});
  @override
  State<_ShareTile> createState() => _ShareTileState();
}

class _ShareTileState extends State<_ShareTile> {
  bool _busy = false;
  ContactShare get s => widget.share;

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

  Api get _api => context.read<AuthProvider>().api;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    const label = {'contact': 'Contact', 'media': 'Photo', 'info': 'Info'};
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border.withValues(alpha: .6)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          GestureDetector(
            onTap: s.sharerHandle == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: s.sharerHandle!))),
            child: Avatar(name: s.sharerName, photoUrl: s.sharerPhotoUrl, size: 44),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.sharerName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
            Text(s.sharerCompany, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 13)),
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(8)), child: Text('${label[s.kind] ?? s.kind} shared', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 8),
        if (s.revealed)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(12)),
            child: s.kind == 'media' && s.payload != null
                ? ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(mediaUrl(s.payload!), fit: BoxFit.contain, height: 220))
                : s.kind == 'contact'
                    ? InkWell(
                        onTap: () => launchUrl(Uri(scheme: 'tel', path: (s.payload ?? '').replaceAll(' ', ''))),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.call, size: 18, color: kGreen), const SizedBox(width: 8), Text(s.payload ?? '', style: const TextStyle(fontWeight: FontWeight.w700))]),
                      )
                    : Text(s.payload ?? ''),
          )
        else
          Row(children: [
            Expanded(
              child: Text(
                s.askStatus == 'asked' ? 'Waiting for them to approve.' : s.askStatus == 'declined' ? 'They declined. You can ask again.' : 'Content is private until they approve.',
                style: TextStyle(color: p.muted, fontSize: 12.5),
              ),
            ),
            SizedBox(
              width: 120,
              child: GoldButton(label: s.askStatus == 'asked' ? 'Asked ✓' : 'Ask to share', outlined: true, loading: _busy, onPressed: s.askStatus == 'asked' ? null : () => _run(() async => _api.post('/posts/${widget.postId}/shares/${s.sharerUid}/ask'))),
            ),
          ]),
        const SizedBox(height: 4),
        Row(children: [
          _thumb(Icons.thumb_up_outlined, s.rating == 1, Colors.green, () => _run(() async => _api.post('/posts/${widget.postId}/shares/${s.sharerUid}/rate', {'rating': s.rating == 1 ? null : 1}))),
          _thumb(Icons.thumb_down_outlined, s.rating == -1, Colors.redAccent, () => _run(() async => _api.post('/posts/${widget.postId}/shares/${s.sharerUid}/rate', {'rating': s.rating == -1 ? null : -1}))),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () async {
              final v = await showModalBottomSheet<String>(
                context: context,
                builder: (ctx) => SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, mainAxisSize: MainAxisSize.min, children: [
                      for (final r in kReactions) GestureDetector(onTap: () => Navigator.pop(ctx, r), child: Text(kReactionEmoji[r]!, style: const TextStyle(fontSize: 34))),
                    ]),
                  ),
                ),
              );
              if (v != null) _run(() async => _api.post('/posts/${widget.postId}/shares/${s.sharerUid}/rate', {'reaction': v == s.ownerReaction ? null : v}));
            },
            child: Padding(padding: const EdgeInsets.all(8), child: Text(s.ownerReaction == null ? '☺' : kReactionEmoji[s.ownerReaction]!, style: const TextStyle(fontSize: 20))),
          ),
          const Spacer(),
          SizedBox(width: 110, child: GoldButton(label: 'Message', outlined: true, onPressed: () => openChat(context, Peer(uid: s.sharerUid, name: s.sharerName, company: s.sharerCompany, handle: s.sharerHandle ?? '', photoUrl: s.sharerPhotoUrl)))),
        ]),
      ]),
    );
  }

  Widget _thumb(IconData icon, bool on, Color color, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _busy ? null : onTap,
        child: Container(margin: const EdgeInsets.only(right: 4), padding: const EdgeInsets.all(8), decoration: BoxDecoration(shape: BoxShape.circle, color: on ? color.withValues(alpha: .18) : null), child: Icon(icon, size: 20, color: on ? color : Pal.of(context).muted)),
      );
}

/// Bottom sheet: how to respond to an ask (contact, photo or information).
class _RespondSheet extends StatefulWidget {
  final String postId;
  const _RespondSheet({required this.postId});
  @override
  State<_RespondSheet> createState() => _RespondSheetState();
}

class _RespondSheetState extends State<_RespondSheet> {
  String _kind = 'contact';
  final _text = TextEditingController();
  XFile? _file;
  bool _busy = false;
  String? _error;

  bool get _ready => _kind == 'contact' || (_kind == 'media' && _file != null) || (_kind == 'info' && _text.text.trim().length >= 2);

  Future<void> _submit() async {
    final api = context.read<AuthProvider>().api;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = <String, dynamic>{'kind': _kind};
      if (_kind == 'media') body['imageUrl'] = await api.uploadImage(await _file!.readAsBytes(), _file!.name);
      if (_kind == 'info') body['text'] = _text.text.trim();
      await api.post('/posts/${widget.postId}/share', body);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    const options = [
      ('contact', Icons.call_outlined, 'Share my contact', 'The owner sees you shared. Your number is revealed only if you approve.'),
      ('media', Icons.photo_camera_outlined, 'Share a photo', 'Product photo, brochure or proof. Shown only after you approve.'),
      ('info', Icons.chat_bubble_outline, 'Share information', 'A short note, price or offer. Shown only after you approve.'),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Respond to this requirement', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          for (final o in options)
            GestureDetector(
              onTap: () => setState(() => _kind = o.$1),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: _kind == o.$1 ? p.text : p.border), color: _kind == o.$1 ? p.chip : null),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(width: 38, height: 38, decoration: BoxDecoration(color: p.canvas, shape: BoxShape.circle), child: Icon(o.$2)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(o.$3, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(o.$4, style: TextStyle(color: p.muted, fontSize: 13)),
                  ])),
                ]),
              ),
            ),
          if (_kind == 'media') ...[
            const SizedBox(height: 4),
            GoldButton(
              label: _file == null ? 'Choose a photo' : 'Photo selected: ${_file!.name}',
              outlined: true,
              icon: Icons.photo_library_outlined,
              onPressed: () async {
                final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1280, imageQuality: 75);
                if (f != null) setState(() => _file = f);
              },
            ),
          ],
          if (_kind == 'info') ...[
            const SizedBox(height: 4),
            AppField(controller: _text, hint: 'e.g. We can supply 2000 boxes/month at ₹18 each, delivery in 2 days.', maxLines: 3, maxLength: 500, onChanged: (_) => setState(() {})),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: GoldButton(label: 'Send', loading: _busy, onPressed: _ready ? _submit : null)),
        ]),
      ),
    );
  }
}

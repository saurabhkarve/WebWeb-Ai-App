import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../auth_provider.dart';
import '../i18n.dart';
import '../models.dart';
import '../screens/contact_picker.dart';
import '../theme.dart';
import '../widgets.dart';
import 'mention_suggest.dart';

/// What Refer sent: how many contacts were referred on an ask, and whether anything went (a note, photos, contacts).
typedef ReferResult = ({int referred, bool noted});

/// Refer, in one step: a composer that opens ready to type, with Contact and Photos in its toolbar.
/// On an ask:
/// - contacts are referred on the ask (POST /posts/:id/refer) with the note, up to 5 per ask;
/// - photos, or a note with no contact, go to the asker in a chat with the ask attached (a chat has no
///   one-reply-per-member limit and takes several photos).
/// On an update: the note (with the update attached), the photos and the contacts go to the poster in a chat.
/// Resolves null when nothing was sent.
Future<ReferResult?> showReferSheet(BuildContext context, Post post) => _show(context, _ReferSheet(post: post));

/// Refer on a card that is not a post (a house account's news or tender): the note, "About" the card, the photos
/// and the contacts go to that account in a chat, where its Reply goes too.
Future<ReferResult?> showReferToChat(BuildContext context, {required String uid, required String name, required String about}) =>
    _show(context, _ReferSheet(chatUid: uid, chatName: name, about: about));

Future<ReferResult?> _show(BuildContext context, Widget sheet) => showModalBottomSheet<ReferResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Pal.of(context).canvas,
      barrierColor: kInk.withValues(alpha: .6),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => sheet,
    );

/// A photo, uploading from the moment it is picked
class _Pic {
  final XFile file;
  late final Future<Uint8List> bytes = file.readAsBytes();
  late final Future<String> url;
  bool failed = false;
  _Pic(this.file, Api api) {
    url = bytes.then((b) => api.uploadImage(b, file.name));
  }
}

class _ReferSheet extends StatefulWidget {
  final Post? post;
  /// not a post: who gets it in a chat, and what it is about
  final String? chatUid, chatName, about;
  const _ReferSheet({this.post, this.chatUid, this.chatName, this.about});
  @override
  State<_ReferSheet> createState() => _ReferSheetState();
}

class _ReferSheetState extends State<_ReferSheet> {
  static const _maxPhotos = 4;
  final _text = TextEditingController();
  final _focus = FocusNode();
  final List<PickedContact> _picked = [];
  final List<_Pic> _pics = [];
  /// contacts this member can still refer on the ask (5 each); updates and house cards: 5 at a time
  int _left = 5;
  bool _busy = false;
  String? _error;

  bool get _ask => widget.post?.isRequirement ?? false;
  String get _toName => widget.post?.shownName ?? widget.chatName ?? '';
  String get _about => widget.post?.title ?? widget.about ?? '';
  Api get _api => context.read<AuthProvider>().api;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    if (!_ask) return;
    _api.get('/app/posts/${widget.post!.id}/referrals/mine').then((r) {
      if (mounted) setState(() => _left = 5 - (r as List).length);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _ready => _picked.isNotEmpty || _pics.isNotEmpty || _text.text.trim().length >= 2;

  Future<void> _attachContact() async {
    final room = _left - _picked.length;
    if (room <= 0) return toast(context, t('You can refer up to 5 contacts on one ask'));
    final got = await Navigator.push<List<PickedContact>>(context, MaterialPageRoute(builder: (_) => ContactPicker(askerName: _toName, maxSelect: room)));
    if (got == null || !mounted) return;
    setState(() {
      for (final c in got) {
        if (!_picked.any((x) => x.phone == c.phone)) _picked.add(c);
      }
    });
  }

  Future<void> _addPhotos() async {
    final room = _maxPhotos - _pics.length;
    if (room <= 0) return;
    final picker = ImagePicker();
    // pickMultiImage takes a limit of 2 or more; one place left is a single pick
    final List<XFile> files;
    if (room > 1) {
      files = await picker.pickMultiImage(maxWidth: 1600, imageQuality: 80, limit: room);
    } else {
      final f = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 80);
      files = [if (f != null) f];
    }
    if (files.isEmpty || !mounted) return;
    final api = _api;
    setState(() {
      for (final f in files.take(room)) {
        final pic = _Pic(f, api);
        pic.url.then((_) {
          if (mounted) setState(() {});
        }, onError: (_) {
          if (mounted) setState(() => pic.failed = true);
        });
        _pics.add(pic);
      }
    });
  }

  Future<void> _send() async {
    final note = _text.text.trim();
    setState(() => (_busy = true, _error = null));
    try {
      final photos = <String>[];
      for (final pic in _pics) {
        try {
          photos.add(await pic.url);
        } catch (_) {
          throw t('A photo could not be uploaded. Remove it and try again.');
        }
      }
      var referred = 0;
      if (_ask && _picked.isNotEmpty) {
        String? err;
        for (final c in _picked) {
          try {
            await _api.post('/posts/${widget.post!.id}/refer', {'name': c.name, 'phone': c.phone, if (note.isNotEmpty) 'note': note.length > 200 ? note.substring(0, 200) : note});
            referred++;
          } catch (e) {
            err = '$e';
          }
        }
        if (referred == 0) throw err ?? t('Could not refer');
      }
      // the chat: everything on an update or house card; on an ask, the photos, or a note with no contact
      if (!_ask || photos.isNotEmpty || _picked.isEmpty) {
        await _toChat(note: _ask && _picked.isNotEmpty ? '' : note, photos: photos, contacts: _ask ? const [] : _picked);
      }
      if (mounted) Navigator.pop(context, (referred: referred, noted: true));
    } catch (e) {
      if (mounted) setState(() => (_busy = false, _error = '$e'));
    }
  }

  /// To the asker or poster (or the house account) in a chat: the note with the post attached, then each photo and
  /// each contact as a message of its own.
  Future<void> _toChat({required String note, required List<String> photos, required List<PickedContact> contacts}) async {
    final post = widget.post;
    final chat = (await _api.post('/chats', {'userId': post?.authorUid ?? widget.chatUid}) as Map)['id'];
    Future<void> say(Map<String, dynamic> m) => _api.post('/chats/$chat/messages', m);
    if (post == null) {
      final about = _about.length > 120 ? '${_about.substring(0, 120)}…' : _about;
      await say({'text': '${t('About')} "$about"${note.isEmpty ? '' : ': $note'}'});
    } else {
      final title = post.title ?? post.description ?? 'Update';
      await say({
        'text': note,
        'attachment': {
          'type': 'post',
          'postId': post.id,
          'kind': post.isRequirement ? 'ask' : 'update',
          'title': title.length > 100 ? title.substring(0, 100) : title,
          if (post.images.isNotEmpty) 'imageUrl': post.images.first,
          'by': post.authorCompany.isNotEmpty ? post.authorCompany : post.authorName,
          'path': Uri.parse(post.webUrl).path,
        },
      });
    }
    for (final u in photos) {
      await say({'imageUrl': u});
    }
    for (final c in contacts) {
      await say({'attachment': {'type': 'contact', 'name': c.name, 'phone': c.phone}});
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final mq = MediaQuery.of(context);
    final kb = mq.viewInsets.bottom;
    final on = _focus.hasFocus;
    final canContact = _picked.length < _left;
    final canPhoto = _pics.length < _maxPhotos;

    Widget tool(IconData icon, String label, VoidCallback? onTap) => TextButton.icon(
          onPressed: _busy ? null : onTap,
          style: TextButton.styleFrom(foregroundColor: p.tagText, visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10), shape: const StadiumBorder()),
          icon: Icon(icon, size: 20),
          label: Text(t(label), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        );

    final contacts = [
      for (final c in _picked)
        Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 2, 4),
          decoration: BoxDecoration(color: kGold.withValues(alpha: .14), borderRadius: BorderRadius.circular(99), border: Border.all(color: kGold.withValues(alpha: .55))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Avatar(name: c.name, size: 28),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.2)),
                Text(c.phone, maxLines: 1, style: TextStyle(fontSize: 11.5, color: p.muted, height: 1.2)),
              ]),
            ),
            IconButton(visualDensity: VisualDensity.compact, tooltip: t('Remove'), onPressed: _busy ? null : () => setState(() => _picked.remove(c)), icon: WIcon(WI.close, size: 14, color: p.muted)),
          ]),
        ),
    ];

    final photos = [
      for (final pic in _pics)
        SizedBox(
          width: 72,
          height: 72,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(fit: StackFit.expand, children: [
              FutureBuilder<Uint8List>(
                future: pic.bytes,
                builder: (_, s) => s.hasData ? Image.memory(s.data!, fit: BoxFit.cover, gaplessPlayback: true) : ColoredBox(color: p.chip),
              ),
              // uploading: a gold bar along the foot until the photo is up
              FutureBuilder<String>(
                future: pic.url,
                builder: (_, s) => s.connectionState == ConnectionState.done
                    ? const SizedBox.shrink()
                    : const Align(alignment: Alignment.bottomCenter, child: LinearProgressIndicator(minHeight: 3, color: kGold, backgroundColor: Colors.transparent)),
              ),
              if (pic.failed) Container(color: p.danger.withValues(alpha: .55), alignment: Alignment.center, child: const Icon(Icons.error_outline_rounded, color: Colors.white)),
              Positioned(
                right: 4,
                top: 4,
                child: Semantics(
                  button: true,
                  label: t('Remove photo'),
                  child: GestureDetector(
                    onTap: _busy ? null : () => setState(() => _pics.remove(pic)),
                    child: Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(color: kInk.withValues(alpha: .7), shape: BoxShape.circle), child: const WIcon(WI.close, size: 12, color: Colors.white)),
                  ),
                ),
              ),
            ]),
          ),
        ),
    ];

    // the composer: the note, what is attached, and the toolbar, in one box that lights up while you write
    final composer = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: p.field,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: on ? kGold : p.border, width: on ? 1.5 : 1),
        boxShadow: on ? [BoxShadow(color: kGold.withValues(alpha: .18), spreadRadius: 3)] : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
          child: TextField(
            controller: _text,
            focusNode: _focus,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            maxLength: 300,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 16, height: 1.4),
            decoration: InputDecoration(
              hintText: t('Who can help, and why they fit. Attach their contact below.'),
              hintStyle: TextStyle(color: p.muted),
              counterText: '',
              filled: false,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: MentionSuggest(controller: _text, focus: _focus)),
        if (contacts.isNotEmpty || photos.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [...contacts, ...photos]),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(4, 2, 12, 2),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border.withValues(alpha: .7)))),
          child: Row(children: [
            tool(Icons.contact_phone_outlined, 'Contact', canContact ? _attachContact : () => toast(context, t('You can refer up to 5 contacts on one ask'))),
            tool(Icons.add_photo_alternate_outlined, 'Photos', canPhoto ? _addPhotos : null),
            const Spacer(),
            if (_text.text.length > 200)
              Text('${_text.text.length}/300', style: TextStyle(fontSize: 11.5, color: _text.text.length > 280 ? p.danger : p.muted, fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        ),
      ]),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 10), decoration: BoxDecoration(color: p.border, borderRadius: BorderRadius.circular(2)))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: const BoxDecoration(gradient: kGoldGradient, shape: BoxShape.circle),
              child: const WIcon(WI.refer, size: 20, color: kInk, strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('Refer'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.2)),
                if (_about.isNotEmpty) Text(_about, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.muted, height: 1.3)),
              ]),
            ),
            IconButton(tooltip: t('Close'), onPressed: () => Navigator.pop(context), icon: WIcon(WI.close, size: 22, color: p.text)),
          ]),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              composer,
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(top: 1), child: WIcon(WI.lock, size: 14, color: p.muted)),
                const SizedBox(width: 6),
                Expanded(child: Text(t('Only {name} sees what you send here.', {'name': _toName}), style: TextStyle(fontSize: 12.5, color: p.muted, height: 1.35))),
              ]),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(fontSize: 14, color: p.danger))),
            ]),
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(16, 10, 16, kb > 0 ? 10 : mq.padding.bottom + 14),
          decoration: BoxDecoration(color: p.canvas, border: Border(top: BorderSide(color: p.border.withValues(alpha: .7)))),
          child: GoldButton(label: t('Send'), wi: WI.send, height: 48, loading: _busy, onPressed: _ready && !_busy ? _send : null),
        ),
      ]),
    );
  }
}

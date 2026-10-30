import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../i18n.dart';
import '../models.dart';
import '../screens/contact_picker.dart';
import '../theme.dart';
import '../widgets.dart';
import 'mention_suggest.dart';

/// What Refer sent: how many contacts were referred, and whether a note went on its own (no contact).
typedef ReferResult = ({int referred, bool noted});

/// Refer on an ask, in one step: the note box opens ready to type, with "Attach a contact" right under it.
/// - With contacts: each one is referred (POST /posts/:id/refer) with the note, up to 5 per ask.
/// - Without: the note is a reply on the ask (POST /posts/:id/share), as "Just a note".
/// Resolves null when nothing was sent.
Future<ReferResult?> showReferSheet(BuildContext context, Post post) => showModalBottomSheet<ReferResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.of(context).canvas,
      barrierColor: kInk.withValues(alpha: .6),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _ReferSheet(post: post),
    );

class _ReferSheet extends StatefulWidget {
  final Post post;
  const _ReferSheet({required this.post});
  @override
  State<_ReferSheet> createState() => _ReferSheetState();
}

class _ReferSheetState extends State<_ReferSheet> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final List<PickedContact> _picked = [];
  /// contacts this member can still refer on the ask (5 each)
  int _left = 5;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    context.read<AuthProvider>().api.get('/app/posts/${widget.post.id}/referrals/mine').then((r) {
      if (mounted) setState(() => _left = 5 - (r as List).length);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _ready => _picked.isNotEmpty || _text.text.trim().length >= 2;

  Future<void> _attach() async {
    final room = _left - _picked.length;
    if (room <= 0) return toast(context, t('You can refer up to 5 contacts on one ask'));
    final got = await Navigator.push<List<PickedContact>>(context, MaterialPageRoute(builder: (_) => ContactPicker(askerName: widget.post.shownName, maxSelect: room)));
    if (got == null || !mounted) return;
    setState(() {
      for (final c in got) {
        if (!_picked.any((x) => x.phone == c.phone)) _picked.add(c);
      }
    });
  }

  Future<void> _send() async {
    final api = context.read<AuthProvider>().api;
    final note = _text.text.trim();
    setState(() => (_busy = true, _error = null));
    try {
      if (_picked.isEmpty) {
        await api.post('/posts/${widget.post.id}/share', {'kind': 'info', 'text': note});
        if (mounted) Navigator.pop(context, (referred: 0, noted: true));
        return;
      }
      var ok = 0;
      String? err;
      for (final c in _picked) {
        try {
          await api.post('/posts/${widget.post.id}/refer', {'name': c.name, 'phone': c.phone, if (note.isNotEmpty) 'note': note.length > 200 ? note.substring(0, 200) : note});
          ok++;
        } catch (e) {
          err = '$e';
        }
      }
      if (!mounted) return;
      if (ok == 0) return setState(() => (_busy = false, _error = err ?? t('Could not refer')));
      Navigator.pop(context, (referred: ok, noted: false));
    } catch (e) {
      if (mounted) setState(() => (_busy = false, _error = '$e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final bottom = MediaQuery.of(context).padding.bottom;
    final kb = MediaQuery.of(context).viewInsets.bottom;
    OutlineInputBorder edge(Color c) => OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c));
    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('Refer'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                if ((widget.post.title ?? '').isNotEmpty) Text(widget.post.title!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.muted)),
              ]),
            ),
            GestureDetector(onTap: () => Navigator.pop(context), child: WIcon(WI.close, size: 24, color: p.text)),
          ]),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: _text,
                focusNode: _focus,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                maxLength: 300,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: t('Who can help, and why they fit. Attach their contact below.'),
                  hintStyle: TextStyle(color: p.muted),
                  counterText: _text.text.length > 150 ? '${_text.text.length}/300' : '',
                  filled: true,
                  fillColor: p.field,
                  contentPadding: const EdgeInsets.all(12),
                  border: edge(p.border),
                  enabledBorder: edge(p.border),
                  focusedBorder: edge(p.text),
                ),
              ),
              MentionSuggest(controller: _text, focus: _focus),
              const SizedBox(height: 10),
              // the contacts attached so far, then the button to attach (more)
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final c in _picked)
                  Container(
                    padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
                    decoration: BoxDecoration(color: kGold.withValues(alpha: .14), borderRadius: BorderRadius.circular(99), border: Border.all(color: kGold.withValues(alpha: .6))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Avatar(name: c.name, size: 24),
                      const SizedBox(width: 6),
                      ConstrainedBox(constraints: const BoxConstraints(maxWidth: 150), child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: t('Remove'),
                        onPressed: () => setState(() => _picked.remove(c)),
                        icon: WIcon(WI.close, size: 14, color: p.muted),
                      ),
                    ]),
                  ),
                if (_picked.length < _left)
                  InkWell(
                    borderRadius: BorderRadius.circular(99),
                    onTap: _busy ? null : _attach,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), border: Border.all(color: kGold, width: 1.4)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        WIcon(WI.contactCard, size: 17, color: p.tagText),
                        const SizedBox(width: 8),
                        Text(t('Attach a contact'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.tagText)),
                      ]),
                    ),
                  ),
              ]),
              const SizedBox(height: 10),
              Text(t('{name} gets the contact and your note.', {'name': widget.post.shownName}), style: TextStyle(fontSize: 12, color: p.muted)),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(fontSize: 14, color: p.danger))),
            ]),
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(16, 10, 16, kb > 0 ? 10 : bottom + 14),
          decoration: BoxDecoration(color: p.canvas, border: Border(top: BorderSide(color: p.border.withValues(alpha: .7)))),
          child: GoldButton(label: t('Send'), wi: WI.send, loading: _busy, onPressed: _ready && !_busy ? _send : null),
        ),
      ]),
    );
  }
}

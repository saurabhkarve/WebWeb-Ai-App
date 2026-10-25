import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets.dart';
import 'p1.dart';

/// Existing response being edited (web: ResponseSheet `existing`).
class ExistingResponse {
  final String kind;
  final String? text, imageUrl;
  /// an offer ("I can do this"), with its price and when
  final bool canDo;
  final String? quote, readyWhen;
  const ExistingResponse(this.kind, {this.text, this.imageUrl, this.canDo = false, this.quote, this.readyWhen});
}

/// Bottom sheet: reply to an ask in one step, like the web's response-sheet.tsx. It opens on "I can do this", an offer
/// that needs no words (a price and when are optional chips the asker can compare), or "Just a note": a note with an
/// optional photo (or a photo on its own). Passing on someone's number is Refer's job, so there is no "share my contact" here.
/// Resolves true when a reply was sent.
Future<bool> showResponseSheet(BuildContext context, String postId, {ExistingResponse? existing}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Pal.of(context).canvas,
    barrierColor: kInk.withValues(alpha: .6),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => _ResponseSheet(postId: postId, existing: existing),
  );
  return r == true;
}

class _ResponseSheet extends StatefulWidget {
  final String postId;
  final ExistingResponse? existing;
  const _ResponseSheet({required this.postId, this.existing});
  @override
  State<_ResponseSheet> createState() => _ResponseSheetState();
}

class _ResponseSheetState extends State<_ResponseSheet> {
  late final _text = TextEditingController(text: widget.existing?.text ?? '');
  // a new reply starts as an offer; an edited one keeps what it was
  late bool _canDo = widget.existing == null || widget.existing!.canDo;
  late final _quote = TextEditingController(text: widget.existing?.quote ?? '');
  // a new offer starts at Today (the most common answer, and the strongest); an edit keeps what was said
  late String? _when = widget.existing == null ? 'today' : widget.existing!.readyWhen;
  XFile? _file;
  late String? _kept = widget.existing?.imageUrl;
  bool _busy = false;
  String? _error;
  // my catalog items for this ask: the best fit is picked for me, one tap to change or drop it
  List<Map> _items = const [];
  String? _itemId;

  @override
  void initState() {
    super.initState();
    if (widget.existing == null) _loadItems();
  }

  Future<void> _loadItems() async {
    try {
      final r = await context.read<AuthProvider>().api.get('/posts/${widget.postId}/my-items') as Map;
      final list = [for (final x in (r['items'] as List? ?? const [])) x as Map];
      if (!mounted) return;
      setState(() => _items = list);
      final best = list.where((x) => x['suggested'] == true).firstOrNull;
      if (best != null) _pick(best);
    } catch (_) {}
  }

  void _pick(Map? it) {
    setState(() {
      _itemId = it == null ? null : '${it['id']}';
      if (it != null) _quote.text = '${it['price'] ?? ''}';
    });
  }

  bool get _editing => widget.existing != null;
  bool get _hasPhoto => _file != null || _kept != null;
  bool get _ready {
    final n = _text.text.trim().length;
    if (_canDo) return n != 1;
    return n >= 2 || (n == 0 && _hasPhoto);
  }

  Future<void> _submit() async {
    final api = context.read<AuthProvider>().api;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final note = _text.text.trim();
      final body = <String, dynamic>{'kind': 'info'};
      if (note.isNotEmpty) body['text'] = note;
      if (_canDo) {
        body['canDo'] = true;
        if (_quote.text.trim().isNotEmpty) body['quote'] = _quote.text.trim();
        if (_when != null) body['readyWhen'] = _when;
        if (_itemId != null) body['itemId'] = _itemId;
      }
      final imageUrl = _file != null ? await api.uploadImage(await _file!.readAsBytes(), _file!.name) : _kept;
      if (imageUrl != null) body['imageUrl'] = imageUrl;
      _editing ? await api.put('/posts/${widget.postId}/share', body) : await api.post('/posts/${widget.postId}/share', body);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _quote.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .9),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(t(_editing ? 'Edit your reply' : 'Reply to this ask'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            GestureDetector(onTap: () => Navigator.pop(context), child: WIcon(WI.close, size: 24, color: p.text)),
          ]),
          const SizedBox(height: 12),
          // what kind of reply: an offer to do it, or just a note
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(99)),
            child: Row(children: [
              for (final v in [true, false])
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _canDo = v),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: _canDo == v && v ? kGoldGradient : null,
                        color: _canDo == v && !v ? p.canvas : null,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(v ? '✓ ${t('I can do this')}' : t('Just a note'),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _canDo == v ? (v ? kInk : p.text) : p.muted)),
                    ),
                  ),
                ),
            ]),
          ),
          if (_canDo && _items.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(t('From your catalog'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.muted)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final it in _items)
                GestureDetector(
                  onTap: () => _pick(_itemId == '${it['id']}' ? null : it),
                  child: Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 64),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _itemId == '${it['id']}' ? kGold.withValues(alpha: .25) : null,
                      border: Border.all(color: _itemId == '${it['id']}' ? kGold : p.border),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text('${it['suggested'] == true ? '✨ ' : ''}${it['name']}',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _itemId == '${it['id']}' ? p.text : p.muted)),
                  ),
                ),
            ]),
            if (_itemId != null && _items.any((x) => '${x['id']}' == _itemId && x['suggested'] == true))
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(t('Picked for this ask. Tap it to remove.'), style: TextStyle(fontSize: 12, color: p.muted))),
          ],
          if (_canDo) ...[
            const SizedBox(height: 12),
            Text(t('Price (optional)'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.muted)),
            const SizedBox(height: 4),
            TextField(
              controller: _quote,
              maxLength: 40,
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                hintText: t('e.g. ₹18 per box'),
                hintStyle: TextStyle(color: p.muted),
                counterText: '',
                isDense: true,
                filled: true,
                fillColor: p.field,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.text)),
              ),
            ),
            const SizedBox(height: 12),
            Text(t('When can you do it?'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.muted)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in kReadyLabel.entries)
                GestureDetector(
                  onTap: () => setState(() => _when = _when == e.key ? null : e.key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _when == e.key ? kGold.withValues(alpha: .25) : null,
                      border: Border.all(color: _when == e.key ? kGold : p.border),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(t(e.value), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _when == e.key ? p.text : p.muted)),
                  ),
                ),
            ]),
            const SizedBox(height: 12),
          ] else
            const SizedBox(height: 12),
          TextField(
            controller: _text,
            autofocus: !_canDo,
            minLines: _canDo ? 2 : 4,
            maxLines: 6,
            maxLength: 300,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              hintText: t(_canDo ? 'Add a note (optional)' : 'e.g. We can supply 2000 boxes/month at ₹18 each, delivery in 2 days.'),
              hintStyle: TextStyle(color: p.muted),
              // the count shows near the 300 limit
              counterText: _text.text.length > 240 ? '${_text.text.length}/300' : '',
              filled: true,
              fillColor: p.field,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.text)),
            ),
          ),
          const SizedBox(height: 8),
          // the photo rides along with the note: product, brochure or proof
          Align(
            alignment: Alignment.centerLeft,
            child: _hasPhoto
                ? Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        height: 160,
                        child: _file != null
                            ? FutureBuilder(
                                future: _file!.readAsBytes(),
                                builder: (_, s) => s.hasData ? Image.memory(s.data!, fit: BoxFit.contain) : const SizedBox(width: 160),
                              )
                            : NetImg(_kept!, fit: BoxFit.contain),
                      ),
                    ),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Semantics(
                        button: true,
                        label: t('Remove photo'),
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _file = null;
                            _kept = null;
                          }),
                          child: Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: kInk.withValues(alpha: .7), shape: BoxShape.circle),
                            child: const WIcon(WI.close, size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ])
                : InkWell(
                    borderRadius: BorderRadius.circular(99),
                    onTap: () async {
                      final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1280, imageQuality: 75);
                      if (f != null) setState(() => _file = f);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), border: Border.all(color: p.border)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        WIcon(WI.camera, size: 16, color: p.muted),
                        const SizedBox(width: 8),
                        Text(t('Add a photo'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.muted)),
                      ]),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Text(t("Your reply shows on the ask. To pass on someone's number, use Refer."), style: TextStyle(fontSize: 12, color: p.muted)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(fontSize: 14, color: p.danger))),
          if (_editing)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                t("Editing clears the owner's earlier thumbs-up or reaction, and they will need to ask again to see the new content."),
                style: TextStyle(fontSize: 12, color: p.muted),
              ),
            ),
          const SizedBox(height: 16),
          GoldButton(label: t(_editing ? 'Save changes' : 'Send'), loading: _busy, onPressed: _ready ? _submit : null),
        ]),
      ),
    );
  }
}

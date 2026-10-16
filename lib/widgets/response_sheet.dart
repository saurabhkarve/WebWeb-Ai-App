import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets.dart';

/// Existing response being edited (web: ResponseSheet `existing`).
class ExistingResponse {
  final String kind;
  final String? text, imageUrl;
  const ExistingResponse(this.kind, {this.text, this.imageUrl});
}

/// Bottom sheet: pick how to respond to an ask (contact, photo or information), like the web's
/// response-sheet.tsx. Resolves true when a response was sent.
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
  late String _kind = widget.existing?.kind ?? 'contact';
  late final _text = TextEditingController(text: widget.existing?.text ?? '');
  XFile? _file;
  bool _busy = false;
  String? _error;

  static const _options = [
    ('contact', WI.phone, 'Share my contact', 'Only the ask owner sees your number. Everyone else just sees that you responded.'),
    ('media', WI.camera, 'Share a photo', 'Product photo, brochure or proof. Only the ask owner can see it.'),
    ('info', WI.talk, 'Share information', 'A short note, price or offer. Only the ask owner can see it.'),
  ];

  bool get _editing => widget.existing != null;
  bool get _ready =>
      _kind == 'contact' || (_kind == 'media' && (_file != null || widget.existing?.imageUrl != null)) || (_kind == 'info' && _text.text.trim().length >= 2);

  Future<void> _submit() async {
    final api = context.read<AuthProvider>().api;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = <String, dynamic>{'kind': _kind};
      if (_kind == 'media') body['imageUrl'] = _file != null ? await api.uploadImage(await _file!.readAsBytes(), _file!.name) : widget.existing!.imageUrl;
      if (_kind == 'info') body['text'] = _text.text.trim();
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
            Expanded(child: Text(t(_editing ? 'Edit your response' : 'Respond to this requirement'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            GestureDetector(onTap: () => Navigator.pop(context), child: WIcon(WI.close, size: 24, color: p.text)),
          ]),
          const SizedBox(height: 12),
          for (final o in _options) ...[
            GestureDetector(
              onTap: () => setState(() => _kind = o.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _kind == o.$1 ? p.text : p.border),
                  color: _kind == o.$1 ? p.chip : Colors.transparent,
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 36,
                    height: 36,
                    margin: const EdgeInsets.only(top: 2),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: p.canvas, shape: BoxShape.circle),
                    child: WIcon(o.$2, size: 20, color: p.text),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t(o.$3), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      Text(t(o.$4), style: TextStyle(color: p.muted, fontSize: 14)),
                    ]),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (_kind == 'media') ...[
            const SizedBox(height: 4),
            if (_file != null || widget.existing?.imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  height: 224,
                  color: kInk,
                  child: _file != null
                      ? FutureBuilder(
                          future: _file!.readAsBytes(),
                          builder: (_, s) => s.hasData ? Image.memory(s.data!, fit: BoxFit.contain) : const SizedBox(),
                        )
                      : NetImg(widget.existing!.imageUrl!, fit: BoxFit.contain),
                ),
              ),
            const SizedBox(height: 8),
            GoldButton(
              label: t(_file != null || widget.existing?.imageUrl != null ? 'Change photo' : 'Choose a photo'),
              outlined: true,
              height: 40,
              onPressed: () async {
                final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1280, imageQuality: 75);
                if (f != null) setState(() => _file = f);
              },
            ),
          ],
          if (_kind == 'info') ...[
            const SizedBox(height: 4),
            TextField(
              controller: _text,
              maxLines: 3,
              maxLength: 500,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                hintText: t('e.g. We can supply 2000 boxes/month at ₹18 each, delivery in 2 days.'),
                hintStyle: TextStyle(color: p.muted),
                counterText: '',
                filled: true,
                fillColor: p.field,
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.text)),
              ),
            ),
          ],
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

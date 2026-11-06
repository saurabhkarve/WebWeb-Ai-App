import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ask_types.dart';
import '../auth_provider.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'ask_deck.dart';
import 'card_look_picker.dart';

/// Card style, in a drawer: the layouts as thumbnails and the colours, with the ask as members will see it above them,
/// changing as you tap. Done returns (style, colour); closing returns null and leaves the earlier pair.
Future<(String, String)?> showCardStyleSheet(
  BuildContext context, {
  required String style,
  required String color,
  required String title,
  required String description,
  required String? type,
  required String budget,
  required String place,
  List<ImageProvider> images = const [],
}) {
  final p = Pal.of(context);
  return showModalBottomSheet<(String, String)>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.canvas,
    barrierColor: kInk.withValues(alpha: .6),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _Sheet(style: style, color: color, title: title, description: description, type: type, budget: budget, place: place, images: images),
  );
}

class _Sheet extends StatefulWidget {
  final String style, color, title, description, budget, place;
  final String? type;
  final List<ImageProvider> images;
  const _Sheet({required this.style, required this.color, required this.title, required this.description, required this.type, required this.budget, required this.place, required this.images});
  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  late String _style = widget.style, _color = widget.color;

  Post _post() {
    final me = context.read<AuthProvider>().profile;
    final type = widget.type;
    return Post(
      id: 'preview', kind: 'requirement', authorUid: me?.uid ?? '', authorName: me?.name ?? '', authorCompany: me?.company ?? '', authorHandle: me?.handle ?? '',
      title: widget.title.trim().isEmpty ? t('Your title shows here') : widget.title.trim(), description: widget.description,
      category: type == null ? 'other' : categoryForType(type, null), askType: type, cardColor: _color, cardStyle: _style,
      locationPref: widget.place.isEmpty ? null : widget.place, budget: widget.budget.isEmpty ? null : widget.budget, createdAt: DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final me = context.read<AuthProvider>().profile;
    final post = _post();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .92),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 4),
            child: Row(children: [
              Expanded(child: Text(t('Card style'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
              IconButton(onPressed: () => Navigator.pop(context), icon: WIcon(WI.close, size: 22, color: p.text)),
            ]),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(t('How members will see your ask'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted)),
                const SizedBox(height: 10),
                if (me != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Avatar(name: me.name, size: 36, type: me.userType, photoUrl: me.photoUrl, uid: me.uid),
                      const SizedBox(width: 10),
                      Expanded(child: Text(me.isEntrepreneur && me.company.isNotEmpty ? me.company : me.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                    ]),
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    WIcon(categoryIcon(askTypeDef(askTypeOf(post))?.icon ?? post.category), size: 14, color: p.link, still: true),
                    const SizedBox(width: 6),
                    Expanded(child: Text(askLabel(post).toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.2, color: p.link))),
                  ]),
                ),
                AskDeck(preview: true, typeAbove: true, post: post, images: widget.images),
                const SizedBox(height: 12),
                CardLookPicker(color: _color, style: _style, onColor: (c) => setState(() => _color = c), onStyle: (s) => setState(() => _style = s)),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: GoldButton(label: t('Done'), onPressed: () => Navigator.pop(context, (_style, _color))),
          ),
        ]),
      ),
    );
  }
}

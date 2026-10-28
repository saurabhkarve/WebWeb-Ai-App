import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// Member suggestions under a text box while an @mention is being typed (ask title and description): type "@" and a
/// few letters, tap a member and their @handle is put in.
class MentionSuggest extends StatefulWidget {
  const MentionSuggest({super.key, required this.controller, required this.focus});
  final TextEditingController controller;
  final FocusNode focus;

  @override
  State<MentionSuggest> createState() => _MentionSuggestState();
}

class _MentionSuggestState extends State<MentionSuggest> {
  // an @word right before the caret, not glued to a word (so an email address does not open it)
  static final _typing = RegExp(r'(^|[^\p{L}\p{N}\p{M}_&/@.])@([A-Za-z0-9]{0,30})$', unicode: true);
  List<Profile> _list = [];
  int _start = -1;
  String _q = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_check);
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_check);
    super.dispose();
  }

  void _check() {
    final c = widget.controller;
    final caret = c.selection.baseOffset;
    final m = caret < 0 || !widget.focus.hasFocus ? null : _typing.firstMatch(c.text.substring(0, caret.clamp(0, c.text.length)));
    if (m == null) {
      if (_start != -1 || _list.isNotEmpty) setState(() { _start = -1; _list = []; });
      return;
    }
    final q = m.group(2)!;
    final start = caret - q.length - 1;
    if (start == _start && q == _q) return;
    _start = start;
    _q = q;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 150), () async {
      try {
        final d = await context.read<AuthProvider>().api.get('/users/mention-search', {'q': q}) as List;
        if (!mounted || _q != q) return;
        setState(() => _list = d.map((e) => Profile.fromJson(e as Map)).toList());
      } catch (_) {}
    });
  }

  void _pick(Profile u) {
    final c = widget.controller;
    final caret = c.selection.baseOffset.clamp(0, c.text.length);
    final text = '${c.text.substring(0, _start)}@${u.handle} ${c.text.substring(caret)}';
    final at = _start + u.handle.length + 2;
    setState(() { _start = -1; _list = []; });
    c.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: at));
  }

  @override
  Widget build(BuildContext context) {
    if (_start < 0 || _list.isEmpty) return const SizedBox();
    final p = Pal.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(color: p.canvas, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (final u in _list)
          InkWell(
            onTap: () => _pick(u),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(children: [
                Avatar(name: u.name, photoUrl: u.photoUrl, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    Text('@${u.handle}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted)),
                  ]),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

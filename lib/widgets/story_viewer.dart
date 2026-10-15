import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../auth_provider.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// Full-screen story player (24-hour updates): tap right/left for next/previous, auto-advances.
class StoryViewer extends StatefulWidget {
  final List<StoryGroup> groups;
  final int startGroup;
  final String? meUid;
  final Future<void> Function(String storyId)? onDelete;
  const StoryViewer({super.key, required this.groups, this.startGroup = 0, this.meUid, this.onDelete});
  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer> {
  late int _g = widget.startGroup;
  int _i = 0;
  Timer? _timer;
  double _progress = 0;
  static const _frame = Duration(seconds: 5);

  StoryGroup get _group => widget.groups[_g];
  StoryItem get _item => _group.items[_i];

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _timer?.cancel();
    _progress = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      setState(() => _progress += 50 / _frame.inMilliseconds);
      if (_progress >= 1) _next();
    });
  }

  void _next() {
    if (_i < _group.items.length - 1) {
      setState(() => _i++);
      _start();
    } else if (_g < widget.groups.length - 1) {
      setState(() {
        _g++;
        _i = 0;
      });
      _start();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _prev() {
    if (_i > 0) {
      setState(() => _i--);
    } else if (_g > 0) {
      setState(() {
        _g--;
        _i = widget.groups[_g].items.length - 1;
      });
    }
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = _group, it = _item;
    final mine = widget.meUid != null && g.uid == widget.meUid;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (d) => d.localPosition.dx < MediaQuery.of(context).size.width / 3 ? _prev() : _next(),
        onLongPressStart: (_) => _timer?.cancel(),
        onLongPressEnd: (_) => _start(),
        child: Stack(children: [
          Positioned.fill(
            child: it.imageUrl != null
                ? Image.network(mediaUrl(it.imageUrl!), fit: BoxFit.contain)
                : Container(
                    decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF3A3A3A), Color(0xFF1E1E1E)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(32),
                    child: Text(it.text ?? '', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
                  ),
          ),
          if (it.imageUrl != null && (it.text ?? '').isNotEmpty)
            Positioned(left: 20, right: 20, bottom: 60, child: Text(it.text!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600, shadows: [Shadow(blurRadius: 8, color: Colors.black)]))),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Column(children: [
                Row(children: [
                  for (var k = 0; k < g.items.length; k++)
                    Expanded(
                      child: Container(
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        child: ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(value: k < _i ? 1 : (k == _i ? _progress.clamp(0, 1) : 0), backgroundColor: Colors.white24, color: Colors.white)),
                      ),
                    ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Avatar(name: g.name, size: 36, photoUrl: g.photoUrl),
                  const SizedBox(width: 10),
                  Expanded(child: Text('${g.name} · ${timeAgo(it.createdAt)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                  if (mine && widget.onDelete != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.white),
                      onPressed: () async {
                        _timer?.cancel();
                        await widget.onDelete!(it.id);
                        if (mounted) Navigator.of(context).pop(true);
                      },
                    ),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Bottom sheet to post a story: a short text, a photo, or both.
Future<bool?> showStoryComposer(BuildContext context) => showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _StoryComposer(),
    );

class _StoryComposer extends StatefulWidget {
  const _StoryComposer();
  @override
  State<_StoryComposer> createState() => _StoryComposerState();
}

class _StoryComposerState extends State<_StoryComposer> {
  final _text = TextEditingController();
  XFile? _file;
  bool _busy = false;

  Future<void> _post() async {
    final api = context.read<AuthProvider>().api;
    setState(() => _busy = true);
    try {
      String? url;
      if (_file != null) url = await api.uploadImage(await _file!.readAsBytes(), _file!.name);
      await api.post('/stories', {if (url != null) 'imageUrl': url, if (_text.text.trim().isNotEmpty) 'text': _text.text.trim()});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, '$e', error: true);
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
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Your update', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        Text('Visible to the network for 24 hours.', style: TextStyle(color: p.muted, fontWeight: FontWeight.w500)),
        const SizedBox(height: 14),
        AppField(controller: _text, hint: "What's new? (optional with a photo)", maxLines: 3, maxLength: 200, autofocus: true, onChanged: (_) => setState(() {})),
        const SizedBox(height: 10),
        GoldButton(
          label: _file == null ? 'Add a photo' : 'Photo: ${_file!.name}',
          outlined: true,
          icon: Icons.photo_library_outlined,
          onPressed: () async {
            final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1280, imageQuality: 75);
            if (f != null) setState(() => _file = f);
          },
        ),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: GoldButton(label: 'Post update', loading: _busy, onPressed: (_file != null || _text.text.trim().isNotEmpty) ? _post : null)),
      ]),
    );
  }
}

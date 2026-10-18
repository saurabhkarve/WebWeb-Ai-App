import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../auth_provider.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets.dart';
import 'image_cropper.dart';

/// Change the profile photo ([kind] avatar) or cover ([kind] cover), as the website's picker: upload a new
/// picture (cropped to its shape first), pick one uploaded before, or (covers) one of WEBWEB's designs, or remove
/// the cover. True when something changed.
Future<bool> showPicturePicker(BuildContext context, String kind) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Pal.of(context).card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PicturePicker(kind: kind),
    ) ==
    true;

class _PicturePicker extends StatefulWidget {
  final String kind;
  const _PicturePicker({required this.kind});
  @override
  State<_PicturePicker> createState() => _PicturePickerState();
}

class _PicturePickerState extends State<_PicturePicker> {
  Map? _data; // {current, mine: [{url, current}], presets: [{name, url, current}]}
  String? _busy; // the url being applied, 'upload' or 'remove'
  String? _error;

  bool get _cover => widget.kind == 'cover';
  AuthProvider get _auth => context.read<AuthProvider>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _auth.api.get('/me/profile-images', {'kind': widget.kind}) as Map;
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// Runs one change, then closes the sheet (true = changed).
  Future<void> _apply(String what, Future<void> Function() change) async {
    setState(() {
      _busy = what;
      _error = null;
    });
    try {
      await change();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _set(String? url) => _auth.updateProfile({_cover ? 'bannerURL' : 'photoURL': url});

  Future<void> _upload() async {
    final auth = _auth;
    try {
      final bytes = await pickAndCrop(context, _cover ? kCoverCrop : kAvatarCrop);
      if (bytes == null || !mounted) return;
      await _apply('upload', () async => _set(await auth.uploadAvatar(bytes, '${widget.kind}.png', kind: widget.kind)));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _remove(String url) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(t('Remove this picture from your earlier pictures?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Remove'))),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await _auth.api.delete('/me/profile-images', {'url': url});
      if (mounted) setState(() => (_data!['mine'] as List).removeWhere((m) => (m as Map)['url'] == url));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Widget _tile(Pal p, String url, bool current, bool removable) {
    final img = ClipRRect(
      borderRadius: BorderRadius.circular(_cover ? 8 : 999),
      child: NetImg(smallImage(url)),
    );
    return Stack(clipBehavior: Clip.none, children: [
      GestureDetector(
        onTap: _busy != null || current ? null : () => _apply(url, () => _set(url)),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_cover ? 10 : 999),
            border: Border.all(color: current ? kGold : Colors.transparent, width: 2),
          ),
          child: AspectRatio(aspectRatio: _cover ? 3 : 1, child: Opacity(opacity: _busy == url ? .5 : 1, child: img)),
        ),
      ),
      if (current)
        Positioned(
          top: 4,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: kGold, borderRadius: BorderRadius.circular(20)),
              child: Text(t('In use'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kInk)),
            ),
          ),
        ),
      if (removable && !current)
        Positioned(
          top: -4,
          right: -4,
          child: GestureDetector(
            onTap: () => _remove(url),
            child: Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: p.ink, shape: BoxShape.circle, border: Border.all(color: p.card, width: 2)),
              child: WIcon(WI.close, size: 12, color: p.onInk, strokeWidth: 2.4),
            ),
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final d = _data;
    final mine = ((d?['mine'] as List?) ?? const []).cast<Map>();
    final presets = ((d?['presets'] as List?) ?? const []).cast<Map>();
    Widget grid(List<Widget> tiles) => GridView.count(
          crossAxisCount: _cover ? 2 : 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: _cover ? 2.8 : .95,
          children: tiles,
        );
    Widget heading(String s) => Padding(padding: const EdgeInsets.only(top: 20, bottom: 8), child: Text(s, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)));

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(t(_cover ? 'Cover' : 'Profile photo'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(t('Close'))),
          ]),
          const SizedBox(height: 8),
          GoldButton(label: t(_cover ? 'Upload a new cover' : 'Upload a new photo'), wi: WI.camera, loading: _busy == 'upload', onPressed: _busy != null ? null : _upload),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(fontSize: 13, color: p.danger))),
          if (d == null && _error == null) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (mine.isNotEmpty) ...[
            heading(t(_cover ? 'Your earlier covers' : 'Your earlier photos')),
            grid([for (final m in mine) _tile(p, '${m['url']}', m['current'] == true, true)]),
          ],
          if (_cover && presets.isNotEmpty) ...[
            heading(t('WEBWEB designs')),
            grid([for (final m in presets) _tile(p, '${m['url']}', m['current'] == true, false)]),
          ],
          if (_cover && d?['current'] != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: _busy != null ? null : () => _apply('remove', () => _set(null)),
              child: Text(t('Remove cover (show the yellow pattern)'), style: TextStyle(color: p.danger, fontWeight: FontWeight.w700)),
            ),
          ],
        ]),
      ),
    );
  }
}

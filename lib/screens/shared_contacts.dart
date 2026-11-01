import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../contact_sync.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets.dart';

/// "Contacts you share": every contact the app sent for Service contacts, with a remove button on each. A removed
/// contact is tagged removed on the server, is not sent again, and sits under "Removed" where it can be shared again.
/// [load]/[onRemove]/[onRestore] default to the server; a preview can pass its own.
class SharedContactsScreen extends StatefulWidget {
  final Future<SharedContacts> Function()? load;
  final Future<void> Function(String phone)? onRemove, onRestore;
  final Future<void> Function(String phone, {int? rating, String? name, String? tag, String? place})? onUpdate;
  const SharedContactsScreen({super.key, this.load, this.onRemove, this.onRestore, this.onUpdate});
  @override
  State<SharedContactsScreen> createState() => _SharedContactsScreenState();
}

class _SharedContactsScreenState extends State<SharedContactsScreen> {
  List<SharedContact>? _shared, _removed;
  String _q = '';
  bool _showRemoved = false, _failed = false;
  String _city = '', _cat = '';
  List<String> _tags = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await (widget.load ?? () => ContactSync.mine(context.read<AuthProvider>().api))();
      if (mounted) setState(() { _shared = r.shared; _removed = r.removed; _city = r.place; _tags = r.tags; _failed = false; });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _move(SharedContact c, {required bool remove}) async {
    final api = widget.load == null ? context.read<AuthProvider>().api : null;
    final run = remove ? (widget.onRemove ?? (ph) => ContactSync.remove(api!, ph)) : (widget.onRestore ?? (ph) => ContactSync.restore(api!, ph));
    try {
      await run(c.phone);
    } catch (_) {
      if (mounted) toast(context, t('Could not do that. Try again.'), error: true);
      return;
    }
    if (!mounted) return;
    setState(() {
      (remove ? _shared! : _removed!).removeWhere((x) => x.phone == c.phone);
      (remove ? _removed! : _shared!).insert(0, c);
      if (remove) _showRemoved = true;
    });
    if (remove) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(t('Removed. It will not be shared again.')),
          action: SnackBarAction(label: t('Undo'), onPressed: () => _move(c, remove: false)),
        ));
    }
  }

  /// Save a change of rating, name, category or place; the row shows it at once and goes back if the server says no.
  Future<void> _save(SharedContact c, {int? rating, String? name, String? tag, String? place}) async {
    final i = _shared!.indexWhere((x) => x.phone == c.phone);
    if (i < 0) return;
    final api = widget.load == null ? context.read<AuthProvider>().api : null;
    setState(() => _shared![i] = c.copyWith(rating: rating, name: name, tag: tag, place: place == null ? null : (place.isEmpty ? _city : place)));
    try {
      await (widget.onUpdate ?? (ph, {rating, name, tag, place}) => ContactSync.update(api!, ph, rating: rating, name: name, tag: tag, place: place))(c.phone, rating: rating, name: name, tag: tag, place: place);
    } catch (_) {
      if (!mounted) return;
      setState(() => _shared![_shared!.indexWhere((x) => x.phone == c.phone)] = c);
      toast(context, t('Could not do that. Try again.'), error: true);
    }
  }

  Future<void> _edit(SharedContact c, [String field = 'name']) async {
    final p = Pal.of(context);
    final r = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.canvas,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _EditSheet(c: c, city: _city, tags: _tags, focus: field),
    );
    if (r == null) return;
    await _save(c,
        name: r['name'] != c.name ? r['name'] : null,
        tag: r['tag']!.isNotEmpty && r['tag'] != c.tag ? r['tag'] : null,
        place: r['place'] != c.place ? r['place'] : null);
  }

  String _catOf(SharedContact c) => c.tag.isNotEmpty ? c.tag : c.keyword;

  bool _hit(SharedContact c) {
    if (_cat.isNotEmpty && _catOf(c) != _cat) return false;
    final q = ContactSync.norm(_q);
    return q.isEmpty || ContactSync.norm('${c.name} ${c.keyword} ${c.phone}').contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final shared = (_shared ?? const <SharedContact>[]).where(_hit).toList();
    final removed = (_removed ?? const <SharedContact>[]).where(_hit).toList();
    final cats = <String, int>{};
    for (final c in _shared ?? const <SharedContact>[]) {
      cats[_catOf(c)] = (cats[_catOf(c)] ?? 0) + 1;
    }
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        backgroundColor: p.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(t('Contacts you share'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: _shared == null
          ? Center(
              child: _failed
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(t('Could not load. Check your connection.'), style: TextStyle(color: p.muted)),
                      TextButton(onPressed: _load, child: Text(t('Retry'))),
                    ])
                  : const CircularProgressIndicator(strokeWidth: 2),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              children: [
                _Hero(shared: _shared!.length, rated: _shared!.where((c) => c.rating > 0).length, removed: _removed!.length, p: p),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (v) => setState(() => _q = v),
                  decoration: InputDecoration(
                    hintText: t('Search your shared contacts'),
                    prefixIcon: Padding(padding: const EdgeInsets.all(12), child: WIcon(WI.search, size: 18, color: p.muted)),
                    filled: true,
                    fillColor: p.field,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                if (cats.length > 1) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 34,
                    child: ListView(scrollDirection: Axis.horizontal, children: [
                      _Chip(label: t('All'), on: _cat.isEmpty, p: p, onTap: () => setState(() => _cat = '')),
                      for (final e in cats.entries) _Chip(label: '${e.key} ${e.value}', on: _cat == e.key, p: p, onTap: () => setState(() => _cat = _cat == e.key ? '' : e.key)),
                    ]),
                  ),
                ],
                const SizedBox(height: 4),
                if (_shared!.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Text(t('You are not sharing any contact right now.'), textAlign: TextAlign.center, style: TextStyle(color: p.muted)),
                  )
                else
                  for (final c in shared) Dismissible(
                      key: ValueKey(c.phone),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) async {
                        await _move(c, remove: true);
                        return false;
                      },
                      background: Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.only(right: 20),
                        alignment: Alignment.centerRight,
                        decoration: BoxDecoration(color: p.danger, borderRadius: BorderRadius.circular(16)),
                        child: const Icon(Icons.delete_outline, color: Colors.white),
                      ),
                      child: _Row(c: c, p: p, action: t("Don't sync"), danger: true, onTap: () => _move(c, remove: true), onEdit: (f) => _edit(c, f), onRate: (n) => _save(c, rating: n)),
                    ),
                if (_removed!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => setState(() => _showRemoved = !_showRemoved),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(children: [
                        Expanded(child: Text('${t('Removed')} (${_removed!.length})', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                        Icon(_showRemoved ? Icons.expand_less : Icons.expand_more, color: p.muted),
                      ]),
                    ),
                  ),
                  if (_showRemoved) for (final c in removed) _Row(c: c, p: p, action: t('Share again'), danger: false, dim: true, onTap: () => _move(c, remove: false)),
                ],
              ],
            ),
    );
  }
}

/// The top card: how many contacts are shared, how many are rated, and a nudge to rate the rest.
class _Hero extends StatelessWidget {
  final int shared, rated, removed;
  final Pal p;
  const _Hero({required this.shared, required this.rated, required this.removed, required this.p});
  @override
  Widget build(BuildContext context) {
    final left = shared - rated;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: kGold.withValues(alpha: .16), borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$shared', style: const TextStyle(fontSize: 34, height: 1, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(width: 8),
          Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 3), child: Text(t('contacts you share'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)))),
          if (removed > 0) Text('$removed ${t('removed')}', style: TextStyle(fontSize: 12, color: p.muted)),
        ]),
        const SizedBox(height: 8),
        Text(t('Only contacts saved as a plumber, cabs, sweet shop and the like are shared, with their number. Swipe left to stop sharing one.'), style: TextStyle(fontSize: 12.5, height: 1.4, color: p.muted)),
        if (shared > 0) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: rated / shared, minHeight: 6, backgroundColor: p.card, valueColor: const AlwaysStoppedAnimation(kGold)),
          ),
          const SizedBox(height: 6),
          Text(left == 0 ? t('All rated. Thank you!') : t('{n} still to rate: your stars help others choose.', {'n': left}), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool on;
  final Pal p;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.on, required this.p, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: on ? p.ink : p.chip, borderRadius: BorderRadius.circular(17)),
            child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? p.onInk : p.text)),
          ),
        ),
      );
}

class _Row extends StatelessWidget {
  final SharedContact c;
  final Pal p;
  final String action;
  final bool danger, dim;
  final VoidCallback onTap;
  final ValueChanged<String>? onEdit;
  final ValueChanged<int>? onRate;
  const _Row({required this.c, required this.p, required this.action, required this.danger, required this.onTap, this.dim = false, this.onEdit, this.onRate});
  @override
  Widget build(BuildContext context) {
    final cat = c.tag.isNotEmpty ? c.tag : c.keyword;
    return Opacity(
      opacity: dim ? .6 : 1,
      child: GestureDetector(
        onTap: onEdit == null ? null : () => onEdit!('name'),
        behavior: HitTestBehavior.opaque,
        child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: p.chip, shape: BoxShape.circle),
              child: Text(initials(c.name), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.muted)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _Editable(onTap: onEdit == null ? null : () => onEdit!('name'), p: p, child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600))),
                const SizedBox(height: 2),
                _Editable(onTap: onEdit == null ? null : () => onEdit!('tag'), p: p, child: Text('${c.phone} · $cat', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted))),
              ]),
            ),
            if (onEdit == null)
              TextButton(
                onPressed: onTap,
                style: TextButton.styleFrom(foregroundColor: p.link, padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 36)),
                child: Text(action, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              )
          ]),
          if (onRate != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(50, 6, 0, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  for (var n = 1; n <= 5; n++)
                    GestureDetector(
                      onTap: () => onRate!(c.rating == n ? 0 : n),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(padding: const EdgeInsets.only(right: 4, top: 2, bottom: 2), child: Icon(n <= c.rating ? Icons.star_rounded : Icons.star_outline_rounded, size: 34, color: n <= c.rating ? kGold : p.border)),
                    ),
                  const SizedBox(width: 2),
                  Icon(Icons.edit_outlined, size: 14, color: p.muted),
                ]),
                const SizedBox(height: 2),
                _Editable(
                  onTap: onEdit == null ? null : () => onEdit!('place'),
                  p: p,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.place_outlined, size: 15, color: p.muted),
                    const SizedBox(width: 3),
                    Flexible(child: Text(c.place.isEmpty ? t('City') : c.place, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.muted))),
                  ]),
                ),
              ]),
            ),
          if (onEdit != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(50, 6, 4, 2),
              child: Row(children: [
                OutlinedButton.icon(
                  onPressed: () => onEdit!('name'),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: Text(t('Edit')),
                  style: OutlinedButton.styleFrom(foregroundColor: p.text, side: BorderSide(color: p.border), visualDensity: VisualDensity.compact, textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.sync_disabled, size: 16),
                  label: Text(action),
                  style: OutlinedButton.styleFrom(foregroundColor: p.danger, side: BorderSide(color: p.danger.withValues(alpha: .4)), visualDensity: VisualDensity.compact, textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
        ]),
      ),
      ),
    );
  }
}

/// A value with a small pencil after it; tapping either opens the editor on that field.
class _Editable extends StatelessWidget {
  final Widget child;
  final Pal p;
  final VoidCallback? onTap;
  const _Editable({required this.child, required this.p, required this.onTap});
  @override
  Widget build(BuildContext context) {
    if (onTap == null) return child;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: child),
          const SizedBox(width: 6),
          Icon(Icons.edit_outlined, size: 14, color: p.muted),
        ]),
      ),
    );
  }
}

/// Edit what the member says about a contact: its name, category and the place it is in (their own city until changed).
class _EditSheet extends StatefulWidget {
  final SharedContact c;
  final String city;
  final List<String> tags;
  final String focus;
  const _EditSheet({required this.c, required this.city, required this.tags, this.focus = 'name'});
  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final _name = TextEditingController(text: widget.c.name);
  late final _tag = TextEditingController(text: widget.c.tag);
  late final _place = TextEditingController(text: widget.c.place);

  @override
  void dispose() {
    _name.dispose();
    _tag.dispose();
    _place.dispose();
    super.dispose();
  }

  InputDecoration _dec(Pal p, String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: p.field,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      );

  Widget _label(Pal p, String s) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: Text(s, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted)));

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final q = ContactSync.norm(_tag.text);
    final exact = widget.tags.any((x) => ContactSync.norm(x) == q);
    final picks = widget.tags.where((x) => q.isEmpty || exact || ContactSync.norm(x).contains(q)).take(12).toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('Edit contact'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          Text(widget.c.phone, style: TextStyle(fontSize: 12, color: p.muted)),
          _label(p, t('Name')),
          TextField(controller: _name, autofocus: widget.focus == 'name', decoration: _dec(p, t('Name'))),
          _label(p, t('Category')),
          TextField(controller: _tag, autofocus: widget.focus == 'tag', onChanged: (_) => setState(() {}), decoration: _dec(p, t('Plumber, Sweet shop, Restaurant…'))),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final x in picks)
              ChoiceChip(
                label: Text(x, style: const TextStyle(fontSize: 12.5)),
                selected: _tag.text.trim().toLowerCase() == x.toLowerCase(),
                onSelected: (_) => setState(() => _tag.text = x),
              ),
          ]),
          _label(p, t('Location')),
          TextField(controller: _place, autofocus: widget.focus == 'place', decoration: _dec(p, widget.city.isEmpty ? t('City') : widget.city)),
          if (widget.city.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: () => setState(() => _place.text = widget.city), style: TextButton.styleFrom(foregroundColor: p.link), child: Text(t('Use my city ({city})', {'city': widget.city}))),
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _name.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, {'name': _name.text.trim(), 'tag': _tag.text.trim(), 'place': _place.text.trim()}),
              style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: kInk, padding: const EdgeInsets.symmetric(vertical: 14)),
              child: Text(t('Save'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}

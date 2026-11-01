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
  const SharedContactsScreen({super.key, this.load, this.onRemove, this.onRestore});
  @override
  State<SharedContactsScreen> createState() => _SharedContactsScreenState();
}

class _SharedContactsScreenState extends State<SharedContactsScreen> {
  List<SharedContact>? _shared, _removed;
  String _q = '';
  bool _showRemoved = false, _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await (widget.load ?? () => ContactSync.mine(context.read<AuthProvider>().api))();
      if (mounted) setState(() { _shared = r.shared; _removed = r.removed; _failed = false; });
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

  Future<void> _confirm(SharedContact c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Stop sharing this contact?')),
        content: Text(t('{name} will be tagged removed on our server and will not be shared again. The contact stays on your phone.', {'name': c.name})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Remove'))),
        ],
      ),
    );
    if (ok == true) await _move(c, remove: true);
  }

  bool _hit(SharedContact c) {
    final q = ContactSync.norm(_q);
    return q.isEmpty || ContactSync.norm('${c.name} ${c.keyword} ${c.phone}').contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final shared = (_shared ?? const <SharedContact>[]).where(_hit).toList();
    final removed = (_removed ?? const <SharedContact>[]).where(_hit).toList();
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
                Text(
                  t('Only contacts saved with a word like plumber or cabs are shared, with their number. Remove any you do not want to share.'),
                  style: TextStyle(fontSize: 13, height: 1.4, color: p.muted),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  _Count(n: _shared!.length, label: t('shared'), p: p),
                  const SizedBox(width: 8),
                  _Count(n: _removed!.length, label: t('removed'), p: p),
                ]),
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
                const SizedBox(height: 8),
                if (_shared!.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Text(t('You are not sharing any contact right now.'), textAlign: TextAlign.center, style: TextStyle(color: p.muted)),
                  )
                else
                  for (final c in shared) _Row(c: c, p: p, action: t('Remove'), danger: true, onTap: () => _confirm(c)),
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

class _Count extends StatelessWidget {
  final int n;
  final String label;
  final Pal p;
  const _Count({required this.n, required this.label, required this.p});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(20)),
        child: Text('$n $label', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
      );
}

class _Row extends StatelessWidget {
  final SharedContact c;
  final Pal p;
  final String action;
  final bool danger, dim;
  final VoidCallback onTap;
  const _Row({required this.c, required this.p, required this.action, required this.danger, required this.onTap, this.dim = false});
  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dim ? .6 : 1,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.border)),
        child: Row(children: [
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
              Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('${c.phone} · ${c.keyword}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted)),
            ]),
          ),
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(foregroundColor: danger ? p.danger : p.link, padding: const EdgeInsets.symmetric(horizontal: 10), minimumSize: const Size(0, 36)),
            child: Text(action, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }
}

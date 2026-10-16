import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../theme.dart';
import '../widgets.dart';

class PickedContact {
  final String name, phone;
  const PickedContact(this.name, this.phone);
  Map<String, String> toJson() => {'name': name, 'phone': phone};
}

String _key(String phone) => phone.replaceAll(RegExp(r'[^\d+]'), '');

/// Multi-select phone-book picker. Pick several contacts, review them, confirm.
/// Pops with the confirmed list (or null if cancelled).
class ContactPicker extends StatefulWidget {
  final String askerName;
  /// How many contacts can still be referred on this ask (the API allows 5 per person per ask).
  final int maxSelect;
  /// Review-step wording: refer on an ask/item (default) or send in a chat.
  final bool forChat;
  const ContactPicker({super.key, required this.askerName, this.maxSelect = 5, this.forChat = false});
  @override
  State<ContactPicker> createState() => _ContactPickerState();
}

class _ContactPickerState extends State<ContactPicker> {
  final _search = TextEditingController();
  List<PickedContact> _all = [];
  final Map<String, PickedContact> _selected = {}; // keyed by number, keeps pick order
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final status = await FlutterContacts.permissions.request(PermissionType.read);
      if (!{'granted', 'limited'}.contains(status.name)) {
        setState(() {
          _loading = false;
          _error = 'Contacts permission is needed to refer people from your phone book.';
        });
        return;
      }
      final contacts = await FlutterContacts.getAll(properties: {ContactProperty.phone});
      final out = <PickedContact>[];
      final seen = <String>{};
      for (final c in contacts) {
        final name = (c.displayName ?? '').trim();
        for (final p in c.phones) {
          final k = _key(p.number);
          if (k.replaceAll('+', '').length < 6 || !seen.add('$name|$k')) continue;
          out.add(PickedContact(name.isEmpty ? p.number : name, p.number.trim()));
        }
      }
      out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (mounted) setState(() {
        _all = out;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'Could not read your contacts.';
      });
    }
  }

  void _toggle(PickedContact c) {
    final k = _key(c.phone);
    if (!_selected.containsKey(k) && _selected.length >= widget.maxSelect) {
      toast(context, 'You can refer up to ${widget.maxSelect} contact${widget.maxSelect == 1 ? '' : 's'} on this ask', error: true);
      return;
    }
    setState(() => _selected.containsKey(k) ? _selected.remove(k) : _selected[k] = c);
  }

  Future<void> _review() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReviewSheet(asker: widget.askerName, forChat: widget.forChat, selected: _selected, onRemove: (k) => setState(() => _selected.remove(k))),
    );
    if (result == true && mounted) Navigator.pop(context, _selected.values.toList());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final q = _search.text.trim().toLowerCase();
    final list = q.isEmpty ? _all : _all.where((c) => c.name.toLowerCase().contains(q) || c.phone.contains(q)).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(_selected.isEmpty ? 'Select contacts' : '${_selected.length} selected', style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [if (_selected.isNotEmpty) TextButton(onPressed: () => setState(_selected.clear), child: const Text('Clear'))],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: AppField(controller: _search, hint: 'Search name or number', prefixIcon: Icon(Icons.search, color: p.muted), onChanged: (_) => setState(() {})),
        ),
        if (_selected.isNotEmpty)
          SizedBox(
            height: 42,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (final e in _selected.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InputChip(
                    label: Text(e.value.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    onDeleted: () => setState(() => _selected.remove(e.key)),
                    backgroundColor: p.chip,
                    side: BorderSide(color: p.border),
                  ),
                ),
            ]),
          ),
        Expanded(
          child: _loading
              ? const Center(child: LogoLoader())
              : _error != null
                  ? Center(child: Padding(padding: const EdgeInsets.all(28), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: p.muted))))
                  : list.isEmpty
                      ? Center(child: Text(_all.isEmpty ? 'No contacts with phone numbers' : 'No match', style: TextStyle(color: p.muted)))
                      : ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final c = list[i];
                            final on = _selected.containsKey(_key(c.phone));
                            return CheckboxListTile(
                              value: on,
                              onChanged: (_) => _toggle(c),
                              activeColor: kGold,
                              checkColor: Colors.black,
                              controlAffinity: ListTileControlAffinity.trailing,
                              secondary: Avatar(name: c.name, size: 42),
                              title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text(c.phone, style: TextStyle(color: p.muted)),
                            );
                          },
                        ),
        ),
        SafeArea(
          top: false,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.border))),
            child: GoldButton(label: _selected.isEmpty ? 'Select at least one contact' : 'Review ${_selected.length} contact${_selected.length == 1 ? '' : 's'}', onPressed: _selected.isEmpty ? null : _review),
          ),
        ),
      ]),
    );
  }
}

/// "Are you sure?" step: shows exactly what will be shared.
class _ReviewSheet extends StatefulWidget {
  final String asker;
  final bool forChat;
  final Map<String, PickedContact> selected;
  final void Function(String key) onRemove;
  const _ReviewSheet({required this.asker, this.forChat = false, required this.selected, required this.onRemove});
  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final items = widget.selected.entries.toList();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${widget.forChat ? 'Send' : 'Refer'} ${items.length} contact${items.length == 1 ? '' : 's'}?', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(widget.forChat ? '${widget.asker} will get these names and numbers in this chat.' : '${widget.asker} will see these names and numbers. Other people only see that contacts were shared.', style: TextStyle(color: p.muted, fontWeight: FontWeight.w500)),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final e in items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Avatar(name: e.value.name, size: 40),
                    title: Text(e.value.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(e.value.phone, style: const TextStyle(color: kGold, fontWeight: FontWeight.w600)),
                    trailing: IconButton(
                      icon: Icon(Icons.close, color: p.muted),
                      onPressed: () {
                        widget.onRemove(e.key);
                        setState(() {});
                        if (widget.selected.isEmpty) Navigator.pop(context, false);
                      },
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: GoldButton(label: 'Back', outlined: true, onPressed: () => Navigator.pop(context, false))),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: GoldButton(label: widget.forChat ? 'Send' : 'Confirm & refer', icon: Icons.check, onPressed: () => Navigator.pop(context, true))),
            ]),
          ]),
        ),
      ),
    );
  }
}

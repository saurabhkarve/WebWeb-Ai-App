import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../i18n.dart';
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
          _error = t('Contacts permission is needed to refer people from your phone book.');
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
      if (mounted) {
        setState(() {
          _all = out;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = t('Could not read your contacts.');
        });
      }
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
      backgroundColor: Pal.of(context).canvas,
      barrierColor: kInk.withValues(alpha: .6),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
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
    return SubPage(
      title: _selected.isEmpty ? t('Select contacts') : '${_selected.length} ${t('selected')}',
      actions: [
        if (_selected.isNotEmpty)
          GestureDetector(
            onTap: () => setState(_selected.clear),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Text(t('Clear'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.link))),
          ),
      ],
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(30)),
            child: Row(children: [
              WIcon(WI.search, size: 20, color: p.muted),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    hintText: t('Search name or number'),
                    hintStyle: TextStyle(color: p.muted, fontWeight: FontWeight.w500),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              if (_search.text.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(_search.clear),
                  child: WIcon(WI.close, size: 18, color: p.muted),
                ),
            ]),
          ),
        ),
        if (_selected.isNotEmpty)
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
              for (final e in _selected.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    padding: const EdgeInsets.only(left: 12, right: 6),
                    decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(e.value.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.onInk)),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => setState(() => _selected.remove(e.key)),
                        child: Padding(padding: const EdgeInsets.all(4), child: WIcon(WI.close, size: 14, color: p.onInk)),
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
        Expanded(
          child: _loading
              ? const Center(child: LogoLoader())
              : _error != null
                  ? EmptyState(title: _error!)
                  : list.isEmpty
                      ? EmptyState(title: t(_all.isEmpty ? 'No contacts with phone numbers' : 'No match'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final c = list[i];
                            final on = _selected.containsKey(_key(c.phone));
                            return InkWell(
                              onTap: () => _toggle(c),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: i == 0 ? null : BoxDecoration(border: Border(top: BorderSide(color: p.border.withValues(alpha: .6)))),
                                child: Row(children: [
                                  Avatar(name: c.name, size: 40),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.25)),
                                      Text(c.phone, style: TextStyle(fontSize: 14, color: p.muted, height: 1.25)),
                                    ]),
                                  ),
                                  _Check(on: on),
                                ]),
                              ),
                            );
                          },
                        ),
        ),
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
          decoration: BoxDecoration(color: p.canvas, border: Border(top: BorderSide(color: p.border))),
          child: GoldButton(
            label: _selected.isEmpty ? t('Select at least one contact') : 'Review ${_selected.length} contact${_selected.length == 1 ? '' : 's'}',
            onPressed: _selected.isEmpty ? null : _review,
          ),
        ),
      ]),
    );
  }
}

/// The web's checkbox: rounded square, ink when ticked.
class _Check extends StatelessWidget {
  final bool on;
  const _Check({required this.on});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: on ? p.ink : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: on ? p.ink : p.border, width: 1.5),
      ),
      child: on ? WIcon(WI.check, size: 16, strokeWidth: 2.4, color: p.onInk) : null,
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
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .8),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text('${widget.forChat ? 'Send' : 'Refer'} ${items.length} contact${items.length == 1 ? '' : 's'}?', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            GestureDetector(onTap: () => Navigator.pop(context, false), child: WIcon(WI.close, size: 24, color: p.text)),
          ]),
          const SizedBox(height: 4),
          Text(
            widget.forChat
                ? '${widget.asker} will get these names and numbers in this chat.'
                : '${widget.asker} will see these names and numbers. Other people only see that contacts were shared.',
            style: TextStyle(fontSize: 14, color: p.muted),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (var i = 0; i < items.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: i == 0 ? null : BoxDecoration(border: Border(top: BorderSide(color: p.border))),
                  child: Row(children: [
                    Avatar(name: items[i].value.name, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(items[i].value.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.25)),
                        Text(items[i].value.phone, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.link, height: 1.25)),
                      ]),
                    ),
                    InkResponse(
                      radius: 20,
                      onTap: () {
                        widget.onRemove(items[i].key);
                        setState(() {});
                        if (widget.selected.isEmpty) Navigator.pop(context, false);
                      },
                      child: Padding(padding: const EdgeInsets.all(8), child: WIcon(WI.close, size: 20, color: p.muted)),
                    ),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: GoldButton(label: t('Back'), outlined: true, onPressed: () => Navigator.pop(context, false))),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: GoldButton(label: widget.forChat ? t('Send') : t('Confirm & refer'), wi: WI.check, onPressed: () => Navigator.pop(context, true))),
          ]),
        ]),
      ),
    );
  }
}

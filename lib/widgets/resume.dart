import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n.dart';
import '../theme.dart';
import '../widgets.dart';

/// A resume line "Role · Organisation · 2019 - 2021" split into its parts.
class _Entry {
  final String raw, head, org, period, from, to;
  final bool current;
  _Entry(this.raw, this.head, this.org, this.period, this.from, this.to, this.current);
  factory _Entry.parse(String row) {
    final parts = row.split(RegExp(r'\s[·|]\s')).map((e) => e.trim()).toList();
    final last = parts.length > 1 ? parts.last : '';
    final hasPeriod = RegExp(r'(\d{4}|present|current|now)', caseSensitive: false).hasMatch(last);
    final ft = hasPeriod ? last.split(RegExp(r'\s*[-–]\s*')) : <String>[];
    return _Entry(
      row,
      parts.isEmpty ? '' : parts.first,
      parts.length <= 1 ? '' : parts.sublist(1, hasPeriod ? parts.length - 1 : parts.length).join(' · '),
      hasPeriod ? last : '',
      ft.isNotEmpty ? ft[0].trim() : '',
      ft.length > 1 ? ft[1].trim() : '',
      RegExp(r'(present|current|now)\s*$', caseSensitive: false).hasMatch(last),
    );
  }
}

/// Resume timeline (web ResumeList): a gold rail with a node per entry; the current role is haloed.
/// On your own profile entries can be added, edited and deleted.
class ResumeList extends StatelessWidget {
  final String title;
  final String? text;
  final WI icon;
  final String kind;
  final bool editable;
  final Future<void> Function(String next) onSave;
  const ResumeList({super.key, required this.title, required this.text, required this.icon, required this.kind, required this.editable, required this.onSave});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final rows = (text ?? '').split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (rows.isEmpty && !editable) return const SizedBox.shrink();
    final entries = rows.map(_Entry.parse).toList();
    Future<void> write(List<String> next) => onSave(next.join('\n'));
    Future<void> openSheet(int? index) => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: p.canvas,
          barrierColor: kInk.withValues(alpha: .6),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          builder: (_) => _ResumeEntrySheet(
            kind: kind,
            initial: index == null ? null : rows[index],
            onSave: (line) => write(index == null ? [...rows, line] : [for (var j = 0; j < rows.length; j++) j == index ? line : rows[j]]),
          ),
        );
    final tagFg = p.dark ? const Color(0xFFFFC700) : const Color(0xFF7A5A00);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Container(width: 28, height: 28, decoration: BoxDecoration(color: p.chip, shape: BoxShape.circle), child: Center(child: WIcon(icon, size: 15, color: p.text, strokeWidth: 2.1))),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
        if (editable)
          GestureDetector(
            onTap: () => openSheet(null),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [WIcon(WI.plus, size: 14, color: p.text), const SizedBox(width: 4), Text(t('Add'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))]),
            ),
          ),
      ]),
      const SizedBox(height: 12),
      if (entries.isEmpty && editable)
        DashedBox(
          radius: 8,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Text(t(kind == 'experience' ? 'Nothing here yet. Tap Add to put your experience on your profile.' : 'Nothing here yet. Tap Add to put your education on your profile.'), style: TextStyle(fontSize: 14, color: p.muted)),
        ),
      for (var i = 0; i < entries.length; i++)
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // rail + node
            SizedBox(
              width: 38,
              child: Stack(children: [
                if (i < entries.length - 1)
                  Positioned(
                    left: 13,
                    top: 12,
                    bottom: 0,
                    child: Container(width: 2, decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [kGold.withValues(alpha: .8), p.border]))),
                  ),
                Positioned(
                  left: 8,
                  top: 4,
                  child: Opacity(
                    opacity: entries[i].current ? 1 : .7,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        gradient: kGoldGradient,
                        shape: BoxShape.circle,
                        border: Border.all(color: p.canvas, width: 0),
                        boxShadow: [
                          BoxShadow(color: p.canvas, spreadRadius: 4),
                          if (entries[i].current) const BoxShadow(color: Color(0x40D8B81C), spreadRadius: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: i < entries.length - 1 ? 20 : 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: p.chip.withValues(alpha: .6), borderRadius: BorderRadius.circular(8)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: Text(entries[i].head, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.375))),
                      if (entries[i].current)
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: kGold.withValues(alpha: .25), borderRadius: BorderRadius.circular(20)),
                          child: Text(t('Current'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: tagFg)),
                        ),
                      if (editable) ...[
                        GestureDetector(onTap: () => openSheet(i), child: Padding(padding: const EdgeInsets.all(4), child: WIcon(WI.edit, size: 16, color: p.muted))),
                        GestureDetector(
                          onTap: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                content: Text(t('Delete this entry?')),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Cancel'), style: TextStyle(color: p.text))),
                                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Delete'), style: TextStyle(color: p.danger))),
                                ],
                              ),
                            );
                            if (ok == true) {
                              try {
                                await write([for (var j = 0; j < rows.length; j++) if (j != i) rows[j]]);
                              } catch (_) {}
                            }
                          },
                          child: Padding(padding: const EdgeInsets.all(4), child: WIcon(WI.trash, size: 16, color: p.muted)),
                        ),
                      ],
                    ]),
                    if (entries[i].org.isNotEmpty) Text(entries[i].org, style: TextStyle(fontSize: 14, color: p.muted, height: 1.375)),
                    if (entries[i].period.isNotEmpty)
                      Padding(padding: const EdgeInsets.only(top: 4), child: Text(entries[i].period, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.link))),
                  ]),
                ),
              ),
            ),
          ]),
        ),
    ]);
  }
}

class _ResumeEntrySheet extends StatefulWidget {
  final String kind;
  final String? initial;
  final Future<void> Function(String line) onSave;
  const _ResumeEntrySheet({required this.kind, this.initial, required this.onSave});
  @override
  State<_ResumeEntrySheet> createState() => _ResumeEntrySheetState();
}

class _ResumeEntrySheetState extends State<_ResumeEntrySheet> {
  late final _Entry? _e0 = widget.initial == null ? null : _Entry.parse(widget.initial!);
  late final _head = TextEditingController(text: _e0?.head ?? '');
  late final _org = TextEditingController(text: _e0?.org ?? '');
  late final _from = TextEditingController(text: _e0?.from ?? '');
  late final _to = TextEditingController(text: _e0 != null && !_e0!.current ? _e0!.to : '');
  late bool _current = _e0?.current ?? false;
  bool _busy = false;
  String? _error;

  bool get _isExp => widget.kind == 'experience';

  Future<void> _save() async {
    final from = _from.text.trim(), to = _to.text.trim();
    final period = from.isNotEmpty ? '$from${_current ? ' - Present' : to.isNotEmpty ? ' - $to' : ''}' : (_current ? 'Present' : to);
    final line = [_head.text.trim(), _org.text.trim(), period].where((s) => s.isNotEmpty).join(' · ');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(line);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _head.dispose();
    _org.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final digits = [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)];
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(t(widget.initial != null ? (_isExp ? 'Edit experience' : 'Edit education') : (_isExp ? 'Add experience' : 'Add education')), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            GestureDetector(onTap: () => Navigator.pop(context), child: WIcon(WI.close, size: 24, color: p.text)),
          ]),
          const SizedBox(height: 16),
          AppField(controller: _head, label: t(_isExp ? 'Role *' : 'Course / degree *'), hint: t(_isExp ? 'e.g. CNC Operator' : 'e.g. ITI Fitter'), maxLength: 80, onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          AppField(controller: _org, label: t(_isExp ? 'Company, place' : 'Institute, place'), hint: t(_isExp ? 'e.g. Precision Tools Pvt Ltd, Turbhe' : 'e.g. Govt ITI Panvel'), maxLength: 80),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: AppField(controller: _from, label: t('From (year)'), hint: '2019', keyboard: TextInputType.number, inputFormatters: digits)),
            const SizedBox(width: 12),
            Expanded(
              child: _current
                  ? AppField(label: t('To (year)'), hint: t('Present'), enabled: false)
                  : AppField(controller: _to, label: t('To (year)'), hint: '2022', keyboard: TextInputType.number, inputFormatters: digits),
            ),
          ]),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => setState(() => _current = !_current),
            child: Row(children: [
              SizedBox(width: 24, height: 24, child: Checkbox(value: _current, activeColor: kInk, onChanged: (v) => setState(() => _current = v ?? false))),
              const SizedBox(width: 8),
              Text(t(_isExp ? 'I currently work here' : 'I am currently studying here'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ]),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(fontSize: 14, color: p.danger))),
          const SizedBox(height: 16),
          GoldButton(label: t('Save'), loading: _busy, onPressed: _head.text.trim().length < 2 ? null : _save),
        ]),
      ),
    );
  }
}

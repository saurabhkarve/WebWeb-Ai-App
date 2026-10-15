import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// A form field that opens a bottom sheet to choose one [Option] (category, location, urgency...).
class PickerField extends StatelessWidget {
  final String label;
  final String? hint;
  final List<Option> options;
  final String? value;
  final ValueChanged<String> onChanged;
  final bool required;
  const PickerField({super.key, required this.label, this.hint, required this.options, required this.value, required this.onChanged, this.required = false});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final selected = options.where((o) => o.value == value).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(required ? '$label *' : label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
      GestureDetector(
        onTap: () async {
          final v = await showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            builder: (ctx) => SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .75),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Padding(padding: const EdgeInsets.all(16), child: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                  Flexible(
                    child: ListView(shrinkWrap: true, children: [
                      for (final o in options)
                        ListTile(
                          title: Text(o.label, style: TextStyle(fontWeight: o.value == value ? FontWeight.w700 : FontWeight.w500)),
                          trailing: o.value == value ? const Icon(Icons.check, color: kGold) : null,
                          onTap: () => Navigator.pop(ctx, o.value),
                        ),
                    ]),
                  ),
                ]),
              ),
            ),
          );
          if (v != null) onChanged(v);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(color: p.field, borderRadius: BorderRadius.circular(14), border: Border.all(color: selected.isEmpty ? p.border : kGold.withValues(alpha: .6))),
          child: Row(children: [
            Expanded(child: Text(selected.isEmpty ? (hint ?? 'Select') : selected.first.label, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: selected.isEmpty ? p.muted : p.text))),
            Icon(Icons.expand_more, color: p.muted),
          ]),
        ),
      ),
    ]);
  }
}

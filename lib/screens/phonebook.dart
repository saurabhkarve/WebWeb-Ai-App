import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../contact_sync.dart';
import '../i18n.dart';
import '../links.dart';
import '../permissions.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/reviews_card.dart';
import 'profile.dart';

/// The AI Phonebook (web /phonebook): which of my contacts already have a WEBWEB page, with what they do, where
/// and their reviews. Only when the member taps "Check my contacts": the numbers are sent once to
/// POST /phonebook/match (which leaves out the member's own number) and not stored; names never leave the phone. Contacts not on WEBWEB can be invited.
class PhonebookScreen extends StatefulWidget {
  const PhonebookScreen({super.key});
  @override
  State<PhonebookScreen> createState() => _PhonebookScreenState();
}

class _PhonebookScreenState extends State<PhonebookScreen> {
  /// number -> name saved on the phone
  Map<String, String>? _contacts;
  List<Map>? _matches;
  bool _busy = false;
  String? _error;
  String _q = '';

  Future<void> _check() async {
    final ok = await Permissions.ensure(context, Need.contacts, reason: t('To show which of your contacts have a page. Numbers are checked and not kept.'));
    if (!ok || !mounted) return;
    setState(() => (_busy = true, _error = null));
    try {
      final all = await FlutterContacts.getAll(properties: {ContactProperty.phone});
      final book = <String, String>{};
      for (final c in all) {
        for (final ph in c.phones) {
          final m = ContactSync.mobile10(ph.number);
          if (m != null) book.putIfAbsent(m, () => (c.displayName ?? '').trim());
        }
      }
      if (book.isEmpty) throw t('No Indian mobile numbers found');
      if (!mounted) return;
      final r = await context.read<AuthProvider>().api.post('/phonebook/match', {'phones': book.keys.take(3000).toList()}) as Map;
      if (mounted) setState(() => (_contacts = book, _matches = (r['matches'] as List).cast<Map>(), _busy = false));
    } catch (e) {
      if (mounted) setState(() => (_busy = false, _error = '$e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final book = _contacts;
    final matches = _matches;
    if (book == null || matches == null) return _intro(p);

    final q = _q.trim().toLowerCase();
    final on = matches.where((m) => q.isEmpty || '${m['name']} ${m['company']} ${m['category']} ${m['location']} ${(m['services'] as List? ?? const []).join(' ')}'.toLowerCase().contains(q)).toList();
    final onPhones = matches.map((m) => '${m['phone']}').toSet();
    final notOn = book.entries.where((e) => !onPhones.contains(e.key) && e.value.isNotEmpty && (q.isEmpty || e.value.toLowerCase().contains(q))).take(50).toList();

    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
      Row(children: [
        Expanded(child: _stat(p, '${matches.length}', t('contacts have a page'))),
        const SizedBox(width: 12),
        Expanded(child: _stat(p, '${book.length - matches.length}', t('are not on WEBWEB yet'))),
      ]),
      const SizedBox(height: 12),
      TextField(
        onChanged: (v) => setState(() => _q = v),
        decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t('Search your phonebook: name, service, area')),
      ),
      const SizedBox(height: 4),
      for (final m in on) _match(p, m, book['${m['phone']}']),
      if (on.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Text(t('None of these contacts have a page yet. Invite them below.'), textAlign: TextAlign.center, style: TextStyle(color: p.muted))),
      if (notOn.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text(t('Invite to the phonebook'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        for (final e in notOn)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Avatar(name: e.value, size: 36),
            title: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: OutlinedButton(
              onPressed: () => openExternal(context, 'https://wa.me/91${e.key}?text=${Uri.encodeComponent('${t('I have a free business page on WEBWEB, the AI Phonebook. Make yours so customers can find and review you:')} https://webweb.ai')}'),
              style: OutlinedButton.styleFrom(shape: const StadiumBorder(), visualDensity: VisualDensity.compact),
              child: Text(t('Invite')),
            ),
          ),
      ],
    ]);
  }

  Widget _intro(Pal p) => ListView(padding: const EdgeInsets.all(20), children: [
        const SizedBox(height: 8),
        Center(child: Icon(Icons.contacts_rounded, size: 64, color: kStar.withValues(alpha: .9))),
        const SizedBox(height: 16),
        Text(t('See which of your contacts have a page: what they do, where they are and their reviews.'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.35)),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _check,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: kStar, foregroundColor: kInk, shape: const StadiumBorder()),
          child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: kInk)) : Text(t('Check my contacts'), style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: p.danger))),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(14)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.lock_outline_rounded, size: 18, color: p.muted),
            const SizedBox(width: 10),
            Expanded(child: Text(t('Only the numbers are sent, once, to find matching pages. They are not stored or shown to anyone, and names stay on your phone.'), style: TextStyle(fontSize: 13, height: 1.4, color: p.muted))),
          ]),
        ),
      ]);

  Widget _stat(Pal p, String n, String label) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(n, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted)),
        ]),
      );

  Widget _match(Pal p, Map m, String? saved) {
    final who = displayName('${m['userType'] ?? ''}', '${m['name'] ?? ''}', '${m['company'] ?? ''}');
    final reviews = (m['reviews'] as num?)?.toInt() ?? 0;
    final rating = (m['rating'] as num?)?.toDouble() ?? 0;
    final services = (m['services'] as List? ?? const []).take(3).join(' · ');
    final where = ['${m['category'] ?? ''}', '${m['location'] ?? ''}'].where((s) => s.isNotEmpty).join(' · ');
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: '${m['handle']}'))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Avatar(name: who, photoUrl: m['photoURL'] as String?, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(who, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                if (((m['verificationLevel'] as num?) ?? 0) > 0) ...[const SizedBox(width: 4), VerifiedBadge(level: (m['verificationLevel'] as num).toInt(), size: 14)],
              ]),
              if (where.isNotEmpty) Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted)),
              if ((saved ?? '').isNotEmpty && saved != who) Text(t('Saved as {name}', {'name': saved!}), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: p.muted)),
              if (services.isNotEmpty) Text(services, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            ]),
          ),
          if (reviews > 0)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Stars(value: rating, size: 11),
              Text('${rating.toStringAsFixed(1)} · $reviews', style: TextStyle(fontSize: 11, color: p.muted)),
            ]),
        ]),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth_provider.dart';
import '../contact_sync.dart';
import '../i18n.dart';
import '../links.dart';
import '../permissions.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/reviews_card.dart';
import 'find.dart';
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
      final matches = (r['matches'] as List).cast<Map>();
      await PhonebookCache.save(matches, book);
      if (mounted) setState(() => (_contacts = book, _matches = matches, _busy = false));
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
        Text(t('Invite to the phonebook'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
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
          child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: kInk)) : Text(t('Check my contacts'), style: const TextStyle(fontWeight: FontWeight.w700)),
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
          Text(n, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
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

/// The last contact check, on this phone only (web: localStorage webweb_phonebook): who has a page and what the
/// member saved them as. The numbers themselves are left out.
class PhonebookCache {
  static const _k = 'pb_cache';

  static Future<void> save(List<Map> matches, Map<String, String> book) async {
    final list = [
      for (final m in matches) {...Map<String, dynamic>.from(m)..remove('phone'), if ((book['${m['phone']}'] ?? '').isNotEmpty) 'saved': book['${m['phone']}']},
    ];
    await (await SharedPreferences.getInstance()).setString(_k, jsonEncode({'at': DateTime.now().millisecondsSinceEpoch, 'matches': list}));
  }

  /// null: never checked on this phone
  static Future<List<Map>?> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_k);
    if (raw == null) return null;
    try {
      return ((jsonDecode(raw) as Map)['matches'] as List).cast<Map>();
    } catch (_) {
      return null;
    }
  }
}

/// The Contacts tab (web phonebook-home.tsx), like a phone's contacts: my card, search a name, trade or area, and
/// the contacts who have a page (from the last check) A to Z.
class PhonebookHome extends StatefulWidget {
  const PhonebookHome({super.key});
  @override
  State<PhonebookHome> createState() => _PhonebookHomeState();
}

class _PhonebookHomeState extends State<PhonebookHome> {
  final _q = TextEditingController();
  List<Map>? _contacts;
  List<Map>? _results;
  Map? _mine;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadContacts();
    final me = context.read<AuthProvider>().profile;
    if (me != null) {
      context.read<AuthProvider>().api.get('/users/${me.uid}/reviews', {'limit': '1'}).then((d) {
        if (mounted) setState(() => _mine = d as Map);
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    final c = await PhonebookCache.load();
    if (mounted) setState(() => _contacts = c);
  }

  void _search(String v) {
    _debounce?.cancel();
    setState(() {});
    if (v.trim().length < 2) return setState(() => _results = null);
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final d = await context.read<AuthProvider>().api.get('/users/search', {'q': v.trim()});
        if (mounted) setState(() => _results = (d as List).cast<Map>());
      } catch (_) {
        if (mounted) setState(() => _results = const []);
      }
    });
  }

  Future<void> _openCheck() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => SubPage(title: t('Phonebook'), body: const PhonebookScreen())));
    _loadContacts();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final q = _q.text.trim().toLowerCase();
    final mine = (_contacts ?? const <Map>[])
        .where((m) => q.isEmpty || '${m['name']} ${m['company']} ${m['saved'] ?? ''} ${m['category']} ${m['location']} ${(m['services'] as List? ?? const []).join(' ')}'.toLowerCase().contains(q))
        .toList();
    final me = context.watch<AuthProvider>().profile;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 120), children: [
      Text(t('Contacts'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      TextField(
        controller: _q,
        onChanged: _search,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          hintText: t('Search a name, trade or area'),
          suffixIcon: _q.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () {
                  _q.clear();
                  _search('');
                }),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
        ),
      ),
      if (q.length >= 2) ...[
        if (mine.isNotEmpty) ...[_label(p, t('In your contacts')), for (final m in mine.take(10)) _row(p, m, saved: m['saved'] as String?)],
        _label(p, t('On WEBWEB')),
        for (final u in (_results ?? const <Map>[]).where((u) => !mine.any((m) => m['uid'] == u['uid'])).take(20)) _row(p, u),
        if (_results != null && _results!.isEmpty && mine.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FindScreen(standalone: true, initialQuery: _q.text.trim()))),
                child: Text('${t('No one found.')} ${t('Search nearby')}'),
              ),
            ),
          ),
      ] else ...[
        // my card, as at the top of a phone's contacts
        if (me != null) ...[const SizedBox(height: 14), _myCard(p, me.uid, me.handle, displayName(me.userType, me.name, me.company), me.photoUrl)],
        const SizedBox(height: 14),
        if (_contacts == null)
          InkWell(
            onTap: _openCheck,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: kStar.withValues(alpha: p.dark ? .12 : .1), borderRadius: BorderRadius.circular(18), border: Border.all(color: kStar.withValues(alpha: .6))),
              child: Row(children: [
                Container(width: 46, height: 46, decoration: const BoxDecoration(gradient: kGoldGradient, shape: BoxShape.circle), child: const Icon(Icons.contacts_rounded, color: kInk)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t('See who in your contacts has a page'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(t('What they do, where they are and their reviews. Numbers are checked and not kept.'), style: TextStyle(fontSize: 13, color: p.muted, height: 1.35)),
                  ]),
                ),
              ]),
            ),
          )
        else ...[
          Row(children: [
            Expanded(child: Text(t('{n} contacts on WEBWEB', {'n': _contacts!.length}), style: TextStyle(fontSize: 13, color: p.muted))),
            TextButton(onPressed: _openCheck, child: Text(t('Check again'))),
          ]),
          if (_contacts!.isEmpty) Text(t('None of your contacts have a page yet. Invite them from the contact check.'), style: TextStyle(color: p.muted)),
          // A to Z, a letter over each group
          for (final e in _byLetter(_contacts!).entries) ...[
            Padding(padding: const EdgeInsets.only(top: 10, bottom: 2), child: Text(e.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kStar))),
            for (final m in e.value) _row(p, m, saved: m['saved'] as String?),
          ],
        ],
      ],
    ]);
  }

  Widget _label(Pal p, String s) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 2),
        child: Text(s.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.25, color: p.muted)),
      );

  Widget _row(Pal p, Map m, {String? saved}) {
    final who = displayName('${m['userType'] ?? ''}', '${m['name'] ?? ''}', '${m['company'] ?? ''}');
    final where = ['${m['category'] ?? ''}', '${m['location'] ?? ''}'].where((s) => s.isNotEmpty).join(' · ');
    final reviews = (m['reviews'] as num?)?.toInt() ?? 0;
    final rating = (m['rating'] as num?)?.toDouble() ?? 0;
    final level = (m['verificationLevel'] as num?)?.toInt() ?? 0;
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: '${m['handle']}'))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(children: [
          Avatar(name: who, photoUrl: (m['photoURL'] ?? m['photoUrl']) as String?, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(who, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                if (level > 0) ...[const SizedBox(width: 4), VerifiedBadge(level: level, size: 14)],
              ]),
              if (where.isNotEmpty) Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted)),
              if ((saved ?? '').isNotEmpty && saved != who) Text(t('Saved as {name}', {'name': saved!}), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: p.muted)),
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

  /// Contacts grouped by the first letter of the name shown (or the name saved on the phone), A to Z; the rest under #.
  Map<String, List<Map>> _byLetter(List<Map> list) {
    String name(Map m) => displayName('${m['userType'] ?? ''}', '${m['name'] ?? ''}', '${m['company'] ?? ''}');
    final sorted = [...list]..sort((x, y) => name(x).toLowerCase().compareTo(name(y).toLowerCase()));
    final out = <String, List<Map>>{};
    for (final m in sorted) {
      final c = name(m).isEmpty ? '#' : name(m)[0].toUpperCase();
      (out[RegExp(r'[A-Z]').hasMatch(c) ? c : '#'] ??= []).add(m);
    }
    return out;
  }

  Widget _myCard(Pal p, String uid, String handle, String name, String? photo) {
    final count = (_mine?['count'] as num?)?.toInt() ?? 0;
    final avg = (_mine?['avg'] as num?)?.toDouble() ?? 0;
    final ask = '${t('Thank you for your business! Could you review {name} on WEBWEB? It takes a minute:', {'name': name})} https://webweb.ai/@$handle#reviews';
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: handle))),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: p.border)),
        child: Row(children: [
          Avatar(name: name, photoUrl: photo, size: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Text(t('My page'), style: TextStyle(fontSize: 12, color: p.muted)),
              if (count > 0)
                Row(children: [Stars(value: avg, size: 11), const SizedBox(width: 4), Text('${avg.toStringAsFixed(1)} · $count', style: TextStyle(fontSize: 11, color: p.muted))]),
            ]),
          ),
          TextButton.icon(
            onPressed: () => openExternal(context, 'https://wa.me/?text=${Uri.encodeComponent(ask)}'),
            icon: const Icon(Icons.star_outline_rounded, size: 18, color: kStar),
            label: Text(t('Ask for a review'), style: const TextStyle(fontSize: 12)),
          ),
        ]),
      ),
    );
  }
}

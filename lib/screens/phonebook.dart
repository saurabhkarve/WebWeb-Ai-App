import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ask_types.dart';
import '../auth_provider.dart';
import '../card_colors.dart';
import '../contact_sync.dart';
import '../i18n.dart';
import '../links.dart';
import '../location.dart' show PermissionNotGiven, currentLocation;
import '../models.dart';
import '../permissions.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/area_map.dart' show askTimeLeft;
import '../widgets/reviews_card.dart';
import 'find.dart';
import 'post_detail.dart';
import 'profile.dart';
import 'your_asks.dart' show askPrefill;

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
/// member saved them as. The app keeps each match's number too (the phone's own contacts have it anyway), so the
/// directory can put the page next to the right contact; it never leaves the phone.
class PhonebookCache {
  static const _k = 'pb_cache';

  static Future<void> save(List<Map> matches, Map<String, String> book) async {
    final list = [
      for (final m in matches) {...Map<String, dynamic>.from(m), if ((book['${m['phone']}'] ?? '').isNotEmpty) 'saved': book['${m['phone']}']},
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

/// One line of the directory: a contact saved on the phone, a WEBWEB page (from the last check), or both.
class _Entry {
  final String name;
  final String? phone;
  final Map? member;
  const _Entry(this.name, this.phone, this.member);

  String get letter {
    final c = name.isEmpty ? '#' : name[0].toUpperCase();
    return RegExp(r'[A-Z]').hasMatch(c) ? c : '#';
  }
}

/// The Contacts tab, the heart of the Smart Phonebook (web phonebook-home.tsx), laid out like a phone's contact
/// directory: search, my card, the open asks around me, then every contact A to Z with a letter index down the side.
/// Contacts who have a WEBWEB page show what they do and their reviews and open their page; the others can be
/// called, messaged or invited.
/// - The phone book is read on the phone, only once the member allows contacts; nothing is sent to show it.
/// - Matching it to pages is the separate "Check my contacts" (POST /phonebook/match), which the member starts.
/// - On the web, and before contacts are allowed, the directory is the pages from the last check.
/// - From 900 px wide the asks move to a column of their own beside the directory.
class PhonebookHome extends StatefulWidget {
  /// open the ask composer, and the feed of asks (the Updates tab)
  final VoidCallback? onAsk, onSeeAsks;
  const PhonebookHome({super.key, this.onAsk, this.onSeeAsks});
  @override
  State<PhonebookHome> createState() => _PhonebookHomeState();
}

class _PhonebookHomeState extends State<PhonebookHome> {
  static const _headH = 30.0, _rowH = 64.0;
  final _q = TextEditingController();
  final _scroll = ScrollController();
  final _topKey = GlobalKey();
  List<Map>? _matches;
  /// the phone's own contacts: null until read (not allowed yet, or not a phone)
  List<Contact>? _device;
  bool _canRead = false, _reading = false;
  List<Map>? _results;
  List<Post>? _asks;
  Map? _mine;
  Timer? _debounce, _aiTimer;
  String? _scrubbing;
  /// Ask AI: the answer (engine, title, matches with why) and the search it is for
  Map? _ai;
  String? _aiFor;
  bool _aiBusy = false;
  /// where the phone is, for nearer results first (only once location is allowed; asked for no more than that)
  ({double lat, double lng, DateTime at})? _here;

  @override
  void initState() {
    super.initState();
    _loadMatches();
    _readPhoneBook(ask: false);
    _loadAsks();
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
    _aiTimer?.cancel();
    _q.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadMatches() async {
    final c = await PhonebookCache.load();
    if (mounted) setState(() => _matches = c);
  }

  /// Reads the phone book on the phone. [ask]: show the permission pop-up (from the "Allow contacts" card);
  /// otherwise only reads when contacts are already allowed.
  Future<void> _readPhoneBook({required bool ask}) async {
    if (!ContactSync.supported) return;
    final ok = ask
        ? await Permissions.ensure(context, Need.contacts, reason: t('To show your phone book here, with who has a WEBWEB page. It is read on your phone and not uploaded.'))
        : await Permissions.granted(Need.contacts);
    if (!mounted) return;
    setState(() => (_canRead = ok, _reading = ok));
    if (!ok) return;
    try {
      final all = await FlutterContacts.getAll(properties: {ContactProperty.phone});
      if (mounted) setState(() => (_device = all.where((c) => (c.displayName ?? '').trim().isNotEmpty && c.phones.isNotEmpty).toList(), _reading = false));
    } catch (_) {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _loadAsks() async {
    final me = context.read<AuthProvider>().profile?.uid;
    try {
      final d = await context.read<AuthProvider>().api.get('/posts', {'matched': 1, 'limit': 20}) as List;
      final list = d.map((e) => Post.fromJson(e as Map)).where((x) => x.isRequirement && !x.closed && x.authorUid != me).take(10).toList();
      if (mounted) setState(() => _asks = list);
    } catch (_) {
      if (mounted) setState(() => _asks = const []);
    }
  }

  Future<void> _refresh() => Future.wait([_loadMatches(), _readPhoneBook(ask: false), _loadAsks()]);

  void _search(String v) {
    _debounce?.cancel();
    _aiTimer?.cancel();
    // Ask AI reads the need once the member pauses (or at once on the keyboard's search key)
    if (v.trim().length >= 4) _aiTimer = Timer(const Duration(milliseconds: 1200), () => _askAi(v.trim()));
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

  /// Ask AI (POST /phonebook/ai-find): the pages that can help with what was typed, each with why.
  Future<void> _askAi(String q) async {
    _aiTimer?.cancel();
    if (q.length < 4 || (q == _aiFor && (_ai != null || _aiBusy))) return;
    setState(() => (_aiFor = q, _ai = null, _aiBusy = true));
    try {
      final here = await _position();
      if (!mounted) return;
      final r = await context.read<AuthProvider>().api.post('/phonebook/ai-find', {'q': q, if (here != null) 'lat': here.lat, if (here != null) 'lng': here.lng}) as Map;
      if (mounted && _aiFor == q) setState(() => _ai = r);
    } catch (_) {
      if (mounted && _aiFor == q) setState(() => _ai = const {'matches': []});
    } finally {
      if (mounted && _aiFor == q) setState(() => _aiBusy = false);
    }
  }

  /// The phone's position for the search (sent with it, not stored): only when location is already allowed,
  /// read again after 5 minutes. Without it the server uses the last location the app saved, or the page's area.
  Future<({double lat, double lng})?> _position() async {
    final h = _here;
    if (h != null && DateTime.now().difference(h.at) < const Duration(minutes: 5)) return (lat: h.lat, lng: h.lng);
    if (!ContactSync.supported || !await Permissions.granted(Need.location)) return null;
    try {
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 6)))
          .catchError((_) async => (await Geolocator.getLastKnownPosition())!);
      _here = (lat: p.latitude, lng: p.longitude, at: DateTime.now());
      return (lat: p.latitude, lng: p.longitude);
    } catch (_) {
      return null;
    }
  }

  /// "Use my location": asks (saying why), saves it as the last location, and searches again nearest to you.
  Future<void> _useLocation() async {
    try {
      final h = await currentLocation(context, reason: t('To show people near you first.'), source: 'ask-ai');
      _here = (lat: h.lat, lng: h.lng, at: DateTime.now());
    } on PermissionNotGiven {
      return;
    } catch (e) {
      if (mounted && '$e'.isNotEmpty) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    final q = _q.text.trim();
    _aiFor = null;
    _askAi(q);
  }

  /// Not found: the search goes to the Ask form as a new ask, for members to refer someone
  void _postAsAsk() {
    final q = _q.text.trim();
    final title = _aiFor == q ? '${_ai?['title'] ?? q}' : q;
    askPrefill.value = title.isEmpty ? q : title;
    _q.clear();
    _search('');
    FocusScope.of(context).unfocus();
    widget.onAsk?.call();
  }

  Future<void> _openCheck() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => SubPage(title: t('Phonebook'), body: const PhonebookScreen())));
    _loadMatches();
  }

  static String _memberName(Map m) => displayName('${m['userType'] ?? ''}', '${m['name'] ?? ''}', '${m['company'] ?? ''}');

  /// The phone's contacts with their pages put next to them, plus pages from the check not (or no longer) on the
  /// phone, A to Z by the name shown.
  List<_Entry> get _entries {
    final matches = _matches ?? const <Map>[];
    final byPhone = {for (final m in matches) if (m['phone'] != null) '${m['phone']}': m};
    // checks from before the number was kept: by the name it was saved as
    final bySaved = {for (final m in matches) if (m['phone'] == null && (m['saved'] ?? '') != '') '${m['saved']}': m};
    final used = <String>{};
    final out = <_Entry>[];
    for (final c in _device ?? const <Contact>[]) {
      final name = c.displayName!.trim();
      final mobiles = c.phones.map((ph) => ContactSync.mobile10(ph.number)).whereType<String>().toList();
      final phone = mobiles.isNotEmpty ? mobiles.first : c.phones.first.number;
      Map? member;
      for (final m in mobiles) {
        member ??= byPhone[m];
      }
      member ??= bySaved[name];
      if (member != null) used.add('${member['uid']}');
      out.add(_Entry(name, phone, member));
    }
    for (final m in matches) {
      if (used.add('${m['uid']}')) out.add(_Entry((m['saved'] as String?) ?? _memberName(m), m['phone'] as String?, m));
    }
    out.sort((a, b) {
      final x = a.letter == '#', y = b.letter == '#';
      return x != y ? (x ? 1 : -1) : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final directory = _directory(p, showAsks: !wide);
      if (!wide) return directory;
      // large screens: the directory, and the asks in a column beside it
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: directory),
        VerticalDivider(width: 1, color: p.border),
        SizedBox(
          width: 360,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 40), children: [
            _asksTitle(p),
            const SizedBox(height: 10),
            _postAskCard(p, vertical: true),
            for (final a in _asks ?? const <Post>[]) Padding(padding: const EdgeInsets.only(top: 10), child: _askCard(p, a, vertical: true)),
            if (_asks == null) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
          ]),
        ),
      ]);
    });
  }

  Widget _directory(Pal p, {required bool showAsks}) {
    final q = _q.text.trim().toLowerCase();
    final me = context.watch<AuthProvider>().profile;
    final all = _entries;
    final searching = q.length >= 2;

    final top = Column(key: _topKey, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Text(t('Contacts'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        if (all.isNotEmpty) Text('${all.length}', style: TextStyle(fontSize: 15, color: p.muted)),
      ]),
      const SizedBox(height: 10),
      // Ask AI: a name finds the contact; anything else is a need, and the AI finds who can help
      TextField(
        controller: _q,
        onChanged: _search,
        onSubmitted: (v) => _askAi(v.trim()),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          prefixIcon: Padding(padding: const EdgeInsets.only(left: 14, right: 8), child: _aiMark(20)),
          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          hintText: t('Ask AI: a name, or what you need'),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide(color: kGold.withValues(alpha: .75), width: 1.5)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: const BorderSide(color: kGold, width: 2)),
          suffixIcon: _q.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _q.clear();
                    _search('');
                  }),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
        ),
      ),
      if (!searching) ...[
        // my card, as at the top of a phone's contacts
        if (me != null) ...[const SizedBox(height: 14), _myCard(p, me.handle, displayName(me.userType, me.name, me.company), me.photoUrl)],
        if (showAsks) ...[
          const SizedBox(height: 18),
          _asksTitle(p),
          const SizedBox(height: 8),
          _askStrip(p),
        ],
        const SizedBox(height: 14),
        ..._prompts(p),
      ],
    ]);

    if (searching) {
      final mine = all.where((e) => '${e.name} ${e.phone ?? ''} ${e.member == null ? '' : '${e.member!['name']} ${e.member!['company']} ${e.member!['category']} ${e.member!['location']} ${(e.member!['services'] as List? ?? const []).join(' ')}'}'.toLowerCase().contains(q)).toList();
      final aiMatches = _aiFor == _q.text.trim() ? ((_ai?['matches'] as List?) ?? const []).cast<Map>() : const <Map>[];
      bool shown(Map u) => mine.any((e) => e.member?['uid'] == u['uid']) || aiMatches.any((m) => m['uid'] == u['uid']);
      final others = (_results ?? const <Map>[]).where((u) => !shown(u)).take(20).toList();
      // what the member saved a page as, when it is in their contacts
      final saved = {for (final e in all) if (e.member != null) '${e.member!['uid']}': e.name};
      return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 120), children: [
        top,
        if (mine.isNotEmpty) ...[_label(p, t('In your contacts')), for (final e in mine.take(30)) _row(p, e)],
        ..._aiSection(p, aiMatches, saved),
        if (others.isNotEmpty) ...[_label(p, t('On WEBWEB')), for (final u in others) _row(p, _Entry(_memberName(u), null, u))],
        const SizedBox(height: 18),
        _postAsAskCard(p),
        Center(
          child: TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FindScreen(standalone: true, initialQuery: _q.text.trim()))),
            child: Text(t('Search nearby')),
          ),
        ),
      ]);
    }

    // A to Z: a letter over each group, every line the same height so the index can jump straight to a letter
    final items = <Object>[];
    final at = <String, int>{};
    for (final e in all) {
      if (items.isEmpty || (items.last is _Entry && (items.last as _Entry).letter != e.letter)) {
        at[e.letter] = items.length;
        items.add(e.letter);
      }
      items.add(e);
    }
    double offsetOf(int index) {
      var y = 0.0;
      for (var k = 0; k < index; k++) {
        y += items[k] is String ? _headH : _rowH;
      }
      return y;
    }

    final list = RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(controller: _scroll, slivers: [
        SliverPadding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), sliver: SliverToBoxAdapter(child: top)),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 28, 120),
          sliver: SliverVariedExtentList.builder(
            itemCount: items.length,
            itemExtentBuilder: (i, _) => i >= items.length ? null : (items[i] is String ? _headH : _rowH),
            itemBuilder: (_, i) {
              final it = items[i];
              return it is String
                  ? Container(alignment: Alignment.bottomLeft, padding: const EdgeInsets.only(bottom: 4), child: Text(it, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kStar)))
                  : _row(p, it as _Entry);
            },
          ),
        ),
      ]),
    );
    if (at.length < 2) return list;
    // the letter index down the right edge: tap or slide to jump
    void jump(Offset local, double height) {
      final letters = at.keys.toList();
      final k = (local.dy / height * letters.length).floor().clamp(0, letters.length - 1);
      final l = letters[k];
      if (l == _scrubbing) return;
      setState(() => _scrubbing = l);
      final topH = (_topKey.currentContext?.findRenderObject() as RenderBox?)?.size.height ?? 0;
      _scroll.jumpTo((12 + topH + offsetOf(at[l]!)).clamp(0.0, _scroll.position.maxScrollExtent));
    }

    return Stack(children: [
      list,
      // beside the list only: it starts under my card and the asks, and moves up with them as they scroll away
      AnimatedBuilder(
        animation: _scroll,
        builder: (context, child) {
          final topH = (_topKey.currentContext?.findRenderObject() as RenderBox?)?.size.height ?? 0;
          final off = _scroll.hasClients ? _scroll.offset : 0.0;
          return Positioned(right: 2, top: (12 + topH - off).clamp(8.0, double.infinity), bottom: 90, child: child!);
        },
        child: Center(
          child: LayoutBuilder(builder: (context, c) {
            final h = (at.length * 18.0).clamp(0.0, c.maxHeight);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => jump(d.localPosition, h),
              onVerticalDragUpdate: (d) => jump(d.localPosition, h),
              onTapUp: (_) => setState(() => _scrubbing = null),
              onVerticalDragEnd: (_) => setState(() => _scrubbing = null),
              child: SizedBox(
                width: 22,
                height: h,
                child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  for (final l in at.keys)
                    Text(l, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: l == _scrubbing ? kStar : p.muted)),
                ]),
              ),
            );
          }),
        ),
      ),
      if (_scrubbing != null)
        Center(
          child: Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(20)),
            child: Text(_scrubbing!, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: kInk)),
          ),
        ),
    ]);
  }

  /// What is missing before the directory is whole: contacts not allowed yet, or never matched to pages.
  List<Widget> _prompts(Pal p) => [
        if (ContactSync.supported && !_canRead)
          _prompt(p, Icons.contacts_rounded, t('Allow contacts'), t('See your phone book here, with who has a WEBWEB page. It is read on your phone and not uploaded.'), () => _readPhoneBook(ask: true)),
        if (_matches == null && _canRead) ...[
          _prompt(p, Icons.verified_rounded, t('See who in your contacts has a page'), t('What they do, where they are and their reviews. Numbers are checked and not kept.'), _openCheck),
        ],
        if (_matches != null && ContactSync.supported)
          Row(children: [
            Expanded(child: Text(t('{n} contacts on WEBWEB', {'n': _matches!.length}), style: TextStyle(fontSize: 13, color: p.muted))),
            TextButton(onPressed: _openCheck, child: Text(t('Check again'))),
          ]),
        if (_reading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
        // the web has no phone book: the pages from the app's last check, if any
        if (!ContactSync.supported && (_matches?.isEmpty ?? true))
          Text(t('Your phone book shows here in the WEBWEB app on your phone.'), style: TextStyle(color: p.muted)),
      ];

  Widget _prompt(Pal p, IconData icon, String title, String body, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: kStar.withValues(alpha: p.dark ? .12 : .1), borderRadius: BorderRadius.circular(18), border: Border.all(color: kStar.withValues(alpha: .6))),
          child: Row(children: [
            Container(width: 46, height: 46, decoration: const BoxDecoration(gradient: kGoldGradient, shape: BoxShape.circle), child: Icon(icon, color: kInk)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(body, style: TextStyle(fontSize: 13, color: p.muted, height: 1.35)),
              ]),
            ),
          ]),
        ),
      );

  Widget _label(Pal p, String s) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 2),
        child: Text(s.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.25, color: p.muted)),
      );

  /// the gold sparkle that marks Ask AI
  Widget _aiMark(double size) => ShaderMask(
        shaderCallback: (r) => kGoldGradient.createShader(r),
        child: Icon(Icons.auto_awesome_rounded, size: size, color: Colors.white),
      );

  /// What Ask AI found for the search: looking, the pages with why each fits, or that none fits yet.
  List<Widget> _aiSection(Pal p, List<Map> matches, Map<String, String> saved) {
    final q = _q.text.trim();
    if (q.length < 4) return const [];
    // nearest first: from the place named, from where you are, or a tap to allow location
    final near = _aiFor == q ? '${_ai?['near'] ?? ''}' : null;
    final head = Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Row(children: [
        _aiMark(15),
        const SizedBox(width: 6),
        Expanded(child: Text(t('Ask AI found').toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.25, color: p.muted))),
        if (near != null && !_aiBusy)
          near.isEmpty && ContactSync.supported
              ? TextButton.icon(
                  onPressed: _useLocation,
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
                  icon: const Icon(Icons.my_location_rounded, size: 16),
                  label: Text(t('Use my location'), style: const TextStyle(fontSize: 12.5)),
                )
              : near.isEmpty
                  ? const SizedBox()
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.place_rounded, size: 14, color: p.muted),
                      const SizedBox(width: 2),
                      Text(near == 'you' ? t('Nearest to you') : t('Nearest to {place}', {'place': near}), style: TextStyle(fontSize: 12, color: p.muted)),
                    ]),
      ]),
    );
    if (_aiBusy || _aiFor != q) {
      return [
        head,
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kGold)),
            const SizedBox(width: 12),
            Expanded(child: Text(_aiFor == q ? t('Looking for who can help…') : t('Press search to ask AI who can help'), style: TextStyle(color: p.muted))),
          ]),
        ),
      ];
    }
    if (matches.isEmpty) return [head, Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(t('No page fits this yet.'), style: TextStyle(color: p.muted)))];
    return [
      head,
      for (final m in matches) _row(p, _Entry(saved['${m['uid']}'] ?? _memberName(m), null, m), why: '${m['why'] ?? ''}'),
    ];
  }

  /// Still not the one: post the search as an ask, and members refer someone they know.
  Widget _postAsAskCard(Pal p) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: kGold.withValues(alpha: p.dark ? .1 : .08), borderRadius: BorderRadius.circular(18), border: Border.all(color: kGold.withValues(alpha: .6))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.campaign_rounded, color: kStar, size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text(t('Not the right one? Post it as an ask'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 4),
          Text(t('Members near you who know someone will refer the right contact to you.'), style: TextStyle(fontSize: 13, height: 1.35, color: p.muted)),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _postAsAsk,
            icon: const Icon(Icons.send_rounded, size: 18),
            label: Text(t('Post as an ask'), style: const TextStyle(fontWeight: FontWeight.w700)),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44), backgroundColor: kStar, foregroundColor: kInk, shape: const StadiumBorder()),
          ),
        ]),
      );

  Widget _row(Pal p, _Entry e, {String? why}) {
    final m = e.member;
    final who = m == null ? '' : _memberName(m);
    final d = (m?['distanceM'] as num?)?.toDouble();
    final away = d == null ? '' : (d < 1000 ? t('under 1 km') : t('{n} km', {'n': (d / 1000).toStringAsFixed(d < 10000 ? 1 : 0)}));
    final sub = m == null
        ? (e.phone ?? '')
        : [if (who != e.name) who, '${m['category'] ?? ''}', '${m['location'] ?? ''}', away].where((s) => s.isNotEmpty).join(' · ');
    final reviews = (m?['reviews'] as num?)?.toInt() ?? 0;
    final rating = (m?['rating'] as num?)?.toDouble() ?? 0;
    final level = (m?['verificationLevel'] as num?)?.toInt() ?? 0;
    return InkWell(
      onTap: () => m != null ? Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: '${m['handle']}'))) : _contactSheet(e),
      child: Container(
        constraints: BoxConstraints(minHeight: _rowH, maxHeight: why == null || why.isEmpty ? _rowH : double.infinity),
        padding: EdgeInsets.symmetric(vertical: why == null || why.isEmpty ? 0 : 8),
        child: Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            Avatar(name: e.name, photoUrl: (m?['photoURL'] ?? m?['photoUrl']) as String?, size: 44),
            // a WEBWEB page: the gold W on the picture
            if (m != null)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(gradient: kGoldGradient, shape: BoxShape.circle, border: Border.all(color: p.canvas, width: 2)),
                  child: const Text('W', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: kInk, height: 1)),
                ),
              ),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: m != null ? FontWeight.w700 : FontWeight.w500))),
                if (level > 0) ...[const SizedBox(width: 4), VerifiedBadge(level: level, size: 14)],
              ]),
              if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted)),
              if (why != null && why.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(children: [
                    _aiMark(12),
                    const SizedBox(width: 4),
                    Expanded(child: Text(why, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.tagText))),
                  ]),
                ),
            ]),
          ),
          if (reviews > 0)
            Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Stars(value: rating, size: 11),
              Text('${rating.toStringAsFixed(1)} · $reviews', style: TextStyle(fontSize: 11, color: p.muted)),
            ]),
        ]),
      ),
    );
  }

  /// A contact without a page: call, WhatsApp, or invite them to make one.
  Future<void> _contactSheet(_Entry e) async {
    final p = Pal.of(context);
    final ten = e.phone == null ? null : ContactSync.mobile10(e.phone!);
    final invite = '${t('I have a free business page on WEBWEB, the AI Phonebook. Make yours so customers can find and review you:')} https://webweb.ai';
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.canvas,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: Avatar(name: e.name, size: 44),
              title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(e.phone ?? '', style: TextStyle(color: p.muted)),
            ),
            const Divider(height: 8),
            if (e.phone != null)
              ListTile(
                leading: const Icon(Icons.call_rounded, color: Color(0xFF1E9E5A)),
                title: Text(t('Call')),
                onTap: () {
                  Navigator.pop(ctx);
                  _open('tel:${e.phone!.replaceAll(RegExp(r'[^\d+]'), '')}');
                },
              ),
            if (ten != null) ...[
              ListTile(
                leading: const Icon(Icons.chat_rounded, color: Color(0xFF25D366)),
                title: const Text('WhatsApp'),
                onTap: () {
                  Navigator.pop(ctx);
                  _open('https://wa.me/91$ten');
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_add_alt_1_rounded, color: kStar),
                title: Text(t('Invite to the phonebook')),
                onTap: () {
                  Navigator.pop(ctx);
                  _open('https://wa.me/91$ten?text=${Uri.encodeComponent(invite)}');
                },
              ),
            ],
          ]),
        ),
      ),
    );
  }

  /// the phone's dialer or WhatsApp, straight away (these are the member's own contacts, not links from others)
  static void _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);

  // ---------- asks ----------

  Widget _asksTitle(Pal p) => Row(children: [
        const Icon(Icons.campaign_rounded, size: 20, color: kStar),
        const SizedBox(width: 6),
        Expanded(child: Text(t('Asks near you'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
        if (widget.onSeeAsks != null) TextButton(onPressed: widget.onSeeAsks, child: Text(t('See all'))),
      ]);

  /// the open asks around me, one swipe each way, after a card to post my own
  Widget _askStrip(Pal p) => SizedBox(
        height: 150,
        child: ListView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          children: [
            _postAskCard(p),
            for (final a in _asks ?? const <Post>[]) Padding(padding: const EdgeInsets.only(left: 10), child: _askCard(p, a)),
            if (_asks == null) const SizedBox(width: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
          ],
        ),
      );

  Widget _postAskCard(Pal p, {bool vertical = false}) => InkWell(
        onTap: widget.onAsk,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: vertical ? null : 150,
          height: vertical ? 96 : 150,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(18)),
          child: Flex(direction: vertical ? Axis.horizontal : Axis.vertical, crossAxisAlignment: vertical ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .55), shape: BoxShape.circle), child: const Icon(Icons.add_rounded, color: kInk, size: 26)),
            if (vertical) const SizedBox(width: 12) else const Spacer(),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(t('Post an ask'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kInk)),
                Text(t('Businesses near you reply'), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, height: 1.2, color: kInk.withValues(alpha: .75))),
              ]),
            ),
          ]),
        ),
      );

  Widget _askCard(Pal p, Post a, {bool vertical = false}) {
    final type = askTypeDef(askTypeOf(a)) ?? kAskTypes.last;
    final tint = kCardColors[cardColorOf(a)]!;
    final meta = [a.locationPref ?? '', askTimeLeft(a) ?? ''].where((s) => s.isNotEmpty).join(' · ');
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailScreen(postId: a.id))),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: vertical ? null : 236,
        height: vertical ? null : 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tint.withValues(alpha: p.dark ? .28 : .22), tint.withValues(alpha: p.dark ? .1 : .06)]),
          border: Border.all(color: tint.withValues(alpha: .45)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('${type.emoji} ${askLabel(a).toUpperCase()}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.muted)),
          const SizedBox(height: 6),
          Text(a.title ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, height: 1.25)),
          if (vertical) const SizedBox(height: 10) else const Spacer(),
          Row(children: [
            Avatar(name: a.shownName, photoUrl: a.authorPhotoUrl, size: 22),
            const SizedBox(width: 6),
            Expanded(child: Text(a.shownName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
          ]),
          if (meta.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.muted))),
        ]),
      ),
    );
  }

  Widget _myCard(Pal p, String handle, String name, String? photo) {
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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';

import '../approx_distance.dart';
import '../ask_types.dart';
import '../auth_provider.dart';
import '../card_colors.dart';
import '../contact_sync.dart';
import '../i18n.dart';
import '../links.dart';
import '../location.dart' show PermissionNotGiven, currentLocation;
import '../models.dart';
import '../permissions.dart';
import '../places.dart' show placeAt;
import '../theme.dart';
import '../widgets.dart';
import '../widgets/area_map.dart' show askTimeLeft;
import '../widgets/city_picker.dart';
import '../widgets/reviews_card.dart';
import '../widgets/whatsapp_icon.dart';
import 'connect.dart' show UpdatesBar;
import '../widgets/tour.dart' show Tours;
import 'find.dart';
import 'post_detail.dart';
import 'profile.dart';
import 'service_page.dart';
import 'service_contacts_sheet.dart' show autoServiceContacts;
import 'ask.dart' show SearchAskForm;

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
      onTap: () => Navigator.push(context, WideRoute(builder: (_) => ProfileScreen(handle: '${m['handle']}'))),
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
          Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.chevron_right_rounded, size: 24, color: p.muted)),
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
/// One service contact or Ask AI page in the merged results: its row and what the sort options order by.
class _Hit {
  _Hit(this.d, this.dist, this.shared, this.rating, this.reviews, this.w);
  final double d; // metres from the server, for the recommended order
  final double dist; // metres, server's or the offline estimate (infinity when unknown)
  final int shared;
  final double rating;
  final int reviews;
  final Widget w;
}

class _Entry {
  final String name;
  final String? phone;
  final Map? member;
  /// the phone's own contact, with everything saved on it (numbers, emails, company, address, photo)
  final Contact? contact;
  const _Entry(this.name, this.phone, this.member, [this.contact]);

  /// the company and job title saved on the contact
  String get org => (contact?.organizations ?? const <Organization>[])
      .map((o) => [o.name, o.jobTitle].whereType<String>().where((s) => s.trim().isNotEmpty).join(' · '))
      .where((s) => s.isNotEmpty)
      .join(', ');

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
/// - Tapping the search turns everything under it into a new ask whose title is the search: what was found shows
///   first, as it is typed, and if no one fits the rest of the form posts it for members to refer someone.
class PhonebookHome extends StatefulWidget {
  /// open the ask composer, and the feed of asks (the Updates tab)
  final VoidCallback? onAsk, onSeeAsks;
  /// an ask was posted from the search
  final VoidCallback? onPosted;
  /// the search page opened or closed
  final ValueChanged<bool>? onSearching;
  /// the Directory tab is on screen (back closes the search only then)
  final bool active;
  const PhonebookHome({super.key, this.onAsk, this.onSeeAsks, this.onPosted, this.onSearching, this.active = true});
  @override
  State<PhonebookHome> createState() => _PhonebookHomeState();
}

class _PhonebookHomeState extends State<PhonebookHome> {
  static const _headH = 30.0, _rowH = 64.0;
  final _q = TextEditingController();
  final _qFocus = FocusNode();
  /// the search field moves between the directory and the search page: one field, so it keeps the keyboard
  final _searchKey = GlobalKey();
  /// the search page is open (from the first tap on the search until Cancel, back or the ask is posted)
  bool _searching = false;
  final _scroll = ScrollController();
  final _topKey = GlobalKey();
  List<Map>? _matches;
  /// the phone's own contacts: null until read (not allowed yet, or not a phone)
  List<Contact>? _device;
  bool _canRead = false, _reading = false;
  List<Map>? _results;
  /// service providers other members saved and WEBWEB approved (plumber, carpenter...), after my own contacts
  List<Map> _service = const [];
  List<Post>? _asks;
  /// every sub-category (service-contact category) with its icon, for the tiles under the search
  List<Map> _cats = const [];
  /// the last searches, on this phone only
  List<String> _recent = const [];
  bool _allCats = false;
  Map? _mine;
  Timer? _debounce, _aiTimer;
  String? _scrubbing;
  /// Ask AI: the answer (engine, title, matches with why) and the search it is for
  Map? _ai;
  String? _aiFor;
  bool _aiBusy = false;
  // how the results are ordered: rec (Ask AI's order), near, shared, rated
  String _sort = 'rec';
  /// where the phone is, for nearer results first (only once location is allowed; asked for no more than that)
  ({double lat, double lng, DateTime at})? _here;
  /// where to look: '' is the current location; or any town in India picked beside the search (with its centre when it is a new town)
  String _place = '';
  ({double lat, double lng})? _placeAt;
  /// the city the phone is in (when location is already allowed): shown in the dropdown in place of "Current location"
  String? _hereCity;

  /// where results are measured from: the point or town picked, else where the phone is or was last
  ({double lat, double lng})? get _base => ApproxDistance.base(at: _placeAt, place: _place, here: _here == null ? null : (lat: _here!.lat, lng: _here!.lng));

  Future<void> _detectCity() async {
    final h = await _position();
    final city = h == null ? null : placeAt(h.lat, h.lng)?.name;
    if (mounted && city != _hereCity) setState(() => _hereCity = city);
  }

  /// prompts a member could type, with their town when it is known
  List<String> get _examples {
    final city = (_place.isNotEmpty ? _place : _hereCity)?.trim();
    final c = city != null && city.isNotEmpty ? city : null;
    return [
      t('plumbers around me'),
      c != null ? t('plumbers in {city}', {'city': c}) : t('electrician near me'),
      t('internet service near me'),
      c != null ? t('a good CA near {city}', {'city': c}) : t('a good CA near me'),
      t('who can repair my AC?'),
    ];
  }

  // the examples typed out one after another in the empty box
  Timer? _typeTimer;
  int _exI = 0, _exN = 0, _exDir = 1;
  String _typed = '';

  void _onSearchFocus() {
    if (mounted) setState(() {});
  }

  void _typeStep() {
    if (!mounted) return;
    final list = _examples;
    if (_qFocus.hasFocus || _q.text.isNotEmpty) {
      _typeTimer = Timer(const Duration(milliseconds: 600), _typeStep);
      if (_typed.isNotEmpty) setState(() => _typed = '');
      return;
    }
    final w = list[_exI % list.length];
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      setState(() => _typed = w);
      _exI++;
      _typeTimer = Timer(const Duration(milliseconds: 2600), _typeStep);
      return;
    }
    _exN += _exDir;
    var wait = _exDir > 0 ? 55 : 25;
    if (_exDir > 0 && _exN >= w.length) {
      _exN = w.length;
      _exDir = -1;
      wait = 1700;
    } else if (_exDir < 0 && _exN <= 0) {
      _exN = 0;
      _exDir = 1;
      _exI++;
      wait = 350;
    }
    setState(() => _typed = w.substring(0, _exN.clamp(0, w.length)));
    _typeTimer = Timer(Duration(milliseconds: wait), _typeStep);
  }

  /// the island's Speak button: clear what is typed, then the microphone listens
  void _onSpeak() {
    if (!mounted) return;
    final had = _q.text.isNotEmpty;
    if (had) {
      _q.clear();
      _search('');
    }
    Future.delayed(Duration(milliseconds: had ? 150 : 0), () => directoryVoice.value++);
  }

  void _onFocusRequest() {
    if (mounted) WidgetsBinding.instance.addPostFrameCallback((_) => _qFocus.requestFocus());
  }

  /// a search sent from the right column of wide screens (and where to look)
  void _onRequest() {
    final r = directoryRequest.value;
    if (r == null || !mounted) return;
    setState(() {
      _place = r.place;
      _placeAt = r.at;
      _q.text = r.q;
      _results = null;
      _aiFor = null;
      _ai = null;
    });
    _q.selection = TextSelection.collapsed(offset: _q.text.length);
    if (r.q.trim().isNotEmpty) {
      _search(r.q);
      if (r.q.trim().length >= 4) _askAi(r.q.trim());
    }
  }

  @override
  void initState() {
    super.initState();
    directoryRequest.addListener(_onRequest);
    directoryFocus.addListener(_onFocusRequest);
    directorySpeak.addListener(_onSpeak);
    _qFocus.addListener(_onSearchFocus);
    _typeTimer = Timer(const Duration(milliseconds: 800), _typeStep);
    ApproxDistance.init().then((_) => mounted ? setState(() {}) : null);
    _loadMatches();
    _readPhoneBook(ask: false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _firstAsk());
    _detectCity();
    _loadAsks();
    _loadCats();
    SharedPreferences.getInstance().then((sp) {
      if (mounted) setState(() => _recent = (sp.getStringList('webweb_recent_finds') ?? const []).take(6).toList());
    });
    final me = context.read<AuthProvider>().profile;
    if (me != null) {
      context.read<AuthProvider>().api.get('/users/${me.uid}/reviews', {'limit': '1'}).then((d) {
        if (mounted) setState(() => _mine = d as Map);
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    directoryRequest.removeListener(_onRequest);
    directoryFocus.removeListener(_onFocusRequest);
    directorySpeak.removeListener(_onSpeak);
    directoryBusy.value = false;
    _debounce?.cancel();
    _aiTimer?.cancel();
    _typeTimer?.cancel();
    _q.dispose();
    _qFocus.removeListener(_onSearchFocus);
    _qFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadMatches() async {
    final c = await PhonebookCache.load();
    if (mounted) setState(() => _matches = c);
  }

  static const _kAskedContacts = 'pb_contacts_asked';

  /// The first time the app opens on a phone: ask for contacts once, saying why, so the directory is the phone book
  /// straight away. After that only the "Allow contacts" card asks.
  Future<void> _firstAsk() async {
    if (!ContactSync.supported || await Permissions.granted(Need.contacts)) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kAskedContacts) == true || !mounted) return;
    await prefs.setBool(_kAskedContacts, true);
    await _readPhoneBook(ask: true);
  }

  /// Reads the phone book on the phone, with each contact's numbers, emails, company, address and photo.
  /// [ask]: show the permission pop-up (first open, or the "Allow contacts" card); otherwise only reads when contacts
  /// are already allowed.
  Future<void> _readPhoneBook({required bool ask}) async {
    if (!ContactSync.supported) return;
    final ok = ask
        ? await Permissions.ensure(context, Need.contacts, reason: t('To show your phone book here, with who has a WEBWEB page. It is read on your phone and not uploaded.'))
        : await Permissions.granted(Need.contacts);
    if (!mounted) return;
    setState(() => (_canRead = ok, _reading = ok));
    if (!ok) return;
    try {
      final all = await FlutterContacts.getAll(properties: {ContactProperty.phone, ContactProperty.email, ContactProperty.organization, ContactProperty.address, ContactProperty.photoThumbnail});
      if (mounted) setState(() => (_device = all.where((c) => (c.displayName ?? '').trim().isNotEmpty && c.phones.isNotEmpty).toList(), _reading = false));
    } catch (_) {
      if (mounted) setState(() => _reading = false);
    }
    if (ask && mounted) _serviceContacts();
  }

  /// Contacts were just allowed: service contacts (only the contacts saved with a service word, shared with the
  /// member's say-so) look at once if they are on, or are offered once, here, instead of at the third open.
  Future<void> _serviceContacts() async => autoServiceContacts(context);

  Future<void> _loadCats() async {
    try {
      final d = await context.read<AuthProvider>().api.get('/service-contacts/categories') as Map;
      if (mounted) setState(() => _cats = (d['categories'] as List).cast<Map>());
    } catch (_) {}
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
    // the directory turns into the search page when the typing starts (not when the box is only tapped), and back when
    // the box is emptied; the box keeps its focus across the change
    final typing = v.trim().isNotEmpty;
    if (typing != _searching) {
      setState(() => _searching = typing);
      widget.onSearching?.call(typing);
    }
    _debounce?.cancel();
    _aiTimer?.cancel();
    // Ask AI reads the need once the member pauses (or at once on the keyboard's search key)
    if (v.trim().length >= 4) _aiTimer = Timer(const Duration(milliseconds: 1200), () => _askAi(v.trim()));
    setState(() {});
    if (v.trim().length < 2) {
      return setState(() {
        _results = null;
        _service = const [];
      });
    }
    final api = context.read<AuthProvider>().api;
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final d = await api.get('/users/search', {'q': v.trim(), if (_place.isNotEmpty) 'place': _place});
        if (mounted) setState(() => _results = (d as List).cast<Map>());
      } catch (_) {
        if (mounted) setState(() => _results = const []);
      }
      try {
        final d = await api.get('/service-contacts/search', {'q': v.trim(), if (_place.isNotEmpty) 'place': _place, if (_placeAt != null) ...{'lat': '${_placeAt!.lat}', 'lng': '${_placeAt!.lng}'}});
        if (mounted && _q.text.trim() == v.trim()) setState(() => _service = ((d as Map)['contacts'] as List? ?? const []).cast<Map>());
      } catch (_) {
        if (mounted) setState(() => _service = const []);
      }
      _matchTyped(v.trim());
    });
  }

  /// A contact found by the search whose number has not been checked yet: ask which of the numbers are on WEBWEB, so
  /// the contact and its page show as one line (POST /phonebook/match, numbers not kept).
  Future<void> _matchTyped(String q) async {
    final ql = q.toLowerCase();
    final known = {for (final m in _matches ?? const <Map>[]) '${m['phone']}'};
    final phones = <String>{};
    for (final e in _entries) {
      if (e.member != null || e.contact == null || !'${e.name} ${e.org}'.toLowerCase().contains(ql)) continue;
      for (final ph in e.contact!.phones) {
        final m = ContactSync.mobile10(ph.number);
        if (m != null && !known.contains(m)) phones.add(m);
      }
      if (phones.length >= 40) break;
    }
    if (phones.isEmpty) return;
    try {
      final r = await context.read<AuthProvider>().api.post('/phonebook/match', {'phones': phones.toList()}) as Map;
      final found = (r['matches'] as List).cast<Map>();
      if (!mounted || found.isEmpty) return;
      final have = {for (final m in _matches ?? const <Map>[]) '${m['uid']}'};
      setState(() => _matches = [...?_matches, for (final m in found) if (have.add('${m['uid']}')) m]);
    } catch (_) {}
  }

  /// Ask AI (POST /phonebook/ai-find): the pages that can help with what was typed, each with why.
  Future<void> _remember(String q) async {
    final next = [q, ..._recent.where((x) => x.toLowerCase() != q.toLowerCase())].take(6).toList();
    if (mounted) setState(() => _recent = next);
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList('webweb_recent_finds', next);
  }

  Future<void> _clearRecent() async {
    setState(() => _recent = const []);
    final sp = await SharedPreferences.getInstance();
    await sp.remove('webweb_recent_finds');
  }

  Future<void> _askAi(String q) async {
    _aiTimer?.cancel();
    if (q.length < 4 || (q == _aiFor && (_ai != null || _aiBusy))) return;
    _remember(q);
    setState(() => (_aiFor = q, _ai = null, _aiBusy = true));
    try {
      // a picked town (with its centre when it is new), else the phone's position now
      final here = _place.isNotEmpty ? _placeAt : await _position();
      if (!mounted) return;
      final r = await context.read<AuthProvider>().api.post('/phonebook/ai-find', {'q': q, if (_place.isNotEmpty) 'place': _place, if (here != null) 'lat': here.lat, if (here != null) 'lng': here.lng}) as Map;
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
      ApproxDistance.rememberHere(p.latitude, p.longitude);
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
      ApproxDistance.rememberHere(h.lat, h.lng);
    } on PermissionNotGiven {
      return;
    } catch (e) {
      if (mounted && '$e'.isNotEmpty) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    _detectCity();
    final q = _q.text.trim();
    _aiFor = null;
    _askAi(q);
  }

  /// Cancel, back, or the ask was posted: the directory again
  void _closeSearch() {
    _q.clear();
    _search('');
    _qFocus.unfocus();
    setState(() {
      _searching = false;
      _askOpen = false;
    });
    widget.onSearching?.call(false);
  }

  Future<void> _openCheck() async {
    await Navigator.push(context, WideRoute(builder: (_) => SubPage(title: t('Phonebook'), body: const PhonebookScreen())));
    _loadMatches();
  }

  static String _memberName(Map m) => displayName('${m['userType'] ?? ''}', '${m['name'] ?? ''}', '${m['company'] ?? ''}');

  /// [_build], kept until the phone book or the pages change (a phone book can have thousands of contacts, and the
  /// letter index rebuilds the page on every move of the finger)
  List<_Entry> get _entries {
    final key = (_device, _matches);
    if (_entriesKey != key) {
      _entriesKey = key;
      _entriesList = _build();
    }
    return _entriesList;
  }

  (List<Contact>?, List<Map>?)? _entriesKey;
  List<_Entry> _entriesList = const [];

  /// The phone's contacts with their pages put next to them, plus pages from the check not (or no longer) on the
  /// phone, A to Z by the name shown.
  List<_Entry> _build() {
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
      out.add(_Entry(name, phone, member, c));
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
    // a search is running: the ring round the island's button turns
    final busy = _aiBusy || (_searching && _results == null);
    WidgetsBinding.instance.addPostFrameCallback((_) => directoryBusy.value = busy);
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final directory = PopScope(
        canPop: !(_searching && widget.active),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _searching) _closeSearch();
        },
        child: KeyedSubtree(key: ValueKey(_searching), child: _searching ? _searchPage(p) : _directory(p, showAsks: !wide)),
      );
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
    final me = context.watch<AuthProvider>().profile;
    final all = _entries;

    final top = Column(key: _topKey, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // the updates (people, leads, Today, new businesses) come first, above the search
      _fold(!_searching, Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Column(key: Tours.key('updates'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // a small gold title with a fading rule, so the circles read as their own strip without a box
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: kGold, boxShadow: [BoxShadow(color: kGold.withValues(alpha: .25), spreadRadius: 3)]),
            ),
            const SizedBox(width: 8),
            Text(t('Updates').toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.6, color: p.dark ? const Color(0xFFFFD84A) : const Color(0xFF7A5A00))),
            const SizedBox(width: 10),
            Expanded(child: Container(height: 1, decoration: BoxDecoration(gradient: LinearGradient(colors: [kGold.withValues(alpha: .6), kGold.withValues(alpha: 0)])))),
          ]),
        ),
        const UpdatesBar(),
      ]),
      const SizedBox(height: 12),
      ])),
      // the page the app opens on: a greeting, what to ask, the search with where to look inside it, and things to try
      AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        padding: EdgeInsets.fromLTRB(16, _searching ? 10 : 18, 16, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: p.dark ? kGold.withValues(alpha: .25) : const Color(0x99F0D77A)),
          boxShadow: p.dark ? null : const [BoxShadow(color: Color(0x40B48200), blurRadius: 30, offset: Offset(0, 10), spreadRadius: -14)],
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: p.dark ? [kGold.withValues(alpha: .22), kGold.withValues(alpha: .04)] : const [Color(0xFFFFF0B0), Color(0xFFFFF8DC), Color(0xFFFFFDF3)],
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _fold(!_searching, Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (me != null && me.name.trim().isNotEmpty)
            Text('${t('Hi {name}', {'name': me.name.trim().split(' ').first})} 👋', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.dark ? const Color(0xFFFFD84A) : const Color(0xFF7A5A00))),
          const SizedBox(height: 2),
          Text(t('What are you looking for?'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.1)),
          const SizedBox(height: 6),
          Text(t('Search your phonebook, trusted service contacts and businesses near you.'), style: TextStyle(fontSize: 14, height: 1.35, color: p.text.withValues(alpha: .65))),
          const SizedBox(height: 16),
          ])),
          _searchField(),
          _fold(!_searching, Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 16),
          Text(t('Popular searches').toUpperCase(), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .6, color: p.text.withValues(alpha: .6))),
          const SizedBox(height: 6),
          _bleed(
            38,
            ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _trades.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => InkWell(
                borderRadius: BorderRadius.circular(30),
                onTap: () => _pick(_trades[i]),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.only(left: 10, right: 14),
                  decoration: BoxDecoration(color: p.card.withValues(alpha: .9), border: Border.all(color: kGold.withValues(alpha: .5)), borderRadius: BorderRadius.circular(30)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_tradeEmoji[_trades[i]] ?? '', style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Text(t(_trades[i]), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),
          ),
          if (_recent.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Text(t('Recent searches').toUpperCase(), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .6, color: p.text.withValues(alpha: .6)))),
              GestureDetector(onTap: _clearRecent, behavior: HitTestBehavior.opaque, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), child: Text(t('Clear'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.link)))),
            ]),
            const SizedBox(height: 6),
            _bleed(
              34,
              ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: _recent.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => InkWell(
                  borderRadius: BorderRadius.circular(30),
                  onTap: () => _pick(_recent[i]),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: p.card.withValues(alpha: .7), borderRadius: BorderRadius.circular(30)),
                    child: Text('↺  ${_recent[i]}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.text.withValues(alpha: .8))),
                  ),
                ),
              ),
            ),
          ],
          ])),
        ]),
      ),
      _fold(!_searching, _categoryTiles(p)),
      // two more ways in under the categories: see which of your contacts have a page, and look round the area
      _fold(!_searching, Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _shortcut(p, Icons.contacts_outlined, 'Check my contacts', _openCheck)),
          const SizedBox(width: 12),
          Expanded(child: _shortcut(p, Icons.near_me_outlined, 'Search nearby', () => Navigator.push(context, WideRoute(builder: (_) => SubPage(title: t('Nearby'), body: const FindScreen()))))),
        ]),
      ])),
      ...[
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
    // where each letter starts, worked out once
    final offsets = <String, double>{};
    var y = 0.0;
    for (final it in items) {
      if (it is String) offsets[it] = y;
      y += it is String ? _headH : _rowH;
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
      _scroll.jumpTo((12 + topH + offsets[l]!).clamp(0.0, _scroll.position.maxScrollExtent));
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

  /// Ask AI: a name finds the contact; anything else is a need, and the AI finds who can help. The main thing of the
  /// app, so it is the one element that moves: a gold light runs round its border, with the AI badge at its start.
  /// The search; where to look is inside its box, under the text.
  Widget _searchField() => _searchBox();

  /// A tap on a category or a trade: that word is searched.
  void _pick(String word) {
    _q.text = word;
    _q.selection = TextSelection.collapsed(offset: _q.text.length);
    _search(word);
    _qFocus.requestFocus();
  }

  static const _tradeEmoji = {'Plumber': '🔧', 'Electrician': '⚡', 'Printer': '🖨️', 'Carpenter': '🪚', 'Tutor': '📚', 'Caterer': '🍽️', 'Transport': '🚚', 'Chartered accountant': '🧾', 'Mobile repair': '📱', 'Tailor': '🧵'};
  static const _trades = ['Plumber', 'Electrician', 'Printer', 'Carpenter', 'Tutor', 'Caterer', 'Transport', 'Chartered accountant', 'Mobile repair', 'Tailor'];

  /// A category's icon and name; a tap searches it.
  Widget _catTile(Map c, {double w = 78}) {
    final tag = '${c['tag']}';
    final p = Pal.of(context);
    // every tile is the same card: the icon in a round on top, the name in a fixed two-line box under it, so rows line up whatever the name
    return Opacity(
      opacity: ((c['n'] as num?) ?? 1) == 0 ? .55 : 1,
      child: SizedBox(
        width: w,
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Material(
            color: kGold.withValues(alpha: p.dark ? .1 : .08),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: kGold.withValues(alpha: .25))),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _pick(tag),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p.card,
                      border: Border.all(color: kGold.withValues(alpha: .4)),
                      boxShadow: const [BoxShadow(color: Color(0x59785A00), blurRadius: 6, spreadRadius: -2, offset: Offset(0, 2))],
                    ),
                    child: Text('${c['emoji'] ?? '✨'}', style: const TextStyle(fontSize: 24, height: 1)),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 28,
                    child: Text(t(tag), maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.15)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Every sub-category of the business categories as icon tiles under the search field: one scrolling row, or all of
  /// them under their business category.
  /// A row that runs out to the edges of the yellow card (its padding is 16) and starts back inside it, so the swipe is end to end.
  Widget _bleed(double h, Widget list) => SizedBox(
        height: h,
        child: LayoutBuilder(
          builder: (_, box) => Transform.translate(
            offset: const Offset(-16, 0),
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: box.maxWidth + 32,
              maxWidth: box.maxWidth + 32,
              child: SizedBox(width: box.maxWidth + 32, child: list),
            ),
          ),
        ),
      );

  /// Folds a block away smoothly (height and fade) while a search is on, and brings it back when the box is cleared.
  Widget _fold(bool open, Widget child) => TweenAnimationBuilder<double>(
        tween: Tween(end: open ? 1.0 : 0.0),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        child: child,
        // one fixed chain of wrappers, so the block (the updates, the typed text) keeps its state while folded
        builder: (_, v, c) => Offstage(
          offstage: v <= 0,
          child: IgnorePointer(
            ignoring: v < 1,
            child: ClipRect(
              clipBehavior: v >= 1 ? Clip.none : Clip.hardEdge,
              child: Align(alignment: Alignment.topCenter, heightFactor: v >= 1 ? null : v, child: Opacity(opacity: v, child: c)),
            ),
          ),
        ),
      );

  Widget _shortcut(Pal p, IconData icon, String label, VoidCallback onTap) => Material(
        color: kGold.withValues(alpha: p.dark ? .1 : .08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: kGold.withValues(alpha: .3))),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(width: 40, height: 40, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: kGoldGradient), child: Icon(icon, size: 20, color: kInk)),
              const SizedBox(width: 10),
              Expanded(child: Text(t(label), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, height: 1.15))),
            ]),
          ),
        ),
      );

  Widget _categoryTiles(Pal p) {
    if (_cats.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 18),
      Row(children: [
        Expanded(child: Text(t('Browse by category'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
        GestureDetector(
          onTap: () => setState(() => _allCats = !_allCats),
          behavior: HitTestBehavior.opaque,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4), child: Text(t(_allCats ? 'Hide' : 'See all'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.link))),
        ),
      ]),
      const SizedBox(height: 4),
      if (!_allCats)
        SizedBox(
          height: 112,
          // a whole number of tiles plus a half, so the last one is cut off and hints the row scrolls
          child: LayoutBuilder(builder: (_, box) {
            final shown = box.maxWidth < 400 ? 4.5 : (box.maxWidth < 560 ? 5.5 : 6.5);
            // out to both screen edges (the page's side padding is 16) and back in at the start, so the swipe runs end to end
            return Transform.translate(
              offset: const Offset(-16, 0),
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: box.maxWidth + 32,
                maxWidth: box.maxWidth + 32,
                child: SizedBox(
                  width: box.maxWidth + 32,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: _cats.length,
                    itemBuilder: (_, i) => _catTile(_cats[i], w: box.maxWidth / shown),
                  ),
                ),
              ),
            );
          }),
        )
      else
        for (final parent in kProfileCategories.map((c) => c.value))
          if (_cats.any((c) => c['parent'] == parent)) ...[
            Padding(padding: const EdgeInsets.only(top: 8, bottom: 6), child: Text(t(parent), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
            Wrap(runSpacing: 6, spacing: 4, children: [for (final c in _cats.where((c) => c['parent'] == parent)) _catTile(c)]),
          ],
    ]);
  }

  /// The search with where to look inside the box, under the text: the current location unless another town is picked
  /// (every city of India, or any town typed).
  Widget _searchBox() {
    final p = Pal.of(context);
    return _GlowBorder(
      radius: 26,
      child: ColoredBox(
        color: p.card,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            key: _searchKey,
            controller: _q,
            focusNode: _qFocus,
            onChanged: _search,
            onSubmitted: (v) => _askAi(v.trim()),
            textInputAction: TextInputAction.search,
            keyboardType: TextInputType.text,
            // tapped: the box grows taller to take a whole sentence
            minLines: _qFocus.hasFocus || _q.text.isNotEmpty ? 2 : 1,
            maxLines: _qFocus.hasFocus || _q.text.isNotEmpty ? 2 : 1,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              filled: true,
              fillColor: p.card,
              contentPadding: const EdgeInsets.symmetric(vertical: 17, horizontal: 8),
              prefixIcon: Padding(padding: const EdgeInsets.only(left: 12, right: 10), child: _aiBadge()),
              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
              hintText: _typed.isNotEmpty ? _typed : t('Ask AI: a name, or what you need'),
              hintStyle: TextStyle(fontSize: 15, color: p.muted),
              // text in the box: a clear icon in the place of the microphone (clearing leaves the search)
              suffixIcon: _q.text.isNotEmpty
                  ? IconButton(
                      tooltip: t('Clear'),
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _q.clear();
                        _search('');
                      })
                  : MicButton(island: true, onWords: (words, _) {
                      _q.text = words;
                      _q.selection = TextSelection.collapsed(offset: _q.text.length);
                      _search(words);
                    }),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
          Divider(height: 1, thickness: 1, color: p.border.withValues(alpha: .6)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 3, 12, 3),
            child: Row(children: [
              Expanded(
                child: Align(
              alignment: Alignment.centerLeft,
              child: CityPill(
                value: _place,
                anyLabel: _hereCity ?? t('Current location'),
                flat: true,
                onChanged: (c) {
                  setState(() {
                    _place = c.name;
                    _placeAt = c.lat != null && c.lng != null ? (lat: c.lat!, lng: c.lng!) : null;
                    _results = null;
                    _aiFor = null;
                    _ai = null;
                  });
                  final q = _q.text.trim();
                  if (q.length >= 2) _search(q);
                  if (q.length >= 4) _askAi(q);
                },
              ),
            ),
              ),
              // the same as the keyboard's search key: searches now, or puts the cursor in the box when it is empty
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(30),
                  onTap: () {
                    final q = _q.text.trim();
                    if (q.isEmpty) {
                      _qFocus.requestFocus();
                    } else {
                      _qFocus.unfocus();
                      _search(q);
                      if (q.length >= 4) _askAi(q);
                    }
                  },
                  child: Ink(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(30), gradient: kGoldGradient),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.search, size: 18, color: Color(0xFF1E1E1E)),
                      const SizedBox(width: 6),
                      Text(t('Find'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF1E1E1E))),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  /// "AI" with the star, in gold: what the search is
  /// a gold orb with the sparkle, the AI tag on its corner like the app's count badges
  /// the AI pill of the logo
  Widget _aiBadge() => const Padding(padding: EdgeInsets.only(right: 2), child: AiPill(font: 14));

  /// The search page: the search (the ask's title) with Cancel, then, down to the keyboard, what was found as it is
  /// typed and the new ask to post when no one fits.
  bool _askOpen = false;

  /// The results page draws nothing over the rows: no grey press / focus / hover highlight left on a row after opening it and
  /// coming back, and no grey stretch or glow at the ends of the list.
  Widget _noGrey(Widget child) => Theme(
        data: Theme.of(context).copyWith(
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
        ),
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
          child: child,
        ),
      );

  Widget _searchPage(Pal p) => _noGrey(_searchColumn(p));

  Widget _searchColumn(Pal p) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            Expanded(child: _searchField()),
          ]),
        ),
        Expanded(
          child: _hasFound() && !_askOpen
              ? ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: _found(p, tuck: true))
              : SearchAskForm(
            title: _q,
            focus: _qFocus,
            lead: _found(p),
            onPosted: () {
              _closeSearch();
              widget.onPosted?.call();
            },
          ),
        ),
      ]);

  /// My contacts (and the pages saved as contacts) that the search text matches.
  List<_Entry> _mineFor(String q) => _entries.where((e) => '${e.name} ${e.phone ?? ''} ${e.org} ${(e.contact?.emails ?? const <Email>[]).map((m) => m.address).join(' ')} ${e.member == null ? '' : '${e.member!['name']} ${e.member!['company']} ${e.member!['category']} ${e.member!['location']} ${(e.member!['services'] as List? ?? const []).join(' ')}'}'.toLowerCase().contains(q)).toList();

  /// Whether the search found anyone: then the ask to post is tucked away until asked for.
  bool _hasFound() {
    final q = _q.text.trim().toLowerCase();
    if (q.length < 2) return false;
    final ai = _aiFor == _q.text.trim() ? ((_ai?['matches'] as List?) ?? const []) : const [];
    return _mineFor(q).isNotEmpty || ai.isNotEmpty || (_results ?? const <Map>[]).isNotEmpty || _service.isNotEmpty;
  }

  /// What the search found, above the ask: in my contacts, what Ask AI found (with why), others on WEBWEB; then the
  /// heading of the ask to post when none of them fits.
  List<Widget> _found(Pal p, {bool tuck = false}) {
    final q = _q.text.trim().toLowerCase();
    final heading = tuck ? [
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: OutlinedButton.icon(
          onPressed: () => setState(() => _askOpen = true),
          icon: const Icon(Icons.campaign_rounded, size: 18, color: kStar),
          label: Text(t('Not the right one? Post it as an ask')),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), foregroundColor: p.text, side: BorderSide(color: p.border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        ),
      ),
      const SizedBox(height: 24),
    ] : [
      Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 4),
        child: Row(children: [
          const Icon(Icons.campaign_rounded, color: kStar, size: 20),
          const SizedBox(width: 6),
          Expanded(child: Text(t(q.length < 2 ? 'Or post it as an ask' : 'Not the right one? Post it as an ask'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
        ]),
      ),
      Text(t('Members near you who know someone will refer the right contact to you.'), style: TextStyle(fontSize: 13, height: 1.35, color: p.muted)),
      const SizedBox(height: 12),
    ];
    if (q.length < 2) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(t('Type a name, or what you need. Ask AI finds who can help, nearest first.'), style: TextStyle(fontSize: 13.5, height: 1.4, color: p.muted)),
        ),
        ...heading,
      ];
    }
    final all = _entries;
    final mine = _mineFor(q);
    final aiMatches = _aiFor == _q.text.trim() ? ((_ai?['matches'] as List?) ?? const []).cast<Map>() : const <Map>[];
    bool shown(Map u) => mine.any((e) => e.member?['uid'] == u['uid']) || aiMatches.any((m) => m['uid'] == u['uid']);
    // a contact whose page the search found by name, though its number was not matched: one line, the page, not two
    String norm(String x) => x.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    for (var i = 0; i < mine.length; i++) {
      if (mine[i].member != null) continue;
      final u = (_results ?? const <Map>[]).where((u) => norm(_memberName(u)) == norm(mine[i].name) || norm('${u['name'] ?? ''}') == norm(mine[i].name)).firstOrNull;
      if (u != null) mine[i] = _Entry(mine[i].name, mine[i].phone, u, mine[i].contact);
    }
    final others = (_results ?? const <Map>[]).where((u) => !shown(u)).take(20).toList();
    // what the member saved a page as, when it is in their contacts
    final saved = {for (final e in all) if (e.member != null) '${e.member!['uid']}': e.name};
    return [
      ..._resultsSection(p, aiMatches, saved, mine),
      if (others.isNotEmpty) ...[_label(p, t('On WEBWEB')), for (final u in others) _row(p, _Entry(_memberName(u), null, u))],
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => Navigator.push(context, WideRoute(builder: (_) => FindScreen(standalone: true, initialQuery: _q.text.trim()))),
          icon: const Icon(Icons.place_rounded, size: 16),
          label: Text(t('Search nearby')),
        ),
      ),
      ...heading,
    ];
  }

  /// Service providers saved by other members and approved by WEBWEB: name, trade, and call / WhatsApp, each with its
  /// distance (metres, for the merge with Ask AI's pages). Left out when the same number is already in my own contacts.
  List<_Hit> _serviceItems(Pal p, List<_Entry> mine) {
    String d10(String? x) => ContactSync.mobile10(x ?? '') ?? '';
    final have = {for (final e in mine) d10(e.phone), for (final e in mine) ...(e.contact?.phones ?? const <Phone>[]).map((ph) => d10(ph.number))};
    final list = _service.where((c) => !have.contains('${c['phone']}')).toList();
    if (list.isEmpty) return const [];
    // who shares it, by the name saved in MY phone book (never the name the sharer is known by elsewhere)
    final saved = <String, String>{};
    for (final e in mine) {
      for (final n in {d10(e.phone), ...(e.contact?.phones ?? const <Phone>[]).map((ph) => d10(ph.number))}) {
        if (n.isNotEmpty) saved.putIfAbsent(ContactSync.sharerId(n), () => e.name);
      }
    }
    String? sharedBy(Map c) {
      final s = c['sharedBy'];
      if (s is! Map) return null;
      final n = (s['count'] as num?)?.toInt() ?? 0;
      if (n <= 0) return null;
      final known = {
        for (final id in (s['ids'] as List? ?? const [])) if (saved['$id'] != null) saved['$id']!,
      }.toList();
      if (known.isEmpty) return n == 1 ? t('Shared by 1 member') : t('Shared by {n} members', {'n': n});
      final others = n - known.take(2).length;
      final names = known.take(2).join(' & ');
      return others > 0 ? t('Shared by {names} and {n} more', {'names': names, 'n': others}) : t('Shared by {names}', {'names': names});
    }
    return [
      for (final c in list)
        _Hit(
          c['km'] is num ? (c['km'] as num).toDouble() * 1000 : double.infinity,
          c['km'] is num ? (c['km'] as num).toDouble() * 1000 : (ApproxDistance.km(_base, '${c['place'] ?? ''}') ?? double.infinity / 1000) * 1000,
          ((c['sharedBy'] is Map ? (c['sharedBy'] as Map)['count'] : 0) as num?)?.toInt() ?? 0,
          (c['rating'] as num?)?.toDouble() ?? 0,
          (c['ratings'] as num?)?.toInt() ?? 0,
          // the same row as an Ask AI page: the picture (initials, no gold W), the name with no verified mark, the trade and place
          InkWell(
            onTap: () => Navigator.push(context, WideRoute(builder: (_) => ServicePageScreen(phone: '${c['phone']}', initial: c, shared: sharedBy(c)))),
            child: Container(
              constraints: const BoxConstraints(minHeight: _rowH),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Avatar(name: '${c['name']}', size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${c['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    Text(
                      [
                        ...((c['tags'] as List?) ?? const []).take(2),
                        if ('${c['place'] ?? ''}'.isNotEmpty) '${c['place']}',
                        if (c['km'] is num)
                          t('{n} km', {'n': (c['km'] as num) < 10 ? (c['km'] as num).toStringAsFixed(1) : (c['km'] as num).round()})
                        else
                          ApproxDistance.label(ApproxDistance.km(_base, '${c['place'] ?? ''}')),
                        // from Google (Places)
                        if (c['rating'] is num) '★ ${(c['rating'] as num).toStringAsFixed(1)}${c['ratings'] is num ? ' (${c['ratings']})' : ''} Google',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: p.muted),
                    ),
                    if (sharedBy(c) != null) Text(sharedBy(c)!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.link, fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                ),
                // the page has Call and WhatsApp and the details: the arrow says there is more
                Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.chevron_right_rounded, size: 24, color: p.muted)),
              ]),
            ),
          ),
        ),
    ];
  }

  /// The hits in the order chosen with the sort chips ([merged]: already in the recommended order).
  List<_Hit> _sorted(List<_Hit> l, {bool merged = false}) {
    final o = [...l];
    switch (_sort) {
      case 'near':
        o.sort((a, b) => a.dist.compareTo(b.dist));
      case 'shared':
        o.sort((a, b) => b.shared != a.shared ? b.shared.compareTo(a.shared) : a.dist.compareTo(b.dist));
      case 'rated':
        o.sort((a, b) => b.rating != a.rating ? b.rating.compareTo(a.rating) : b.reviews != a.reviews ? b.reviews.compareTo(a.reviews) : a.dist.compareTo(b.dist));
    }
    return o;
  }

  Widget _sortBar(Pal p) {
    const opts = [('rec', 'Recommended'), ('near', 'Nearest'), ('shared', 'Shared by many'), ('rated', 'Top rated')];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        children: [
          for (final (k, label) in opts)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _sort = k),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    gradient: _sort == k ? kGoldGradient : null,
                    borderRadius: BorderRadius.circular(16),
                    border: _sort == k ? null : Border.all(color: p.border),
                  ),
                  child: Text(t(label), style: TextStyle(fontSize: 13, fontWeight: _sort == k ? FontWeight.w800 : FontWeight.w600, color: _sort == k ? const Color(0xFF3d3500) : p.muted)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Ask AI's pages and the service contacts as one list under one heading, nearest first where both know the distance.
  List<Widget> _resultsSection(Pal p, List<Map> matches, Map<String, String> saved, List<_Entry> mine) {
    final svc = _serviceItems(p, mine);
    // the contacts saved on this phone look the same as the rest, at the top of the one list
    final own = [for (final e in mine.take(30)) _row(p, e)];
    if (_q.text.trim().length < 4) {
      if (own.isEmpty && svc.isEmpty) return const [];
      return [_label(p, t(own.isNotEmpty ? 'In your contacts' : 'Service contacts')), ...own, for (final s in _sorted(svc)) s.w];
    }
    return _aiSection(p, matches, saved, svc, own);
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
  List<Widget> _aiSection(Pal p, List<Map> matches, Map<String, String> saved, [List<_Hit> svc = const [], List<Widget> own = const []]) {
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
        ...own,
        for (final s in svc) s.w,
      ];
    }
    if (matches.isEmpty && svc.isEmpty) return [if (own.isNotEmpty) ...[_label(p, t('In your contacts')), ...own], head, Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(t('No page fits this yet.'), style: TextStyle(color: p.muted)))];
    // one list: the pages and the service contacts, nearest first (a page with no distance keeps its place at the top)
    final pages = [
      for (final m in matches)
        _Hit(
          (m['distanceM'] as num?)?.toDouble() ?? 0.0,
          (m['distanceM'] as num?)?.toDouble() ?? (ApproxDistance.km(_base, '${m['location'] ?? ''}') ?? double.infinity / 1000) * 1000,
          0,
          (m['rating'] as num?)?.toDouble() ?? 0,
          (m['reviews'] as num?)?.toInt() ?? 0,
          _row(p, _Entry(saved['${m['uid']}'] ?? _memberName(m), null, m), why: '${m['why'] ?? ''}'),
        ),
    ];
    final mixed = <_Hit>[];
    var i = 0, j = 0;
    while (i < pages.length || j < svc.length) {
      mixed.add(j >= svc.length || (i < pages.length && pages[i].d <= svc[j].d) ? pages[i++] : svc[j++]);
    }
    return [head, if (mixed.length >= 2) _sortBar(p), ...own, for (final h in _sorted(mixed, merged: true)) h.w];
  }

  Widget _row(Pal p, _Entry e, {String? why}) {
    final m = e.member;
    final who = m == null ? '' : _memberName(m);
    final d = (m?['distanceM'] as num?)?.toDouble();
    final away = d == null ? ApproxDistance.label(ApproxDistance.km(_base, '${m?['location'] ?? ''}')) : (d < 1000 ? t('under 1 km') : t('{n} km', {'n': (d / 1000).toStringAsFixed(d < 10000 ? 1 : 0)}));
    final sub = m == null
        ? [e.org, e.phone ?? ''].where((s) => s.isNotEmpty).join(' · ')
        : [if (who != e.name) who, '${m['category'] ?? ''}', '${m['location'] ?? ''}', away].where((s) => s.isNotEmpty).join(' · ');
    final reviews = (m?['reviews'] as num?)?.toInt() ?? 0;
    final rating = (m?['rating'] as num?)?.toDouble() ?? 0;
    final level = (m?['verificationLevel'] as num?)?.toInt() ?? 0;
    return InkWell(
      onTap: () => m != null ? Navigator.push(context, WideRoute(builder: (_) => ProfileScreen(handle: '${m['handle']}'))) : _contactSheet(e),
      child: Container(
        constraints: BoxConstraints(minHeight: _rowH, maxHeight: why == null || why.isEmpty ? _rowH : double.infinity),
        padding: EdgeInsets.symmetric(vertical: why == null || why.isEmpty ? 0 : 8),
        child: Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            _photo(e, m, 44),
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
                if (reviews > 0) ...[const SizedBox(width: 6), Text('★ ${rating.toStringAsFixed(1)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.tagText))],
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
        ]),
      ),
    );
  }

  /// The page's photo, else the one saved on the phone, else the initials
  Widget _photo(_Entry e, Map? m, double size) {
    final url = (m?['photoURL'] ?? m?['photoUrl']) as String?;
    final thumb = e.contact?.photo?.thumbnail;
    if ((url ?? '').isEmpty && thumb != null && thumb.isNotEmpty) {
      return ClipOval(child: Image.memory(thumb, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true));
    }
    return Avatar(name: e.name, photoUrl: url, size: size);
  }

  /// A contact without a page: everything saved on it (each number with call and WhatsApp, emails, company,
  /// address), and an invitation to make a page.
  Future<void> _contactSheet(_Entry e) async {
    final p = Pal.of(context);
    final c = e.contact;
    final phones = c == null ? [if (e.phone != null) e.phone!] : c.phones.map((ph) => ph.number).toSet().toList();
    final emails = (c?.emails ?? const <Email>[]).map((m) => m.address.trim()).where((m) => m.isNotEmpty).toSet().toList();
    final places = (c?.addresses ?? const <Address>[])
        .map((a) => (a.formatted ?? [a.street, a.subLocality, a.city, a.state, a.postalCode].whereType<String>().where((x) => x.trim().isNotEmpty).join(', ')).trim())
        .where((a) => a.isNotEmpty)
        .toSet()
        .toList();
    final ten = phones.map(ContactSync.mobile10).whereType<String>().firstOrNull;
    final invite = '${t('I have a free business page on WEBWEB, the AI Phonebook. Make yours so customers can find and review you:')} https://webweb.ai';
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.canvas,
      isScrollControlled: true,
      builder: (ctx) {
        void go(String url) {
          Navigator.pop(ctx);
          _open(url);
        }

        Widget icon(IconData i, Color color, String tip, VoidCallback onTap) => IconButton(tooltip: tip, onPressed: onTap, icon: Icon(i, color: color));
        Widget iconW(Widget w, String tip, VoidCallback onTap) => IconButton(tooltip: tip, onPressed: onTap, icon: w);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .8),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                ListTile(
                  leading: _photo(e, null, 48),
                  title: Text(e.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  subtitle: e.org.isEmpty ? null : Text(e.org, style: TextStyle(color: p.muted)),
                ),
                const Divider(height: 8),
                for (final ph in phones)
                  ListTile(
                    leading: Icon(Icons.phone_rounded, color: p.muted),
                    title: Text(ph),
                    onTap: () => go('tel:${ph.replaceAll(RegExp(r'[^\d+]'), '')}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      icon(Icons.call_rounded, const Color(0xFF1E9E5A), t('Call'), () => go('tel:${ph.replaceAll(RegExp(r'[^\d+]'), '')}')),
                      if (ContactSync.mobile10(ph) != null) iconW(const WhatsAppIcon(size: 24), 'WhatsApp', () => go('https://wa.me/91${ContactSync.mobile10(ph)}')),
                    ]),
                  ),
                for (final m in emails)
                  ListTile(leading: Icon(Icons.mail_outline_rounded, color: p.muted), title: Text(m), onTap: () => go('mailto:$m')),
                for (final a in places)
                  ListTile(
                    leading: Icon(Icons.place_outlined, color: p.muted),
                    title: Text(a),
                    onTap: () => go('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(a)}'),
                  ),
                if (ten != null) ...[
                  const Divider(height: 8),
                  ListTile(
                    leading: const Icon(Icons.person_add_alt_1_rounded, color: kStar),
                    title: Text(t('Invite to the phonebook')),
                    onTap: () => go('https://wa.me/91$ten?text=${Uri.encodeComponent(invite)}'),
                  ),
                ],
              ]),
            ),
          ),
        );
      },
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
      onTap: () => Navigator.push(context, WideRoute(builder: (_) => PostDetailScreen(postId: a.id))),
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
      onTap: () => Navigator.push(context, WideRoute(builder: (_) => ProfileScreen(handle: handle))),
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


/// The four SkyQ colours that run round [child]'s border (a sweep gradient turning), with a soft glow; still when the phone
/// asks for less motion.
class _GlowBorder extends StatefulWidget {
  final Widget child;
  final double radius;
  const _GlowBorder({required this.child, required this.radius});
  @override
  State<_GlowBorder> createState() => _GlowBorderState();
}

class _GlowBorderState extends State<_GlowBorder> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 4));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const w = 2.0;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => Container(
        padding: const EdgeInsets.all(w),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: SweepGradient(
            transform: GradientRotation(_c.value * 6.2832),
            // the four colours of the SkyQ mark, running round the border as on Google's AI Mode button
            colors: const [Color(0xFF0575E6), Color(0xFF34A853), Color(0xFFFFC700), Color(0xFFFF0000), Color(0xFF0575E6)],
            stops: const [0, .25, .5, .75, 1],
          ),
          boxShadow: [
            BoxShadow(color: const Color(0xFF0575E6).withValues(alpha: .18), blurRadius: 14, spreadRadius: 0.5),
            BoxShadow(color: const Color(0xFFFFC700).withValues(alpha: .14), blurRadius: 14, spreadRadius: 0.5),
          ],
        ),
        child: child,
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(widget.radius - w), child: widget.child),
    );
  }
}


/// What the right column asks of the Directory: a search and where to look (a fresh value each time, so the same search
/// can be sent again).
/// the search icon of the top bar: open the Directory with its search box ready to type in
final directoryFocus = ValueNotifier<int>(0);

/// The island's Speak button (shown on the Find page): [directorySpeak] is tapped; the page clears its box and bumps
/// [directoryVoice], which its microphone listens to. [directoryBusy]: a search is running (the ring round the button turns).
final directorySpeak = ValueNotifier<int>(0);
final directoryVoice = ValueNotifier<int>(0);
final directoryBusy = ValueNotifier<bool>(false);

/// The loudness of the member's voice, 0..1, while the microphone listens (-1 when it does not): the ring round the Find button follows it.
final directoryLevel = ValueNotifier<double>(-1);

final directoryRequest = ValueNotifier<({String q, String place, ({double lat, double lng})? at, int n})?>(null);

/// The microphone of a search: asks for the microphone first, then listens in the app's language (Konkani is heard as
/// Hindi) and hands the words over as they come ([done] when they are final).
/// The Directory's search bar for any search: the AI badge, the four SkyQ colours round the box, the microphone.
class AiSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final Widget? trailing;
  const AiSearchField({super.key, required this.controller, required this.hint, required this.onChanged, this.onSubmitted, this.focusNode, this.trailing});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return _GlowBorder(
      radius: 28,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          filled: true,
          fillColor: p.card,
          contentPadding: const EdgeInsets.symmetric(vertical: 17, horizontal: 8),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 12, right: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(14)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Text('AI', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kInk, height: 1)),
                SizedBox(width: 3),
                Icon(Icons.auto_awesome_rounded, size: 14, color: kInk),
              ]),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          hintText: hint,
          hintStyle: TextStyle(fontSize: 15, color: p.muted),
          suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
            if (trailing != null) trailing!,
            // text in the box: a clear icon in the place of the microphone
            if (controller.text.isNotEmpty)
              IconButton(
                tooltip: t('Clear'),
                icon: const Icon(Icons.close),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              )
            else
              MicButton(onWords: (words, _) {
                controller.text = words;
                controller.selection = TextSelection.collapsed(offset: words.length);
                onChanged(words);
              }),
          ]),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }
}

class MicButton extends StatefulWidget {
  final void Function(String words, bool done) onWords;
  /// the island's Speak button starts this one (the box of the Find page)
  final bool island;
  const MicButton({super.key, required this.onWords, this.island = false});
  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton> {
  final _speech = SpeechToText();
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    if (widget.island) directoryVoice.addListener(_fromIsland);
  }

  void _fromIsland() {
    if (mounted) _toggle();
  }

  @override
  void dispose() {
    directoryVoice.removeListener(_fromIsland);
    _speech.cancel();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_listening) {
      await _speech.stop();
      directoryLevel.value = -1;
      if (mounted) setState(() => _listening = false);
      return;
    }
    final ok = await Permissions.ensure(context, Need.microphone, reason: t('To hear what you want to search for.'));
    if (!ok || !mounted) return;
    final ready = await _speech.initialize(onStatus: (s) {
      if (s == 'done' || s == 'notListening') {
        directoryLevel.value = -1;
        if (mounted) setState(() => _listening = false);
      }
    }, onError: (_) {
      directoryLevel.value = -1;
      if (mounted) {
        setState(() => _listening = false);
        toast(context, t('Could not hear that. Try again.'), error: true);
      }
    });
    if (!ready || !mounted) return;
    final loc = switch (currentLang) { 'hi' || 'kok' => 'hi_IN', 'mr' => 'mr_IN', 'gu' => 'gu_IN', _ => 'en_IN' };
    setState(() => _listening = true);
    directoryLevel.value = 0;
    await _speech.listen(
      onSoundLevelChange: (db) {
        // about -2 (quiet) to 10 (loud) dB on both platforms, eased so the ring does not flicker
        final v = ((db + 2) / 12).clamp(0.0, 1.0);
        directoryLevel.value = v > directoryLevel.value ? v : directoryLevel.value * 0.8 + v * 0.2;
      },
      listenOptions: SpeechListenOptions(partialResults: true, listenMode: ListenMode.search, localeId: loc),
      onResult: (r) {
        widget.onWords(r.recognizedWords, r.finalResult);
        if (r.finalResult) {
          directoryLevel.value = -1;
          if (mounted) setState(() => _listening = false);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: t(_listening ? 'Listening… tap to stop' : 'Speak your ask'),
        icon: WIcon(WI.mic, size: 22, color: _listening ? kGold : Pal.of(context).muted),
        onPressed: _toggle,
      );
}

/// The Directory's search in the right column of wide screens (web right-rail.tsx): the AI badge, the four SkyQ colours
/// running round the box, the microphone, and where to look. Enter (or a voice search) opens the Directory with it.
class DirectoryRailSearch extends StatefulWidget {
  final VoidCallback onOpen;
  const DirectoryRailSearch({super.key, required this.onOpen});
  @override
  State<DirectoryRailSearch> createState() => _DirectoryRailSearchState();
}

class _DirectoryRailSearchState extends State<DirectoryRailSearch> {
  final _q = TextEditingController();
  String _place = '';
  ({double lat, double lng})? _at;
  static int _n = 0;
  /// the city the phone is in (when location is already allowed), shown for "Current location"
  String? _hereCity;

  @override
  void initState() {
    super.initState();
    _detectCity();
  }

  Future<void> _detectCity() async {
    if (!ContactSync.supported || !await Permissions.granted(Need.location)) return;
    try {
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 6)))
          .catchError((_) async => (await Geolocator.getLastKnownPosition())!);
      final city = placeAt(p.latitude, p.longitude)?.name;
      if (mounted && city != _hereCity) setState(() => _hereCity = city);
    } catch (_) {}
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _go() {
    directoryRequest.value = (q: _q.text.trim(), place: _place, at: _at, n: ++_n);
    widget.onOpen();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _GlowBorder(
        radius: 26,
        child: Container(
          color: p.card,
          height: 48,
          padding: const EdgeInsets.only(left: 10),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(14)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Text('AI', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kInk, height: 1)),
                SizedBox(width: 3),
                Icon(Icons.auto_awesome_rounded, size: 14, color: kInk),
              ]),
            ),
            Expanded(
              child: TextField(
                controller: _q,
                onSubmitted: (_) => _go(),
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  hintText: t('Ask AI: a name, or what you need'),
                  hintStyle: TextStyle(fontSize: 13.5, color: p.muted),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ),
            MicButton(onWords: (words, done) {
              _q.text = words;
              if (done && words.trim().isNotEmpty) _go();
            }),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: CityPill(
          value: _place,
          anyLabel: _hereCity ?? t('Current location'),
          chip: true,
          onChanged: (c) {
            setState(() {
              _place = c.name;
              _at = c.lat != null && c.lng != null ? (lat: c.lat!, lng: c.lng!) : null;
            });
            if (_q.text.trim().isNotEmpty) _go();
          },
        ),
      ),
    ]);
  }
}

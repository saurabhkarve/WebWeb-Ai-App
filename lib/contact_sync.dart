import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'permissions.dart';

/// Service contacts: with the member's say-so (off until they turn it on), the app looks through the phone book
/// on the phone for contacts saved with a service word ("Ramesh Plumber", "Sai Cabs") and sends only those:
/// saved name, number and the word that matched, and the picture saved with it (the phone's small thumbnail).
/// The rest of the phone book never leaves the phone.
/// The words come from the server (Admin > Service contacts > Keywords). It runs quietly while the app is open,
/// at most once a day, and sends only contacts it has not sent before.
class ContactSync {
  static const _kSent = 'svc_contacts_sent';
  static const _kLast = 'svc_contacts_last';
  static const _kAsked = 'svc_contacts_asked';
  /// number -> fingerprint of the picture last sent for it ('' = sent as none), so a picture goes again only when it changes
  static const _kPhotos = 'svc_contacts_photos';
  static bool _running = false;

  static bool get supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// Lower case; anything that is not a letter, mark or digit becomes one space (works in every script).
  static String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true), ' ').trim();

  /// A 10-digit Indian mobile from however it was saved, or null (landlines and foreign numbers are skipped).
  static String? mobile10(String raw) {
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length == 12 && d.startsWith('91')) {
      d = d.substring(2);
    } else if (d.length == 11 && d.startsWith('0')) {
      d = d.substring(1);
    }
    return RegExp(r'^[6-9]\d{9}$').hasMatch(d) ? d : null;
  }

  /// What the server sends for each member who shares a contact: a salted hash of their number, never the number.
  /// The phone hashes the numbers in its own phone book the same way to tell which sharers the member has saved.
  static String sharerId(String phone10) => sha256.convert(utf8.encode('wwsc1:$phone10')).toString().substring(0, 16);

  static String _cut(String s) => s.length > 120 ? s.substring(0, 120) : s;

  /// Is it on for this member (the server keeps the choice, so it follows them to a new phone)?
  static Future<bool> isOn(Api api) async {
    final d = await api.get('/contact-sync') as Map;
    return d['on'] == true;
  }

  /// Turn it on or off. Off only stops further sharing (the server remembers the choice); contacts already shared stay until the member removes them one by one.
  static Future<void> setOn(Api api, bool on) async {
    await api.put('/contact-sync', {'on': on});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAsked, true);
    if (!on) {
      await prefs.remove(_kSent);
      await prefs.remove(_kLast);
    }
  }

  /// What this member shares, and what they removed from it (the server tags those removed).
  static Future<SharedContacts> mine(Api api) async {
    final d = await api.get('/contact-sync/mine') as Map;
    List<SharedContact> rows(String k) => [for (final r in (d[k] as List? ?? const [])) SharedContact.fromJson(Map<String, dynamic>.from(r as Map))];
    return SharedContacts(rows('shared'), rows('removed'), place: '${d['place'] ?? ''}', tags: [for (final x in (d['tags'] as List? ?? const [])) '$x']);
  }

  /// Stop sharing one contact. The server tags it removed and the next look through the phone book skips it.
  static Future<void> remove(Api api, String phone) => api.delete('/contact-sync/contacts/$phone');

  /// Rate (1-5, 0 clears), rename, set the category or the place of a shared contact. Only what is passed is changed;
  /// an empty [place] goes back to the member's own city.
  static Future<void> update(Api api, String phone, {int? rating, String? name, String? tag, String? place}) => api.patch(
        '/contact-sync/contacts/$phone',
        {if (rating != null) 'rating': rating, if (name != null) 'name': name, if (tag != null) 'tag': tag, if (place != null) 'place': place},
      );

  /// Share a removed contact again.
  static Future<void> restore(Api api, String phone) => api.post('/contact-sync/contacts/$phone/restore', {});

  static const _kInvites = 'svc_invites';
  static const _kInviteAt = 'svc_invite_at';

  /// Show the invitation now? Not on every open: the first time at the start, then at most 3 times in all, a week
  /// apart, and never once it is on, or when the phone will not ask again (the profile's strength then points to
  /// Settings). The caller has checked that it is not on yet.
  static Future<bool> shouldInvite() async {
    if (!supported) return false;
    final prefs = await SharedPreferences.getInstance();
    final n = prefs.getInt(_kInvites) ?? 0;
    final at = prefs.getInt(_kInviteAt) ?? 0;
    if (n >= 3) return false;
    if (n > 0 && DateTime.now().millisecondsSinceEpoch - at < const Duration(days: 7).inMilliseconds) return false;
    final s = await Permission.contacts.status;
    if (s.isPermanentlyDenied || s.isRestricted) return false;
    return true;
  }

  /// Has the member been offered it (or chosen) on this phone?
  static Future<bool> wasAsked() async => (await SharedPreferences.getInstance()).getBool(_kAsked) == true;

  static Future<void> markInvited() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAsked, true);
    await prefs.setInt(_kInvites, (prefs.getInt(_kInvites) ?? 0) + 1);
    await prefs.setInt(_kInviteAt, DateTime.now().millisecondsSinceEpoch);
  }

  /// Look and send, if it is on and contacts are allowed. Never asks for anything; returns how many were sent.
  /// [force] skips the once-a-day limit (right after turning it on).
  static Future<int> run(Api api, {bool force = false}) async {
    if (!supported || _running) return 0;
    _running = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_kLast) ?? 0;
      if (!force && DateTime.now().millisecondsSinceEpoch - last < const Duration(hours: 24).inMilliseconds) return 0;
      if (!await Permissions.granted(Need.contacts)) return 0;
      final d = await api.get('/contact-sync') as Map;
      if (d['on'] != true) return 0;
      final words = <String>[
        for (final k in (d['keywords'] as List? ?? const [])) norm('${(k as Map)['k']}'),
      ].where((w) => w.isNotEmpty).toList()
        // longer words first, so "pest control" wins over "pest"
        ..sort((a, b) => b.length.compareTo(a.length));
      if (words.isEmpty) return 0;

      final contacts = await FlutterContacts.getAll(properties: {ContactProperty.phone, ContactProperty.organization});
      final sent = (prefs.getStringList(_kSent) ?? const []).toSet();
      final out = <Map<String, String>>[];
      final seen = <String>{};
      // every matched contact (sent now or before), for its picture: contact id -> its numbers
      final matched = <String, List<String>>{};
      for (final c in contacts) {
        final name = (c.displayName ?? '').trim();
        if (name.isEmpty || c.phones.isEmpty) continue;
        final org = c.organizations
            .map((o) => [o.name, o.jobTitle].whereType<String>().where((s) => s.trim().isNotEmpty).join(' '))
            .where((s) => s.isNotEmpty)
            .join(' ')
            .trim();
        final hay = ' ${norm('$name $org')} ';
        final word = words.cast<String?>().firstWhere((w) => hay.contains(' $w '), orElse: () => null);
        if (word == null) continue;
        for (final p in c.phones) {
          final m = mobile10(p.number);
          if (m != null && c.id != null) matched.putIfAbsent(c.id!, () => []).add(m);
          if (m == null || sent.contains(m) || !seen.add(m)) continue;
          out.add({'name': _cut(name), if (org.isNotEmpty) 'org': _cut(org), 'phone': m, 'keyword': word});
        }
      }
      for (var i = 0; i < out.length; i += 500) {
        final batch = out.sublist(i, i + 500 > out.length ? out.length : i + 500);
        await api.post('/contact-sync', {'contacts': batch});
        sent.addAll(batch.map((b) => b['phone']!));
        await prefs.setStringList(_kSent, sent.toList());
      }
      await _sendPhotos(api, prefs, matched, sent);
      await prefs.setInt(_kLast, DateTime.now().millisecondsSinceEpoch);
      return out.length;
    } catch (_) {
      return 0; // quietly try again next time
    } finally {
      _running = false;
    }
  }
}

/// The pictures saved with the matched contacts, read one contact at a time (only those, never the whole phone
/// book's pictures) and sent five at a time when new, changed or deleted. At most 100 a day.
Future<void> _sendPhotos(Api api, SharedPreferences prefs, Map<String, List<String>> matched, Set<String> sent) async {
  final known = <String, String>{};
  try {
    known.addAll((jsonDecode(prefs.getString(ContactSync._kPhotos) ?? '{}') as Map).map((k, v) => MapEntry('$k', '$v')));
  } catch (_) {}
  final queue = <Map<String, Object?>>[];
  final marks = <String, String>{};
  for (final e in matched.entries) {
    if (queue.length >= 100) break;
    final phones = e.value.where(sent.contains).toSet(); // only numbers the server has
    if (phones.isEmpty) continue;
    Uint8List? thumb;
    try {
      thumb = (await FlutterContacts.get(e.key, properties: {ContactProperty.photoThumbnail}))?.photo?.thumbnail;
    } catch (_) {
      continue;
    }
    if (thumb != null && (thumb.length < 100 || thumb.length > 150000)) thumb = null;
    final mark = thumb == null ? '' : sha256.convert(thumb).toString().substring(0, 16);
    for (final p in phones) {
      final was = known[p];
      if (was == mark || (was == null && mark.isEmpty)) continue; // unchanged, or never had one
      queue.add({'phone': p, 'image': thumb == null ? null : base64Encode(thumb)});
      marks[p] = mark;
    }
  }
  for (var i = 0; i < queue.length; i += 5) {
    final batch = queue.sublist(i, i + 5 > queue.length ? queue.length : i + 5);
    await api.post('/contact-sync/photos', {'photos': batch});
    for (final b in batch) {
      known['${b['phone']}'] = marks['${b['phone']}']!;
    }
    await prefs.setString(ContactSync._kPhotos, jsonEncode(known));
  }
}

class SharedContact {
  final String phone, name, keyword, place, tag;
  final int rating;
  final DateTime at;
  const SharedContact(this.phone, this.name, this.keyword, this.at, {this.rating = 0, this.place = '', this.tag = ''});
  factory SharedContact.fromJson(Map<String, dynamic> j) => SharedContact(
        '${j['phone']}',
        '${j['name']}',
        '${j['keyword']}',
        DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
        rating: (j['rating'] as num?)?.toInt() ?? 0,
        place: '${j['place'] ?? ''}',
        tag: '${j['tag'] ?? ''}',
      );
  SharedContact copyWith({String? name, String? place, String? tag, int? rating}) =>
      SharedContact(phone, name ?? this.name, keyword, at, rating: rating ?? this.rating, place: place ?? this.place, tag: tag ?? this.tag);
}

class SharedContacts {
  final List<SharedContact> shared, removed;
  /// The member's own city (the place of every contact until they change it), and the categories to pick from.
  final String place;
  final List<String> tags;
  const SharedContacts(this.shared, this.removed, {this.place = '', this.tags = const []});
}

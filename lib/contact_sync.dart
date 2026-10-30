import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'permissions.dart';

/// Service contacts: with the member's say-so (off until they turn it on), the app looks through the phone book
/// on the phone for contacts saved with a service word ("Ramesh Plumber", "Sai Cabs") and sends only those:
/// saved name, number and the word that matched. The rest of the phone book never leaves the phone.
/// The words come from the server (Admin > Service contacts > Keywords). It runs quietly while the app is open,
/// at most once a day, and sends only contacts it has not sent before.
class ContactSync {
  static const _kSent = 'svc_contacts_sent';
  static const _kLast = 'svc_contacts_last';
  static const _kAsked = 'svc_contacts_asked';
  static const _kOpens = 'svc_contacts_opens';
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

  static String _cut(String s) => s.length > 120 ? s.substring(0, 120) : s;

  /// Is it on for this member (the server keeps the choice, so it follows them to a new phone)?
  static Future<bool> isOn(Api api) async {
    final d = await api.get('/contact-sync') as Map;
    return d['on'] == true;
  }

  /// Turn it on or off. Off removes everything this member sent, and the phone forgets what it sent.
  static Future<void> setOn(Api api, bool on) async {
    await api.put('/contact-sync', {'on': on});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAsked, true);
    if (!on) {
      await prefs.remove(_kSent);
      await prefs.remove(_kLast);
    }
  }

  /// Show the one-time invitation? From the member's third app open, once, when it is not on yet.
  static Future<bool> shouldInvite() async {
    if (!supported) return false;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kAsked) == true) return false;
    final opens = (prefs.getInt(_kOpens) ?? 0) + 1;
    await prefs.setInt(_kOpens, opens);
    return opens >= 3;
  }

  /// Has the member been offered it (or chosen) on this phone?
  static Future<bool> wasAsked() async => (await SharedPreferences.getInstance()).getBool(_kAsked) == true;

  static Future<void> markInvited() async => (await SharedPreferences.getInstance()).setBool(_kAsked, true);

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
      await prefs.setInt(_kLast, DateTime.now().millisecondsSinceEpoch);
      return out.length;
    } catch (_) {
      return 0; // quietly try again next time
    } finally {
      _running = false;
    }
  }
}

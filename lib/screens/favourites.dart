import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

/// Starred contacts, like a phone's Favourites: kept on this phone (name, page and photo of each), newest first.
class Favourites {
  static const _k = 'fav_contacts';
  static final list = ValueNotifier<List<Map>>(const []);
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final raw = (await SharedPreferences.getInstance()).getString(_k);
    if (raw == null) return;
    try {
      list.value = (jsonDecode(raw) as List).cast<Map>();
    } catch (_) {}
  }

  static bool has(String uid) => list.value.any((m) => m['uid'] == uid);

  static Future<void> toggle(Profile u) async {
    await load();
    list.value = has(u.uid)
        ? list.value.where((m) => m['uid'] != u.uid).toList()
        : [
            {'uid': u.uid, 'handle': u.handle, 'name': u.name, 'company': u.company, 'userType': u.userType, 'photoURL': u.photoUrl, 'category': u.category, 'verification': u.verification},
            ...list.value,
          ];
    await (await SharedPreferences.getInstance()).setString(_k, jsonEncode(list.value));
  }
}

/// Contact pages opened lately, newest first (kept on this phone, at most 40): with calls, they make Recents.
class RecentPeople {
  static const _k = 'recent_people';
  static const _max = 40;

  static Future<List<Map>> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_k);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).cast<Map>();
    } catch (_) {
      return const [];
    }
  }

  /// A page was opened (not your own).
  static Future<void> note(Profile u) async {
    final list = [
      {'uid': u.uid, 'handle': u.handle, 'name': u.name, 'company': u.company, 'userType': u.userType, 'photoURL': u.photoUrl, 'category': u.category, 'location': u.location, 'at': DateTime.now().millisecondsSinceEpoch},
      ...(await load()).where((m) => m['uid'] != u.uid),
    ].take(_max).toList();
    await (await SharedPreferences.getInstance()).setString(_k, jsonEncode(list));
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/reviews_card.dart' show kStar;
import 'profile.dart';

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

/// Favourites tab: starred contacts as large photos, three to a row, as in a phone's dialer.
class FavouritesScreen extends StatefulWidget {
  const FavouritesScreen({super.key});
  @override
  State<FavouritesScreen> createState() => _FavouritesScreenState();
}

class _FavouritesScreenState extends State<FavouritesScreen> {
  @override
  void initState() {
    super.initState();
    Favourites.load();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return ValueListenableBuilder<List<Map>>(
      valueListenable: Favourites.list,
      builder: (_, favs, __) => ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 140), children: [
        Text(t('Favourites'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        if (favs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(children: [
              Icon(Icons.star_outline_rounded, size: 56, color: kStar.withValues(alpha: .9)),
              const SizedBox(height: 12),
              Text(t('No favourites yet'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(t('Tap the star on a contact to keep them here, one tap away.'), textAlign: TextAlign.center, style: TextStyle(color: p.muted)),
            ]),
          )
        else
          LayoutBuilder(builder: (_, c) {
            final w = ((c.maxWidth - 24) / 3).clamp(0.0, double.infinity);
            return Wrap(spacing: 12, runSpacing: 18, children: [
              for (final m in favs)
                SizedBox(
                  width: w,
                  child: GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: '${m['handle']}'))),
                    child: Column(children: [
                      Avatar(name: displayName('${m['userType']}', '${m['name']}', '${m['company'] ?? ''}'), photoUrl: m['photoURL'] as String?, size: (w - 16).clamp(40.0, 96.0)),
                      const SizedBox(height: 6),
                      Text(displayName('${m['userType']}', '${m['name']}', '${m['company'] ?? ''}'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      if ('${m['category'] ?? ''}'.isNotEmpty) Text('${m['category']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: p.muted)),
                    ]),
                  ),
                ),
            ]);
          }),
      ]),
    );
  }
}

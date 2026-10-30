import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth_provider.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/reviews_card.dart';
import 'profile.dart';
import 'talk.dart';

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

/// The keypad: dial any number. Call uses the phone's own dialer; if the number has a WEBWEB page it shows who it
/// is, with a free in-app call and chat that keep your number private (POST /phonebook/lookup, nothing stored).
Future<void> showKeypad(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.of(context).canvas,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _Keypad(),
    );

class _Keypad extends StatefulWidget {
  const _Keypad();
  @override
  State<_Keypad> createState() => _KeypadState();
}

class _KeypadState extends State<_Keypad> {
  static const _keys = [('1', ''), ('2', 'ABC'), ('3', 'DEF'), ('4', 'GHI'), ('5', 'JKL'), ('6', 'MNO'), ('7', 'PQRS'), ('8', 'TUV'), ('9', 'WXYZ'), ('*', ''), ('0', '+'), ('#', '')];
  String _n = '';
  Map? _who;
  String? _looked;

  String get _ten {
    final d = _n.replaceAll(RegExp(r'\D'), '');
    return d.length >= 10 ? d.substring(d.length - 10) : '';
  }

  void _press(String k) {
    HapticFeedback.selectionClick();
    setState(() => _n += k);
    _lookup();
  }

  void _back() {
    if (_n.isEmpty) return;
    setState(() => (_n = _n.substring(0, _n.length - 1), _who = null));
  }

  Future<void> _lookup() async {
    final ten = _ten;
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(ten) || ten == _looked) return;
    _looked = ten;
    try {
      final r = await context.read<AuthProvider>().api.post('/phonebook/lookup', {'phone': ten}) as Map;
      if (mounted && _ten == ten) setState(() => _who = r['match'] as Map?);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final who = _who;
    final name = who == null ? '' : displayName('${who['userType']}', '${who['name']}', '${who['company'] ?? ''}');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // who it is, when the number has a page
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            child: who == null
                ? const SizedBox(height: 0, width: double.infinity)
                : InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: '${who['handle']}'))),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(16)),
                      child: Row(children: [
                        Avatar(name: name, photoUrl: who['photoURL'] as String?, size: 40),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(['${who['category'] ?? ''}', '${who['location'] ?? ''}'].where((s) => s.isNotEmpty).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted)),
                          ]),
                        ),
                        if (((who['reviews'] as num?) ?? 0) > 0) Stars(value: (who['rating'] as num).toDouble(), size: 11),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: t('Free call in the app'),
                          onPressed: () => placeCall(context, Peer.fromJson(who), false),
                          icon: const Icon(Icons.call_rounded, color: Color(0xFF1E9E5A)),
                        ),
                      ]),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: FittedBox(
              child: Text(_n.isEmpty ? ' ' : _n, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w500, letterSpacing: 0.75)),
            ),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.6,
            children: [
              for (final (d, l) in _keys)
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _press(d),
                  onLongPress: d == '0' ? () => _press('+') : null,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(d, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w500, height: 1)),
                    Text(l, style: TextStyle(fontSize: 10, letterSpacing: 0.6, color: p.muted)),
                  ]),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(children: [
            const Expanded(child: SizedBox()),
            // call with the phone's own dialer; the number is not sent anywhere
            GestureDetector(
              onTap: _n.isEmpty ? null : () => launchUrl(Uri(scheme: 'tel', path: _n)),
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: _n.isEmpty ? p.border : const Color(0xFF1E9E5A), shape: BoxShape.circle),
                child: Icon(Icons.call_rounded, color: Colors.white, size: 30, semanticLabel: t('Call')),
              ),
            ),
            Expanded(
              child: Align(
                child: IconButton(
                  onPressed: _n.isEmpty ? null : _back,
                  icon: Icon(Icons.backspace_outlined, color: p.muted, semanticLabel: t('Delete')),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

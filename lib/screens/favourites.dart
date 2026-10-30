import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth_provider.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/reviews_card.dart' show kStar;
import 'profile.dart';
import 'talk.dart' show callLabel, placeCall;

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

/// Recents, as in a phone's dialer: favourites as a row of photos, then each person you called, were called by or
/// whose page you opened lately, the latest first, with a call button.
class RecentsScreen extends StatefulWidget {
  const RecentsScreen({super.key});
  @override
  State<RecentsScreen> createState() => _RecentsScreenState();
}

/// one line of Recents: the person, and the latest thing that happened with them
class _Recent {
  final Peer peer;
  final DateTime at;
  final CallLog? call;
  final String sub;
  const _Recent(this.peer, this.at, this.call, this.sub);
}

class _RecentsScreenState extends State<RecentsScreen> {
  List<_Recent>? _list;

  @override
  void initState() {
    super.initState();
    Favourites.load();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final me = context.read<AuthProvider>().profile?.uid ?? '';
    final calls = await api.get('/app/calls').then((d) => (d as List).map((e) => CallLog.fromJson(e as Map)).toList()).catchError((_) => <CallLog>[]);
    final viewed = await RecentPeople.load();
    final byUid = <String, _Recent>{};
    void add(_Recent r) {
      final had = byUid[r.peer.uid];
      if (had == null || r.at.isAfter(had.at)) byUid[r.peer.uid] = r;
    }

    for (final c in calls) {
      if (c.peer != null) add(_Recent(c.peer!, c.createdAt, c, callLabel(c, me)));
    }
    for (final m in viewed) {
      add(_Recent(Peer.fromJson(m), DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()), null, [m['category'], m['location']].where((s) => '${s ?? ''}'.isNotEmpty).join(' · ')));
    }
    if (mounted) setState(() => _list = byUid.values.toList()..sort((a, b) => b.at.compareTo(a.at)));
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final me = context.read<AuthProvider>().profile?.uid ?? '';
    Widget label(String s) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Text(t(s).toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.25, color: p.muted)),
        );
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(16, 12, 16, 140), children: [
        Text(t('Recents'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
        // favourites, one tap away
        ValueListenableBuilder<List<Map>>(
          valueListenable: Favourites.list,
          builder: (_, favs, __) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            label('Favourites'),
            if (favs.isEmpty)
              Row(children: [
                const Icon(Icons.star_outline_rounded, color: kStar),
                const SizedBox(width: 8),
                Expanded(child: Text(t('Tap the star on a contact to keep them here, one tap away.'), style: TextStyle(fontSize: 13, color: p.muted))),
              ])
            else
              SizedBox(
                height: 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: favs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (_, i) {
                    final m = favs[i];
                    final name = displayName('${m['userType']}', '${m['name']}', '${m['company'] ?? ''}');
                    return GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: '${m['handle']}'))),
                      child: SizedBox(
                        width: 64,
                        child: Column(children: [
                          Avatar(name: name, photoUrl: m['photoURL'] as String?, size: 60),
                          const SizedBox(height: 6),
                          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    );
                  },
                ),
              ),
          ]),
        ),
        label('Recent'),
        if (_list == null)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
        else if (_list!.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(children: [
              WIcon(WI.clock, size: 44, color: p.muted),
              const SizedBox(height: 10),
              Text(t('No recent calls or contacts yet'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(t('People you call or whose page you open show here.'), textAlign: TextAlign.center, style: TextStyle(color: p.muted)),
            ]),
          )
        else
          for (final r in _list!) _row(p, r, me),
      ]),
    );
  }

  Widget _row(Pal p, _Recent r, String me) {
    final c = r.call;
    final outgoing = c != null && c.callerUid == me;
    final missed = c != null && !outgoing && c.status != 'completed';
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: r.peer.handle))),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border.withValues(alpha: .6)))),
        child: Row(children: [
          Avatar(name: r.peer.shownName, photoUrl: r.peer.photoUrl, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.peer.shownName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: missed ? p.danger : p.text)),
              const SizedBox(height: 2),
              Row(children: [
                WIcon(c == null ? WI.eye : (outgoing ? WI.callOut : (missed ? WI.callMissed : WI.callIn)), size: 14, color: c == null ? p.muted : (missed ? p.danger : const Color(0xFF1E9E5A))),
                const SizedBox(width: 4),
                Flexible(child: Text(c == null ? (r.sub.isEmpty ? t('Viewed their page') : r.sub) : t(r.sub), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: missed ? p.danger : p.muted))),
                Text(' · ${timeAgo(r.at)}', style: TextStyle(fontSize: 12, color: p.muted)),
              ]),
            ]),
          ),
          // a free call in the app, as from the dialer's recents
          IconButton(
            tooltip: t('Call'),
            onPressed: () => placeCall(context, r.peer, c?.video ?? false),
            icon: WIcon(c?.video == true ? WI.video : WI.phone, size: 22, color: const Color(0xFF1E9E5A)),
          ),
        ]),
      ),
    );
  }
}

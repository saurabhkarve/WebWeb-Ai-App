import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api.dart';
import 'auth_provider.dart';
import 'i18n.dart';
import 'theme.dart';
import 'widgets.dart';

/// Report, block and account deletion (Play Store user-generated-content policy).

const _reasons = ['Spam or scam', 'Harassment or abuse', 'Fake or misleading', 'Inappropriate content', 'Something else'];

/// Asks for a reason, then sends it to the moderators. [kind] is `user`, `post` or `message`.
Future<void> reportContent(BuildContext context, {required String kind, required String targetId, required String what}) async {
  final api = context.read<AuthProvider>().api;
  final reason = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 6), child: Align(alignment: Alignment.centerLeft, child: Text('Report $what', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)))),
        for (final r in _reasons) ListTile(title: Text(r), onTap: () => Navigator.pop(ctx, r)),
      ]),
    ),
  );
  if (reason == null || !context.mounted) return;
  try {
    await api.post('/app/report', {'kind': kind, 'targetId': targetId, 'reason': reason});
    if (context.mounted) toast(context, 'Thanks, we will review this.');
  } catch (e) {
    if (context.mounted) toast(context, '$e', error: true);
  }
}

/// Confirms, then blocks [uid]. Returns true when the person was blocked.
Future<bool> blockUser(BuildContext context, {required String uid, required String name}) async {
  final api = context.read<AuthProvider>().api;
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Block $name?'),
      content: Text('$name will not be able to message you, and you will not see their asks. You can unblock from Profile > Blocked people.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Block', style: TextStyle(color: Colors.redAccent))),
      ],
    ),
  );
  if (yes != true || !context.mounted) return false;
  try {
    await api.post('/app/blocks', {'uid': uid});
    if (context.mounted) toast(context, '$name blocked');
    return true;
  } catch (e) {
    if (context.mounted) toast(context, '$e', error: true);
    return false;
  }
}

/// "Report or block" sheet for a person (optionally from one of their asks). Returns true when they were blocked.
/// [saved] + [onToggleSave]: a Save / Remove from saved row on top (the ⋯ under someone else's ask); [onAlert]:
/// "Alert me for similar asks" under it.
Future<bool> showSafetySheet(BuildContext context, {required String uid, required String name, String? postId, bool? saved, VoidCallback? onToggleSave, VoidCallback? onAlert}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (onToggleSave != null)
          ListTile(
            leading: WIcon(WI.bookmark, size: 20, color: Pal.of(ctx).text, fill: saved == true),
            title: Text(t(saved == true ? 'Remove from saved' : 'Save ask')),
            onTap: () => Navigator.pop(ctx, 'save'),
          ),
        if (onAlert != null) ListTile(leading: WIcon(WI.bell, size: 20, color: Pal.of(ctx).text), title: Text(t('Alert me for similar asks')), onTap: () => Navigator.pop(ctx, 'alert')),
        // saving is for you; what follows reports or blocks
        if (onToggleSave != null || onAlert != null) Divider(height: 1, color: Pal.of(ctx).border),
        if (postId != null) ListTile(leading: const Icon(Icons.flag_outlined), title: const Text('Report this ask'), onTap: () => Navigator.pop(ctx, 'post')),
        ListTile(leading: const Icon(Icons.flag_outlined), title: Text('Report $name'), onTap: () => Navigator.pop(ctx, 'user')),
        ListTile(leading: const Icon(Icons.block, color: Colors.redAccent), title: Text('Block $name', style: const TextStyle(color: Colors.redAccent)), onTap: () => Navigator.pop(ctx, 'block')),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return false;
  if (choice == 'save') {
    onToggleSave?.call();
  } else if (choice == 'alert') {
    onAlert?.call();
  } else if (choice == 'post') {
    await reportContent(context, kind: 'post', targetId: postId!, what: 'this ask');
  } else if (choice == 'user') {
    await reportContent(context, kind: 'user', targetId: uid, what: name);
  } else {
    return blockUser(context, uid: uid, name: name);
  }
  return false;
}

/// UIDs I have blocked (empty when the request fails).
Future<Set<String>> loadBlocked(Api api) async {
  try {
    final d = await api.get('/app/blocks') as List;
    return {for (final e in d) (e as Map)['uid'] as String};
  } catch (_) {
    return {};
  }
}

/// Confirms, deletes the account on the server, then signs out.
Future<void> deleteAccount(BuildContext context) async {
  final auth = context.read<AuthProvider>();
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete your account?'),
      content: const Text('This permanently removes your profile, asks, catalog, chats and responses. This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete forever', style: TextStyle(color: Colors.redAccent))),
      ],
    ),
  );
  if (yes != true || !context.mounted) return;
  try {
    await auth.api.delete('/app/me');
    await auth.logout();
  } catch (e) {
    if (context.mounted) toast(context, '$e', error: true);
  }
}

/// Blocked people, with an unblock button each.
class BlockedPeopleScreen extends StatefulWidget {
  const BlockedPeopleScreen({super.key});
  @override
  State<BlockedPeopleScreen> createState() => _BlockedPeopleScreenState();
}

class _BlockedPeopleScreenState extends State<BlockedPeopleScreen> {
  List<Map>? _items;

  Api get _api => context.read<AuthProvider>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _api.get('/app/blocks') as List;
      if (mounted) setState(() => _items = d.cast<Map>());
    } catch (_) {
      if (mounted) setState(() => _items = []);
    }
  }

  Future<void> _unblock(Map m) async {
    try {
      await _api.delete('/app/blocks/${m['uid']}');
      await _load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked people')),
      body: _items == null
          ? const PageLoader()
          : _items!.isEmpty
              ? Center(child: Text('You have not blocked anyone.', style: TextStyle(color: p.muted)))
              : ListView(children: [
                  for (final m in _items!)
                    ListTile(
                      leading: Avatar(name: '${m['name']}', photoUrl: m['photoURL'] as String?, size: 40),
                      title: Text('${m['name']}'),
                      subtitle: Text('${m['company'] ?? ''}'),
                      trailing: TextButton(onPressed: () => _unblock(m), child: const Text('Unblock')),
                    ),
                ]),
    );
  }
}

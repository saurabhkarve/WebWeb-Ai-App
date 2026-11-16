import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/city_picker.dart';
import 'profile.dart';

/// True while someone is browsing without an account (see [AuthProvider.guest]).
bool isGuest(BuildContext context) {
  final auth = context.read<AuthProvider>();
  return !auth.isLoggedIn && auth.guest;
}

/// Something that needs an account was tapped while browsing: say so, and offer the sign-in screen.
/// Returns true when the person is signed in (nothing to do).
bool needsSignIn(BuildContext context) {
  if (!isGuest(context)) return false;
  final p = Pal.of(context);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: p.canvas,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('Sign in to continue'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(t('Talking, calling, asks and your own free page need an account. Sign in with your mobile number; it takes a minute.'),
              style: const TextStyle(fontSize: 14, height: 1.45)),
          const SizedBox(height: 18),
          GoldButton(
            label: t('Sign in'),
            onPressed: () {
              Navigator.of(ctx).popUntil((r) => r.isFirst);
              ctx.read<AuthProvider>().endGuest();
            },
          ),
          const SizedBox(height: 4),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Keep browsing'))),
        ]),
      ),
    ),
  );
  return true;
}

/// The app without an account: search businesses and people on WEBWEB (by words and place) and open their public
/// pages, the same pages the website shows a visitor (no phone numbers). Location is never needed: the place is picked.
class GuestHome extends StatefulWidget {
  const GuestHome({super.key});
  @override
  State<GuestHome> createState() => _GuestHomeState();
}

class _GuestHomeState extends State<GuestHome> {
  final _q = TextEditingController();
  Timer? _debounce;
  String _place = '';
  List<Profile>? _results;
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final mine = ++_seq;
    setState(() => _error = null);
    try {
      final d = await context.read<AuthProvider>().api.get('/public/search', {
        if (_q.text.trim().length >= 2) 'q': _q.text.trim(),
        if (_place.isNotEmpty) 'place': _place,
      });
      if (!mounted || mine != _seq) return;
      setState(() => _results = (d as List).map((e) => Profile.fromJson(e as Map)).toList());
    } catch (e) {
      if (mounted && mine == _seq) setState(() => _error = '$e');
    }
  }

  void _typed(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final auth = context.read<AuthProvider>();
    final results = _results;
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: CustomScrollView(slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      const Expanded(child: Text('WEBWEB', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: .5))),
                      SizedBox(width: 110, child: GoldButton(label: t('Sign in'), height: 40, onPressed: auth.endGuest)),
                    ]),
                    const SizedBox(height: 18),
                    Text(t('Find businesses and people'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2)),
                    const SizedBox(height: 6),
                    Text(t('Search by what they do or their name, and open their page. Sign in to talk, call or get your own free page.'),
                        style: TextStyle(fontSize: 14, color: p.muted, height: 1.4)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _q,
                      onChanged: _typed,
                      onSubmitted: (_) => _search(),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: t('Plumber, printer, tutor…'),
                        prefixIcon: Padding(padding: const EdgeInsets.all(12), child: WIcon(WI.search, size: 20, color: p.muted)),
                        filled: true,
                        fillColor: p.card,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide(color: p.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide(color: p.border)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: CityPill(
                        value: _place,
                        anyLabel: t('Any location'),
                        chip: true,
                        onChanged: (c) {
                          setState(() => _place = c.name);
                          _search();
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                  ]),
                ),
              ),
              if (_error != null && results == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(t('Could not load. Check your connection.'), style: TextStyle(color: p.muted)),
                      const SizedBox(height: 10),
                      SizedBox(width: 160, child: GoldButton(label: t('Try again'), height: 40, onPressed: _search)),
                    ]),
                  ),
                )
              else if (results == null)
                const SliverFillRemaining(hasScrollBody: false, child: Center(child: LogoLoader()))
              else if (results.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text(t('No pages found. Try other words or another place.'), style: TextStyle(color: p.muted))),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: results.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: p.border),
                    itemBuilder: (_, i) => _Row(results[i]),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final Profile u;
  const _Row(this.u);
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final name = displayName(u.userType, u.name, u.company);
    final line = [t(labelOf(kProfileCategories, u.category)), u.location].where((e) => e.isNotEmpty).join(' · ');
    return InkWell(
      onTap: () => Navigator.push(context, WideRoute(builder: (_) => ProfileScreen(handle: u.handle))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          Avatar(name: name, photoUrl: u.photoUrl, size: 48, type: u.userType),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                const SizedBox(width: 4),
                VerifiedBadge(level: u.verification, premium: u.premium, plan: u.plan),
              ]),
              if (line.isNotEmpty) Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: p.muted)),
            ]),
          ),
          WIcon(WI.chevronRight, size: 18, color: p.muted),
        ]),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../models.dart';
import '../realtime.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/post_card.dart';
import 'profile.dart';
import 'talk.dart' show openChat;

/// Find tab: search businesses, products & services, jobs, asks and people (GET /app/search).
class FindScreen extends StatefulWidget {
  const FindScreen({super.key});
  @override
  State<FindScreen> createState() => _FindScreenState();
}

class _FindScreenState extends State<FindScreen> {
  static const _types = {'all': 'All', 'businesses': 'Businesses', 'products': 'Products & Services', 'jobs': 'Jobs', 'asks': 'Asks', 'people': 'People'};
  final _q = TextEditingController();
  String _type = 'all';
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  String? _error;
  Timer? _debounce;

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
    setState(() {});
  }

  Future<void> _search() async {
    final q = _q.text.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final d = await context.read<AuthProvider>().api.get('/app/search', {'q': q, 'type': _type}) as List;
      if (!mounted || _q.text.trim() != q) return;
      setState(() {
        _results = d.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return SafeArea(
      bottom: false,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: _SearchBox(controller: _q, hint: 'Search businesses, jobs, people, asks', onChanged: _onChanged, onClear: () {
            _q.clear();
            _search();
          }),
        ),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            for (final e in _types.entries)
              Padding(padding: const EdgeInsets.only(right: 8), child: FilterPill(label: e.value, selected: _type == e.key, onTap: () {
                setState(() => _type = e.key);
                _search();
              })),
          ]),
        ),
        Expanded(
          child: _q.text.trim().isEmpty
              ? Padding(padding: const EdgeInsets.all(28), child: Align(alignment: Alignment.topCenter, child: Text('Type a name, skill, product, area or industry, for example “CNC”, “Vashi” or “driver”.', textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontWeight: FontWeight.w500, height: 1.4))))
              : _loading && _results.isEmpty
                  ? const PageLoader()
                  : _error != null
                      ? Center(child: Text(_error!, style: TextStyle(color: p.muted)))
                      : _results.isEmpty
                          ? Center(child: Text('No results for “${_q.text.trim()}”', style: TextStyle(color: p.muted, fontWeight: FontWeight.w600)))
                          : ListView.builder(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), itemCount: _results.length, itemBuilder: (_, i) => _tile(_results[i])),
        ),
      ]),
    );
  }

  Widget _tile(Map<String, dynamic> r) {
    final p = Pal.of(context);
    if (r['kind'] == 'post') return PostCard(post: Post.fromJson(r['post'] as Map));
    final isProduct = r['kind'] == 'product';
    final u = Profile.fromJson((isProduct ? r['owner'] : r['user']) as Map);
    final item = isProduct ? Product.fromJson(r['item'] as Map) : null;
    final me = context.read<AuthProvider>().profile?.uid;
    final online = context.watch<RealtimeService>().isOnline(u.uid);
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: u.handle))),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border.withValues(alpha: .6)))),
        child: Row(children: [
          if (isProduct) NetImage(item!.imageUrl, size: 52, fallback: Icons.inventory_2_outlined) else Avatar(name: u.name, photoUrl: u.photoUrl, ring: u.isEntrepreneur, type: u.userType),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (isProduct) ...[
                Text(item!.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                if ((item.price ?? '').isNotEmpty) Text(item.price!, style: const TextStyle(color: kGold, fontWeight: FontWeight.w700)),
                Text('${item.kind == 'service' ? 'Service' : 'Product'} by ${u.company} · ${u.location}', style: TextStyle(color: p.muted, fontSize: 13)),
              ] else ...[
                Row(children: [
                  Flexible(child: Text(u.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                  if (online) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.circle, size: 9, color: kGreen)),
                ]),
                Text('@${u.handle} · ${u.company}', overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 13)),
                Text('${u.location} · ${u.category}', overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12.5)),
              ],
            ]),
          ),
          if (u.uid != me) IconButton(tooltip: 'Message', icon: const Icon(Icons.chat_bubble_outline, color: kGold), onPressed: () => openChat(context, Peer.fromProfile(u))),
        ]),
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  const _SearchBox({required this.controller, required this.hint, required this.onChanged, required this.onClear});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: p.field, borderRadius: BorderRadius.circular(30)),
      child: Row(children: [
        Icon(Icons.search, color: p.muted),
        const SizedBox(width: 10),
        Expanded(child: TextField(controller: controller, onChanged: onChanged, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15.5), decoration: InputDecoration(hintText: hint, hintStyle: TextStyle(color: p.muted), border: InputBorder.none, isDense: true))),
        if (controller.text.isNotEmpty) GestureDetector(onTap: onClear, child: Icon(Icons.close, size: 20, color: p.muted)),
      ]),
    );
  }
}

/// Pill used for filters, categories and segmented controls (selected = cream).
class FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  const FilterPill({super.key, required this.label, required this.selected, required this.onTap, this.icon});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: selected ? p.selected : p.chip, borderRadius: BorderRadius.circular(24)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 16, color: selected ? p.onSelected : p.muted), const SizedBox(width: 6)],
          Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: selected ? p.onSelected : p.muted)),
        ]),
      ),
    );
  }
}

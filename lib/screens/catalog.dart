import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../auth_provider.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// Manage my products & services (GET /users/:id/products, POST/PATCH/DELETE /me/products).
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  List<Product>? _items;
  Api get _api => context.read<AuthProvider>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final uid = context.read<AuthProvider>().profile!.uid;
      final d = await _api.get('/users/$uid/products') as List;
      if (mounted) setState(() => _items = d.map((e) => Product.fromJson(e as Map)).toList());
    } catch (e) {
      if (mounted) {
        setState(() => _items = []);
        toast(context, '$e', error: true);
      }
    }
  }

  Future<void> _edit([Product? p]) async {
    if (await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => _ItemSheet(item: p)) == true) _load();
  }

  Future<void> _delete(Product p) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${p.name}?'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.redAccent)))],
      ),
    );
    if (yes != true) return;
    try {
      await _api.delete('/me/products/${p.id}');
      _load();
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Manage catalog', style: TextStyle(fontWeight: FontWeight.w700))),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), backgroundColor: kGold, foregroundColor: const Color(0xFF1E1E1E), icon: const Icon(Icons.add), label: const Text('Add item', style: TextStyle(fontWeight: FontWeight.w700))),
      body: _items == null
          ? const PageLoader()
          : _items!.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Text('No items yet. Add your first product or service.', textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontWeight: FontWeight.w500))))
              : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                  for (final it in _items!)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
                      child: Row(children: [
                        NetImage(it.imageUrl, size: 56, fallback: Icons.inventory_2_outlined),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text('${it.kind == 'service' ? 'Service' : 'Product'}${(it.price ?? '').isEmpty ? '' : ' · ${it.price}'}${it.available ? '' : ' · Unavailable'}', style: TextStyle(color: p.muted, fontSize: 12.5)),
                        ])),
                        IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(it)),
                        IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => _delete(it)),
                      ]),
                    ),
                ]),
    );
  }
}

class _ItemSheet extends StatefulWidget {
  final Product? item;
  const _ItemSheet({this.item});
  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _price = TextEditingController(text: widget.item?.price ?? '');
  late final _desc = TextEditingController(text: widget.item?.description ?? '');
  late String _kind = widget.item?.kind ?? 'product';
  late bool _available = widget.item?.available ?? true;
  String? _image;
  bool _busy = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _image = widget.item?.imageUrl;
  }

  Future<void> _pick() async {
    final api = context.read<AuthProvider>().api;
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1024, imageQuality: 75);
    if (f == null) return;
    setState(() => _uploading = true);
    try {
      final url = await api.uploadImage(await f.readAsBytes(), f.name);
      if (mounted) setState(() => _image = url);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final api = context.read<AuthProvider>().api;
    setState(() => _busy = true);
    try {
      final body = {'name': _name.text.trim(), 'kind': _kind, 'price': _price.text.trim(), 'description': _desc.text.trim(), 'available': _available, if (_image != null) 'imageUrl': _image};
      widget.item == null ? await api.post('/me/products', body) : await api.patch('/me/products/${widget.item!.id}', body);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, '$e', error: true);
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _price, _desc]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.item == null ? 'Add item' : 'Edit item', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Row(children: [
            GestureDetector(onTap: _uploading ? null : _pick, child: Stack(alignment: Alignment.center, children: [NetImage(_image, size: 72, fallback: Icons.add_photo_alternate_outlined), if (_uploading) const LogoLoader(size: 28)])),
            const SizedBox(width: 14),
            Expanded(child: Row(children: [
              for (final k in const [('product', 'Product'), ('service', 'Service')])
                Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(k.$2), selected: _kind == k.$1, onSelected: (_) => setState(() => _kind = k.$1))),
            ])),
          ]),
          const SizedBox(height: 14),
          AppField(controller: _name, label: 'Name *', maxLength: 80, onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          AppField(controller: _price, label: 'Price', hint: 'e.g. ₹18 / box', maxLength: 40),
          const SizedBox(height: 12),
          AppField(controller: _desc, label: 'Description', maxLines: 3, maxLength: 300),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: Text('Available', style: TextStyle(color: p.text, fontWeight: FontWeight.w600)), value: _available, activeColor: kGold, onChanged: (v) => setState(() => _available = v)),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: GoldButton(label: 'Save', loading: _busy, onPressed: _name.text.trim().length >= 2 ? _save : null)),
        ]),
      ),
    );
  }
}

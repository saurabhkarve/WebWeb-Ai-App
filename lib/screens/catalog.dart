import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../auth_provider.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

const _emerald = Color(0xFF047857);
const _emeraldDark = Color(0xFF34D399);

class _Cat {
  final String name;
  final int count;
  const _Cat(this.name, this.count);
}

Product _with(Product p, {bool? available, String? category, bool clearCategory = false}) => Product(
      id: p.id,
      name: p.name,
      kind: p.kind,
      available: available ?? p.available,
      price: p.price,
      description: p.description,
      imageUrl: p.imageUrl,
      category: clearCategory ? null : (category ?? p.category),
    );

Future<T?> _sheet<T>(BuildContext context, Widget child) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.of(context).canvas,
      barrierColor: kInk.withValues(alpha: .6),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => child,
    );

/// Manage the catalog shown on your free website (web profile/catalog): add, edit, hide, reorder,
/// categorise and delete products and services.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  List<Product>? _items;
  List<_Cat> _cats = [];
  String _filter = 'all'; // all product service
  String _catFilter = 'all'; // all, none (uncategorised) or a category name
  String? _confirmId;
  String? _error;

  Api get _api => context.read<AuthProvider>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = context.read<AuthProvider>().profile?.uid;
    if (uid == null) return;
    try {
      final d = await _api.get('/users/$uid/products') as List;
      if (mounted) setState(() => _items = d.map((e) => Product.fromJson(e as Map)).toList());
    } catch (_) {
      if (mounted) setState(() => _items = []);
    }
    try {
      final c = await _api.get('/me/product-categories') as List;
      if (mounted) setState(() => _cats = [for (final e in c.cast<Map>()) _Cat('${e['name']}', (e['count'] as num?)?.toInt() ?? 0)]);
    } catch (_) {}
  }

  List<Product> get _shown => (_items ?? [])
      .where((p) =>
          (_filter == 'all' || p.kind == _filter) &&
          (_catFilter == 'all' || (_catFilter == 'none' ? p.category == null : p.category?.toLowerCase() == _catFilter.toLowerCase())))
      .toList();

  Future<void> _guard(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : '$e');
      _load();
    }
  }

  void _replace(Product next) => setState(() => _items = [for (final x in _items ?? <Product>[]) x.id == next.id ? next : x]);

  Future<void> _toggle(Product p) async {
    _replace(_with(p, available: !p.available));
    await _guard(() async => _api.patch('/me/products/${p.id}', {'available': !p.available}));
  }

  Future<void> _move(Product p, int dir) async {
    final items = [...?_items];
    final i = items.indexWhere((x) => x.id == p.id);
    final j = i + dir;
    if (i < 0 || j < 0 || j >= items.length) return;
    final tmp = items[i];
    items[i] = items[j];
    items[j] = tmp;
    setState(() => _items = items);
    await _guard(() async => _api.put('/me/products/order', {'ids': items.map((x) => x.id).toList()}));
  }

  Future<void> _setCategory(Product p, String? category) async {
    _replace(_with(p, category: category, clearCategory: category == null));
    await _guard(() async {
      await _api.patch('/me/products/${p.id}', {'category': category});
      _load();
    });
  }

  Future<void> _remove(String id) async {
    setState(() {
      _items = _items?.where((x) => x.id != id).toList();
      _confirmId = null;
    });
    await _guard(() async => _api.delete('/me/products/$id'));
  }

  Future<void> _openItem([Product? item]) async {
    final saved = await _sheet<bool>(context, _ItemSheet(item: item, categories: _cats.map((c) => c.name).toList()));
    if (saved == true) _load();
  }

  Future<void> _manage() async {
    await _sheet(context, _CategoryManager(categories: _cats, onChanged: () async {
      setState(() => _catFilter = 'all');
      await _load();
    }));
  }

  Future<void> _pick(Product p) async {
    final r = await _sheet<(String?,)>(context, _CategoryPicker(title: p.name, current: p.category, categories: _cats));
    if (r != null) _setCategory(p, r.$1);
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final items = _items;
    final products = items?.where((x) => x.kind == 'product').length ?? 0;
    final services = items?.where((x) => x.kind == 'service').length ?? 0;
    final shown = _shown;

    Widget seg(String id, String label) => Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _filter = id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: _filter == id ? p.ink : Colors.transparent, borderRadius: BorderRadius.circular(18)),
              child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _filter == id ? p.onInk : p.muted)),
            ),
          ),
        );

    Widget catChip(String id, String label) => GestureDetector(
          onTap: () => setState(() => _catFilter = id),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: _catFilter == id ? p.ink : p.chip, borderRadius: BorderRadius.circular(18)),
            child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _catFilter == id ? p.onInk : p.muted)),
          ),
        );

    return SubPage(
      title: t('Catalog'),
      body: LogoRefresh(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 32),
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('Your catalog'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.25)),
                  Text('$products products · $services services. Visitors see this first on your page.', style: TextStyle(fontSize: 14, color: p.muted, height: 1.25)),
                ]),
              ),
              const SizedBox(width: 12),
              SizedBox(width: 84, child: GoldButton(label: t('Add'), wi: WI.plus, height: 32, onPressed: () => _openItem())),
            ]),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: p.canvas.withValues(alpha: .9), borderRadius: BorderRadius.circular(30), border: Border.all(color: p.border.withValues(alpha: .7))),
              child: Row(children: [
                seg('all', '${t('All')} ${items?.length ?? 0}'),
                const SizedBox(width: 4),
                seg('product', '${t('Products')} $products'),
                const SizedBox(width: 4),
                seg('service', '${t('Services')} $services'),
              ]),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 36,
              child: ListView(scrollDirection: Axis.horizontal, clipBehavior: Clip.none, children: [
                GestureDetector(
                  onTap: _manage,
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: p.border)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      WIcon(WI.tag, size: 16, color: p.text),
                      const SizedBox(width: 6),
                      Text(t('Categories'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
                if (_cats.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  catChip('all', t('All categories')),
                  for (final c in _cats) ...[const SizedBox(width: 8), catChip(c.name, '${c.name} ${c.count}')],
                  if ((items ?? []).any((x) => x.category == null)) ...[const SizedBox(width: 8), catChip('none', t('Uncategorised'))],
                ],
              ]),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(fontSize: 14, color: p.danger))),
            if (items == null)
              const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: LogoLoader())),
            if (items != null && items.isEmpty) EmptyState(title: t('Your catalog is empty'), hint: t('Add what you sell or the services you offer.')),
            if (items != null && items.isNotEmpty && shown.isEmpty) EmptyState(title: t('Nothing in this filter')),
            const SizedBox(height: 4),
            for (var k = 0; k < shown.length; k++) _row(shown[k], k == 0, p),
          ],
        ),
      ),
    );
  }

  Widget _row(Product it, bool first, Pal pal) {
    final items = _items!;
    final index = items.indexWhere((x) => x.id == it.id);
    final confirming = _confirmId == it.id;
    Widget arrow(String glyph, bool enabled, VoidCallback onTap) => GestureDetector(
          onTap: enabled ? onTap : null,
          child: Opacity(
            opacity: enabled ? 1 : .25,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), child: Text(glyph, style: TextStyle(fontSize: 13, color: pal.muted))),
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: first ? null : BoxDecoration(border: Border(top: BorderSide(color: pal.border))),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 64,
            height: 64,
            color: pal.chip,
            child: (it.imageUrl ?? '').isNotEmpty
                ? Opacity(opacity: it.available ? 1 : .4, child: NetImg(it.imageUrl!, width: 64, height: 64, fit: BoxFit.cover))
                : Center(child: WIcon(it.kind == 'service' ? WI.service : WI.box, size: 24, color: pal.muted)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              it.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: it.available ? pal.text : pal.muted,
                decoration: it.available ? null : TextDecoration.lineThrough,
              ),
            ),
            Text('${it.kind == 'service' ? 'Service' : 'Product'}${(it.price ?? '').isEmpty ? '' : ' · ${it.price}'}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: pal.muted)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              GestureDetector(
                onTap: () => _pick(it),
                child: _DashedPill(
                  dashed: it.category == null,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    WIcon(WI.tag, size: 12, color: it.category == null ? pal.muted : pal.text),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(it.category ?? t('Add category'),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: it.category == null ? pal.muted : pal.text)),
                    ),
                  ]),
                ),
              ),
              GestureDetector(
                onTap: () => _toggle(it),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: it.available ? const Color(0xFF059669).withValues(alpha: .1) : pal.chip,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(it.available ? 'Available' : 'Unavailable',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: it.available ? (pal.dark ? _emeraldDark : _emerald) : pal.muted)),
                ),
              ),
            ]),
          ]),
        ),
        if (confirming)
          Column(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              onTap: () => _remove(it.id),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: pal.danger, borderRadius: BorderRadius.circular(16)),
                child: Text(t('Delete'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(width: 76, child: GoldButton(label: t('Keep'), height: 32, outlined: true, onPressed: () => setState(() => _confirmId = null))),
          ])
        else
          Row(mainAxisSize: MainAxisSize.min, children: [
            Column(mainAxisSize: MainAxisSize.min, children: [
              arrow('▲', _filter == 'all' && index > 0, () => _move(it, -1)),
              arrow('▼', _filter == 'all' && index < items.length - 1, () => _move(it, 1)),
            ]),
            InkResponse(onTap: () => _openItem(it), radius: 20, child: Padding(padding: const EdgeInsets.all(8), child: WIcon(WI.edit, size: 20, color: pal.text))),
            InkResponse(onTap: () => setState(() => _confirmId = it.id), radius: 20, child: Padding(padding: const EdgeInsets.all(8), child: WIcon(WI.trash, size: 20, color: pal.danger))),
          ]),
      ]),
    );
  }
}

/// Round pill with a solid border, or a dashed one when empty ("Add category").
class _DashedPill extends StatelessWidget {
  final bool dashed;
  final Widget child;
  const _DashedPill({required this.dashed, required this.child});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final inner = Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2), child: child);
    if (!dashed) {
      return Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: p.border)), child: inner);
    }
    return DashedBox(radius: 20, padding: EdgeInsets.zero, color: p.border, child: inner);
  }
}

// ---------- add / edit one item (web catalog-item-sheet) ----------

class _ItemSheet extends StatefulWidget {
  final Product? item;
  final List<String> categories;
  const _ItemSheet({this.item, this.categories = const []});
  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _price = TextEditingController(text: widget.item?.price ?? '');
  late final _desc = TextEditingController(text: widget.item?.description ?? '');
  late final _category = TextEditingController(text: widget.item?.category ?? '');
  late String _kind = widget.item?.kind ?? 'product';
  late bool _available = widget.item?.available ?? true;
  late String? _image = widget.item?.imageUrl;
  bool _busy = false;
  bool _uploading = false;
  String? _error;

  Future<void> _pick() async {
    final api = context.read<AuthProvider>().api;
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 82);
    if (f == null) return;
    setState(() => _uploading = true);
    try {
      final url = await api.uploadImage(await f.readAsBytes(), f.name);
      if (mounted) setState(() => _image = url);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final api = context.read<AuthProvider>().api;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? v(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    try {
      final body = {'name': _name.text.trim(), 'kind': _kind, 'available': _available};
      if (widget.item == null) {
        await api.post('/me/products', {
          ...body,
          if (v(_price) != null) 'price': v(_price),
          if (v(_category) != null) 'category': v(_category),
          if (v(_desc) != null) 'description': v(_desc),
          if (_image != null) 'imageUrl': _image,
        });
      } else {
        await api.patch('/me/products/${widget.item!.id}', {...body, 'price': v(_price), 'category': v(_category), 'description': v(_desc), 'imageUrl': _image});
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : 'Could not save.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _price, _desc, _category]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final has = (_image ?? '').isNotEmpty;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .92),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(widget.item == null ? 'Add to catalog' : 'Edit item', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            GestureDetector(onTap: () => Navigator.pop(context), child: WIcon(WI.close, size: 24, color: p.text)),
          ]),
          const SizedBox(height: 16),
          _Segmented(value: _kind, options: const [('product', 'Product'), ('service', 'Service')], onChanged: (k) => setState(() => _kind = k)),
          const SizedBox(height: 16),
          Row(children: [
            GestureDetector(
              onTap: _uploading ? null : _pick,
              child: DashedBox(
                radius: 8,
                padding: EdgeInsets.zero,
                color: p.border,
                child: SizedBox(
                  width: 96,
                  height: 96,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(fit: StackFit.expand, children: [
                      if (has) NetImg(_image!, fit: BoxFit.cover) else Center(child: WIcon(WI.imageAdd, size: 28, color: p.muted)),
                      if (_uploading) const Center(child: LogoLoader(size: 28)),
                    ]),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              GestureDetector(onTap: _uploading ? null : _pick, child: Text(has ? 'Change photo' : 'Add a photo', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
              if (has)
                GestureDetector(
                  onTap: () => setState(() => _image = null),
                  child: Text('Remove', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.danger)),
                ),
            ]),
          ]),
          const SizedBox(height: 16),
          AppField(controller: _name, label: _kind == 'service' ? 'Service name *' : 'Product name *', maxLength: 80, onChanged: (_) => setState(() {})),
          const SizedBox(height: 16),
          AppField(controller: _category, label: t('Category'), helper: t('Groups your catalog into filters, e.g. Packaging, Printing'), maxLength: 30),
          if (widget.categories.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in widget.categories)
                GestureDetector(
                  onTap: () => setState(() => _category.text = c),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(20)),
                    child: Text(c, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted)),
                  ),
                ),
            ]),
          ],
          const SizedBox(height: 16),
          AppField(controller: _price, label: t('Price'), helper: t('Free text, e.g. ₹450 / kg, From ₹5,000, On request'), maxLength: 40),
          const SizedBox(height: 16),
          AppField(controller: _desc, label: t('Description'), maxLines: 3, maxLength: 300, caps: TextCapitalization.sentences),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => setState(() => _available = !_available),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t('Available'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.25)),
                    Text(t('Turn off when out of stock or paused'), style: TextStyle(fontSize: 12, color: p.muted, height: 1.25)),
                  ]),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: _available ? p.ink : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _available ? p.ink : p.border, width: 1.5),
                  ),
                  child: _available ? WIcon(WI.check, size: 16, strokeWidth: 2.4, color: p.onInk) : null,
                ),
              ]),
            ),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(fontSize: 14, color: p.danger))),
          const SizedBox(height: 16),
          GoldButton(label: widget.item == null ? 'Add to catalog' : 'Save changes', wi: WI.box, loading: _busy, onPressed: _name.text.trim().length >= 2 && !_uploading ? _save : null),
        ]),
      ),
    );
  }
}

/// The web Segmented control: pill track, the chosen option filled with ink.
class _Segmented extends StatelessWidget {
  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;
  const _Segmented({required this.value, required this.options, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: p.canvas.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: p.border.withValues(alpha: .7)),
        boxShadow: [BoxShadow(color: kInk.withValues(alpha: .3), blurRadius: 30, spreadRadius: -10, offset: const Offset(0, 8))],
      ),
      child: Row(children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(options[i].$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: value == options[i].$1 ? p.ink : Colors.transparent, borderRadius: BorderRadius.circular(22)),
                child: Text(t(options[i].$2), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: value == options[i].$1 ? p.onInk : p.muted)),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

// ---------- categories (web category-manager) ----------

class _CategoryManager extends StatefulWidget {
  final List<_Cat> categories;
  final Future<void> Function() onChanged;
  const _CategoryManager({required this.categories, required this.onChanged});
  @override
  State<_CategoryManager> createState() => _CategoryManagerState();
}

class _CategoryManagerState extends State<_CategoryManager> {
  late List<_Cat> _cats = widget.categories;
  final _name = TextEditingController();
  final _draft = TextEditingController();
  String? _editing;
  String? _confirm;
  bool _busy = false;
  String? _error;

  Api get _api => context.read<AuthProvider>().api;

  Future<void> _run(Future<void> Function() fn) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await fn();
      await widget.onChanged();
      final c = await _api.get('/me/product-categories') as List;
      if (mounted) setState(() => _cats = [for (final e in c.cast<Map>()) _Cat('${e['name']}', (e['count'] as num?)?.toInt() ?? 0)]);
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : 'Could not save.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    Widget small(String label, VoidCallback? onTap, {bool danger = false, bool secondary = false}) => GestureDetector(
          onTap: onTap,
          child: Opacity(
            opacity: onTap == null ? .5 : 1,
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: danger || secondary ? null : kGoldGradient,
                color: danger ? p.danger : (secondary ? p.chip : null),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: danger ? Colors.white : (secondary ? p.text : kInk))),
            ),
          ),
        );
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .85),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            WIcon(WI.tag, size: 20, color: p.text),
            const SizedBox(width: 8),
            Expanded(child: Text(t('Manage categories'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            GestureDetector(onTap: () => Navigator.pop(context), child: WIcon(WI.close, size: 24, color: p.text)),
          ]),
          const SizedBox(height: 12),
          Text(t('Group your products and services. Visitors can filter your page by category.'), style: TextStyle(fontSize: 14, color: p.muted)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: AppField(controller: _name, hint: t('New category'), maxLength: 30, onChanged: (_) => setState(() {}))),
            const SizedBox(width: 8),
            SizedBox(
              width: 84,
              child: GoldButton(
                label: t('Add'),
                wi: WI.plus,
                height: 40,
                onPressed: _name.text.trim().isEmpty || _busy
                    ? null
                    : () => _run(() async {
                          await _api.post('/me/product-categories', {'name': _name.text.trim()});
                          _name.clear();
                        }),
              ),
            ),
          ]),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(fontSize: 14, color: p.danger))),
          const SizedBox(height: 4),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              if (_cats.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Text(t('No categories yet.'), textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: p.muted))),
              for (var i = 0; i < _cats.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: i == 0 ? null : BoxDecoration(border: Border(top: BorderSide(color: p.border))),
                  child: _editing == _cats[i].name
                      ? Row(children: [
                          Expanded(child: AppField(controller: _draft, autofocus: true, maxLength: 30, onChanged: (_) => setState(() {}))),
                          const SizedBox(width: 8),
                          small(t('Save'), _draft.text.trim().isEmpty || _busy
                              ? null
                              : () {
                                  final from = _cats[i].name;
                                  if (_draft.text.trim() == from) return setState(() => _editing = null);
                                  _run(() async {
                                    await _api.put('/me/product-categories', {'from': from, 'to': _draft.text.trim()});
                                    _editing = null;
                                  });
                                }),
                          const SizedBox(width: 6),
                          small(t('Cancel'), () => setState(() => _editing = null), secondary: true),
                        ])
                      : _confirm == _cats[i].name
                          ? Row(children: [
                              Expanded(
                                child: Text.rich(
                                  TextSpan(children: [
                                    TextSpan(text: '${t('Delete')} '),
                                    TextSpan(text: _cats[i].name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                    TextSpan(text: '? ${_cats[i].count > 0 ? t('Its items stay, uncategorised.') : ''}'),
                                  ]),
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              small(t('Delete'), _busy
                                  ? null
                                  : () {
                                      final n = _cats[i].name;
                                      _run(() async {
                                        await _api.delete('/me/product-categories?name=${Uri.encodeQueryComponent(n)}');
                                        _confirm = null;
                                      });
                                    }, danger: true),
                              const SizedBox(width: 6),
                              small(t('Keep'), () => setState(() => _confirm = null), secondary: true),
                            ])
                          : Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(_cats[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                  Text('${_cats[i].count} ${t(_cats[i].count == 1 ? 'item' : 'items')}', style: TextStyle(fontSize: 12, color: p.muted)),
                                ]),
                              ),
                              InkResponse(
                                onTap: () => setState(() {
                                  _editing = _cats[i].name;
                                  _draft.text = _cats[i].name;
                                }),
                                radius: 20,
                                child: Padding(padding: const EdgeInsets.all(8), child: WIcon(WI.edit, size: 20, color: p.text)),
                              ),
                              InkResponse(
                                onTap: () => setState(() => _confirm = _cats[i].name),
                                radius: 20,
                                child: Padding(padding: const EdgeInsets.all(8), child: WIcon(WI.trash, size: 20, color: p.danger)),
                              ),
                            ]),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Put one item in a category, or none. Pops with a one-field record so "no category" (null) differs
/// from dismissing the sheet.
class _CategoryPicker extends StatefulWidget {
  final String title;
  final String? current;
  final List<_Cat> categories;
  const _CategoryPicker({required this.title, this.current, required this.categories});
  @override
  State<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<_CategoryPicker> {
  final _fresh = TextEditingController();

  @override
  void dispose() {
    _fresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    Widget row(String label, bool on, String? value) => GestureDetector(
          onTap: () => Navigator.pop(context, (value,)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(color: on ? p.chip : Colors.transparent, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
              if (on) const Text('✓', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ]),
          ),
        );
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .8),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            GestureDetector(onTap: () => Navigator.pop(context), child: WIcon(WI.close, size: 24, color: p.text)),
          ]),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              row(t('No category'), widget.current == null, null),
              for (final c in widget.categories) row(c.name, widget.current?.toLowerCase() == c.name.toLowerCase(), c.name),
            ]),
          ),
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
            child: Row(children: [
              Expanded(
                child: AppField(
                  controller: _fresh,
                  hint: t('New category'),
                  maxLength: 30,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) Navigator.pop(context, (v.trim(),));
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 84,
                child: GoldButton(label: t('Add'), height: 40, onPressed: _fresh.text.trim().isEmpty ? null : () => Navigator.pop(context, (_fresh.text.trim(),))),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

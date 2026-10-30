import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr/qr.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth_provider.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// UPI on a member's page and in chat (web components/upi.tsx): chips that open a QR popup, the list
/// in Edit profile, the "UPI payment" form in the chat attach sheet and the payment card in a chat.

const _green = Color(0xFF047857);
const _greenDark = Color(0xFF6EE7B7);
Color upiGreen(Pal p) => p.dark ? _greenDark : _green;

final _vpaRe = RegExp(r'^[a-z0-9][a-z0-9._-]{1,255}@[a-z][a-z0-9.-]{1,63}$');

/// NPCI's UPI payment link: opens the payer's UPI app with the UPI ID, name and amount filled in.
String upiLink({required String vpa, String? name, double? amount, String? note, String scheme = 'upi://pay'}) {
  final q = <String, String>{
    'pa': vpa,
    if ((name ?? '').isNotEmpty) 'pn': name!.length > 50 ? name.substring(0, 50) : name,
    if (amount != null && amount > 0) 'am': amount.toStringAsFixed(2),
    'cu': 'INR',
    if ((note ?? '').isNotEmpty) 'tn': note!.length > 60 ? note.substring(0, 60) : note,
  };
  return '$scheme?${q.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
}

String rupees(double n) {
  final whole = n == n.roundToDouble();
  final s = whole ? n.toInt().toString() : n.toStringAsFixed(2);
  // Indian grouping: 1,00,000
  final parts = s.split('.');
  var i = parts[0];
  if (i.length > 3) {
    final last3 = i.substring(i.length - 3);
    var rest = i.substring(0, i.length - 3);
    final groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    i = '${groups.join(',')},$last3';
  }
  return '₹$i${parts.length > 1 ? '.${parts[1]}' : ''}';
}

double? _amount(String s) {
  final v = double.tryParse(s);
  return v == null || v <= 0 ? null : (v * 100).roundToDouble() / 100;
}

/// Opens a UPI app. Android shows its own chooser for upi://; iPhones have no shared scheme, so the
/// member picks the app (each one has its own link).
Future<void> openUpiApp(BuildContext context, {required String vpa, String? name, double? amount, String? note}) async {
  Future<bool> go(String scheme) => launchUrl(Uri.parse(upiLink(vpa: vpa, name: name, amount: amount, note: note, scheme: scheme)), mode: LaunchMode.externalApplication)
      .catchError((_) => false);
  if (!Platform.isIOS) {
    if (!await go('upi://pay') && context.mounted) toast(context, t('No UPI app found on this phone'), error: true);
    return;
  }
  final p = Pal.of(context);
  final scheme = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: p.canvas,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(t('Pay with'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        for (final a in const [('Google Pay', 'gpay://upi/pay'), ('PhonePe', 'phonepe://pay'), ('Paytm', 'paytmmp://pay'), ('BHIM / other UPI app', 'upi://pay')])
          ListTile(title: Text(a.$1 == 'BHIM / other UPI app' ? t(a.$1) : a.$1, style: const TextStyle(fontWeight: FontWeight.w700)), onTap: () => Navigator.pop(ctx, a.$2)),
      ]),
    ),
  );
  if (scheme == null) return;
  if (!await go(scheme) && context.mounted) toast(context, t('That app is not on this phone'), error: true);
}

/// The QR code, black on white so every UPI app scans it (also in dark mode).
class UpiQr extends StatelessWidget {
  final String data;
  final double size;
  const UpiQr(this.data, {super.key, required this.size});
  @override
  Widget build(BuildContext context) => Semantics(
        label: t('UPI QR code'),
        child: Container(color: Colors.white, width: size, height: size, child: CustomPaint(painter: _QrPainter(data))),
      );
}

class _QrPainter extends CustomPainter {
  final String data;
  _QrPainter(this.data);
  @override
  void paint(Canvas canvas, Size size) {
    final img = QrImage(QrCode(payload: QrPayload.fromString(data), errorCorrectLevel: QrErrorCorrectLevel.medium));
    final n = img.moduleCount;
    final cell = size.width / (n + 4);
    final ink = Paint()
      ..color = kInk
      ..isAntiAlias = false;
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (img.isDark(r, c)) canvas.drawRect(Rect.fromLTWH((c + 2) * cell, (r + 2) * cell, cell + .5, cell + .5), ink);
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.data != data;
}

/// The UPI mark: its two arrowheads, green and orange, pointing right (as on the web).
const upiMarkSvg = '<svg viewBox="0 0 16 18" xmlns="http://www.w3.org/2000/svg"><path d="M6.2 0 15 9l-8.8 9 3-9z" fill="#097939"/><path d="M1 0l8.8 9L1 18l3-9z" fill="#ed752e"/></svg>';

/// A member's UPI IDs as chips (in the profile's tag row); tapping one opens its QR.
List<Widget> upiChips(BuildContext context, Profile u, String payee) => [
      for (final x in u.upi)
        GestureDetector(
          onTap: () => showUpiDialog(context, vpa: x.vpa, name: x.verifiedName ?? payee, verifiedName: x.verifiedName, editableAmount: true),
          child: Builder(builder: (context) {
            final p = Pal.of(context);
            final fg = upiGreen(p);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: .15), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                // the UPI mark, then "UPI QR" (the ID itself is in the QR popup)
                SvgPicture.string(upiMarkSvg, height: 13),
                const SizedBox(width: 5),
                Text(t('UPI QR'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
                if (x.verifiedName != null) ...[
                  const SizedBox(width: 4),
                  WIcon(WI.checkCircle, size: 12, color: fg),
                ],
              ]),
            );
          }),
        ),
    ];

/// The QR popup: who gets the money (the bank's name when verified), the QR, the UPI ID to copy, an
/// optional amount and a button that opens a UPI app with everything filled in.
Future<void> showUpiDialog(BuildContext context,
    {required String vpa, required String name, String? verifiedName, double? amount, String? note, bool editableAmount = false}) {
  final p = Pal.of(context);
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.canvas,
    barrierColor: kInk.withValues(alpha: .6),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _UpiSheet(vpa: vpa, name: name, verifiedName: verifiedName, amount: amount, note: note, editableAmount: editableAmount),
  );
}

class _UpiSheet extends StatefulWidget {
  final String vpa, name;
  final String? verifiedName, note;
  final double? amount;
  final bool editableAmount;
  const _UpiSheet({required this.vpa, required this.name, this.verifiedName, this.amount, this.note, this.editableAmount = false});
  @override
  State<_UpiSheet> createState() => _UpiSheetState();
}

class _UpiSheetState extends State<_UpiSheet> {
  late final _amt = TextEditingController(text: widget.amount == null ? '' : '${widget.amount}');

  @override
  void dispose() {
    _amt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final amount = widget.editableAmount ? _amount(_amt.text) : widget.amount;
    final link = upiLink(vpa: widget.vpa, name: widget.name, amount: amount, note: widget.note);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('Pay by UPI').toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.muted, letterSpacing: 0.4)),
                Text(widget.name.isEmpty ? widget.vpa : widget.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                widget.verifiedName != null
                    ? Row(children: [
                        WIcon(WI.checkCircle, size: 13, color: upiGreen(p)),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(t('Verified UPI ID · bank name {name}', {'name': widget.verifiedName!}),
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: upiGreen(p))),
                        ),
                      ])
                    : Text(t('Not verified. Check the name in your UPI app before you pay.'), style: TextStyle(fontSize: 12, color: p.muted)),
              ]),
            ),
            GestureDetector(onTap: () => Navigator.pop(context), child: WIcon(WI.close, size: 24, color: p.text)),
          ]),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.border)),
              child: UpiQr(link, size: 220),
            ),
          ),
          const SizedBox(height: 8),
          Text(t('Scan with any UPI app'), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.muted)),
          const SizedBox(height: 8),
          Center(
            child: Material(
              color: p.chip,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: widget.vpa));
                  toast(context, t('Copied'));
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(child: Text(widget.vpa, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, fontFamily: 'monospace'))),
                    const SizedBox(width: 8),
                    Text(t('Copy'), style: TextStyle(fontSize: 12, color: p.muted)),
                  ]),
                ),
              ),
            ),
          ),
          if (widget.editableAmount) ...[
            const SizedBox(height: 16),
            AppField(
              controller: _amt,
              label: t('Amount (optional)'),
              prefixText: '₹ ',
              keyboard: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,6}(\.\d{0,2})?'))],
              onChanged: (_) => setState(() {}),
            ),
          ] else if (amount != null) ...[
            const SizedBox(height: 16),
            Text(rupees(amount), textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            if ((widget.note ?? '').isNotEmpty) Text(widget.note!, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: p.muted)),
          ],
          const SizedBox(height: 16),
          GoldButton(
            label: amount != null ? t('Pay {amount} in a UPI app', {'amount': rupees(amount)}) : t('Open a UPI app'),
            onPressed: () => openUpiApp(context, vpa: widget.vpa, name: widget.name, amount: amount, note: widget.note),
          ),
        ]),
      ),
    );
  }
}

/// Edit profile > UPI: add UPI IDs, pick the default, verify (Razorpay, the bank's name), remove.
class UpiManager extends StatefulWidget {
  final VoidCallback? onChanged;
  const UpiManager({super.key, this.onChanged});
  @override
  State<UpiManager> createState() => UpiManagerState();
}

class UpiManagerState extends State<UpiManager> {
  List<UpiId>? _items;
  bool _canVerify = false;
  int _max = 5;
  String? _busy, _error;
  final _vpa = TextEditingController();

  @override
  void initState() {
    super.initState();
    _run('load', () => context.read<AuthProvider>().api.get('/me/upi'), notify: false);
  }

  @override
  void dispose() {
    _vpa.dispose();
    super.dispose();
  }

  Future<bool> _run(String key, Future<dynamic> Function() fn, {bool notify = true}) async {
    setState(() {
      _busy = key;
      _error = null;
    });
    try {
      final d = await fn() as Map;
      if (!mounted) return false;
      setState(() {
        _items = [for (final u in (d['items'] as List? ?? const [])) UpiId.fromJson(u as Map)];
        _canVerify = d['canVerify'] == true;
        _max = (d['max'] as num?)?.toInt() ?? 5;
      });
      if (notify) widget.onChanged?.call();
      return true;
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
      return false;
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final api = context.read<AuthProvider>().api;
    final items = _items;
    if (items == null) {
      return _error != null ? Text(_error!, style: TextStyle(color: p.danger)) : const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
    }
    final vpa = _vpa.text.trim().toLowerCase();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (items.isNotEmpty)
        RadioGroup<String>(
          groupValue: items.firstWhere((u) => u.isDefault, orElse: () => items.first).id,
          onChanged: (id) {
            if (_busy == null && id != null) _run('d', () => api.put('/me/upi/$id/default', {}));
          },
          child: Container(
          decoration: BoxDecoration(border: Border.all(color: p.border), borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            for (var i = 0; i < items.length; i++)
              Container(
                decoration: i == 0 ? null : BoxDecoration(border: Border(top: BorderSide(color: p.border))),
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                child: Row(children: [
                  Radio<String>(value: items[i].id, enabled: _busy == null),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(items[i].vpa, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text(t(items[i].isDefault ? 'Default' : 'Set as default'), style: TextStyle(fontSize: 12, color: p.muted)),
                        if (items[i].verifiedName != null)
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            WIcon(WI.checkCircle, size: 12, color: upiGreen(p)),
                            const SizedBox(width: 2),
                            Text(items[i].verifiedName!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: upiGreen(p))),
                          ]),
                      ]),
                    ]),
                  ),
                  if (items[i].verifiedName == null && _canVerify)
                    SizedBox(
                      width: 84,
                      child: GoldButton(
                        label: t('Verify'),
                        outlined: true,
                        height: 32,
                        loading: _busy == 'v${items[i].id}',
                        onPressed: _busy != null ? null : () => _run('v${items[i].id}', () => api.post('/me/upi/${items[i].id}/verify')),
                      ),
                    ),
                  IconButton(
                    tooltip: t('Remove {vpa}', {'vpa': items[i].vpa}),
                    onPressed: _busy != null ? null : () => _run('r', () => api.delete('/me/upi/${items[i].id}')),
                    icon: WIcon(WI.trash, size: 20, color: p.muted),
                  ),
                ]),
              ),
          ]),
        ),
        ),
      if (items.length < _max) ...[
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: AppField(
              controller: _vpa,
              hint: t('yourname@bank'),
              keyboard: TextInputType.emailAddress,
              inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: GoldButton(
              label: t('Add'),
              loading: _busy == 'add',
              onPressed: !_vpaRe.hasMatch(vpa) || _busy != null
                  ? null
                  : () async {
                      if (await _run('add', () => api.post('/me/upi', {'vpa': vpa}))) _vpa.clear();
                    },
            ),
          ),
        ]),
      ],
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(fontSize: 14, color: p.danger))),
      const SizedBox(height: 8),
      Text(
        t('Your UPI IDs show on your page, and you can send one in a chat to get paid. A UPI ID made from your mobile number shows that number.') +
            (_canVerify ? ' ${t('Verify checks the UPI ID with your bank and shows the account name next to it.')}' : ''),
        style: TextStyle(fontSize: 12, height: 1.45, color: p.muted),
      ),
    ]);
  }
}

/// Chat attach sheet > UPI payment: pick a UPI ID (the default is picked), optionally an amount and a
/// note, and send a payment card. With no UPI ID yet, it asks for one first.
class UpiRequestForm extends StatefulWidget {
  final Future<void> Function(Map<String, dynamic> attachment) onSend;
  final VoidCallback onBack;
  const UpiRequestForm({super.key, required this.onSend, required this.onBack});
  @override
  State<UpiRequestForm> createState() => _UpiRequestFormState();
}

class _UpiRequestFormState extends State<UpiRequestForm> {
  List<UpiId>? _items;
  String? _pick, _error;
  bool _busy = false;
  final _amt = TextEditingController(), _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amt.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await context.read<AuthProvider>().api.get('/me/upi') as Map;
      final items = [for (final u in (d['items'] as List? ?? const [])) UpiId.fromJson(u as Map)];
      if (!mounted) return;
      setState(() {
        _items = items;
        if (_pick == null || !items.any((u) => u.id == _pick)) {
          _pick = items.isEmpty ? null : items.firstWhere((u) => u.isDefault, orElse: () => items.first).id;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _send() async {
    final u = _items!.firstWhere((x) => x.id == _pick);
    final amount = _amount(_amt.text);
    if (amount != null && amount > 100000) return setState(() => _error = t('UPI payments go up to ₹1,00,000'));
    final me = context.read<AuthProvider>().profile;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // the server rebuilds the card from upiId; vpa and name are only for showing it while it sends
      await widget.onSend({
        'type': 'upi',
        'upiId': u.id,
        if (amount != null) 'amount': amount,
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
        'vpa': u.vpa,
        'name': u.verifiedName ?? (me == null ? '' : displayName(me.userType, me.name, me.company)),
        'verified': u.verifiedName != null,
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final items = _items;
    if (items == null) {
      return _error != null ? Text(_error!, style: TextStyle(color: p.danger)) : const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
    }
    if (items.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(t('Add your UPI ID to send it in chats. It also shows on your page.'), style: TextStyle(fontSize: 14, color: p.muted)),
        const SizedBox(height: 12),
        UpiManager(onChanged: _load),
        const SizedBox(height: 12),
        Align(alignment: Alignment.centerLeft, child: GoldButton(label: t('Back'), outlined: true, height: 44, onPressed: widget.onBack)),
      ]);
    }
    final amount = _amount(_amt.text);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      RadioGroup<String>(
        groupValue: _pick,
        onChanged: (v) => setState(() => _pick = v),
        child: Column(children: [
      for (final u in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            color: _pick == u.id ? p.chip : Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: _pick == u.id ? p.text : p.border)),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _pick = u.id),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                child: Row(children: [
                  Radio<String>(value: u.id),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(u.vpa, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      if (u.isDefault || u.verifiedName != null)
                        Text(
                          [if (u.isDefault) t('Default'), if (u.verifiedName != null) '✓ ${u.verifiedName}'].join(' · '),
                          style: TextStyle(fontSize: 12, color: u.verifiedName != null ? upiGreen(p) : p.muted, fontWeight: FontWeight.w600),
                        ),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
        ]),
      ),
      const SizedBox(height: 6),
      Row(children: [
        SizedBox(
          width: 130,
          child: AppField(
            controller: _amt,
            hint: t('Amount'),
            prefixText: '₹ ',
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,6}(\.\d{0,2})?'))],
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: AppField(controller: _note, hint: t('For (optional), e.g. Invoice 42'), maxLength: 60)),
      ]),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(fontSize: 14, color: p.danger))),
      const SizedBox(height: 12),
      Row(children: [
        GoldButton(label: t('Back'), outlined: true, height: 44, onPressed: widget.onBack),
        const SizedBox(width: 8),
        Expanded(
          child: GoldButton(
            label: amount != null ? t('Ask for {amount}', {'amount': rupees(amount)}) : t('Send UPI ID'),
            height: 44,
            loading: _busy,
            onPressed: _pick == null || _busy ? null : _send,
          ),
        ),
      ]),
    ]);
  }
}

/// A UPI card in a chat: the QR (tap for the large one), the amount, and for the payer a one-tap button.
class UpiCard extends StatelessWidget {
  final Map<String, dynamic> a;
  final bool mine;
  final Color fg, bg;
  const UpiCard({super.key, required this.a, required this.mine, required this.fg, required this.bg});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final vpa = '${a['vpa'] ?? ''}', name = '${a['name'] ?? ''}';
    final amount = (a['amount'] as num?)?.toDouble();
    final note = a['note'] as String?;
    final verified = a['verified'] == true;
    final link = upiLink(vpa: vpa, name: name, amount: amount, note: note);
    void open() => showUpiDialog(context, vpa: vpa, name: name, verifiedName: verified ? name : null, amount: amount, note: note, editableAmount: amount == null);
    return Container(
      width: 256,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8), border: const Border(left: BorderSide(color: Color(0xFF10B981), width: 4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        InkWell(
          onTap: vpa.isEmpty ? null : open,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              ClipRRect(borderRadius: BorderRadius.circular(6), child: UpiQr(link, size: 60)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t(amount != null ? 'Payment request' : 'UPI ID').toUpperCase(),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg.withValues(alpha: .7))),
                  if (amount != null) Text(rupees(amount), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: fg)),
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
                  Row(children: [
                    Flexible(child: Text(vpa, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: fg.withValues(alpha: .8)))),
                    if (verified) ...[const SizedBox(width: 4), WIcon(WI.checkCircle, size: 12, color: upiGreen(p))],
                  ]),
                  if ((note ?? '').isNotEmpty) Text(note!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: fg.withValues(alpha: .75))),
                ]),
              ),
            ]),
          ),
        ),
        if (!mine && vpa.isNotEmpty)
          InkWell(
            onTap: () => openUpiApp(context, vpa: vpa, name: name, amount: amount, note: note),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: fg.withValues(alpha: .1)))),
              child: Text(
                amount != null ? t('Pay {amount}', {'amount': rupees(amount)}) : t('Pay with a UPI app'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: upiGreen(p)),
              ),
            ),
          ),
      ]),
    );
  }
}

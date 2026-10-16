import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../auth_provider.dart';
import '../i18n.dart';
import '../location.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// Handles the API will refuse; checked here too so the message shows while typing.
const _reserved = {'admin', 'api', 'talk', 'ask', 'find', 'chat', 'post', 'profile', 'login', 'onboarding', 'update', 'u', 'me', 'saved', 'features', 'webweb', 'support', 'help'};
String _slug(String s) {
  final out = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  return out.length > 20 ? out.substring(0, 20) : out;
}

const _green = Color(0xFF2F9E6B);
const _emerald600 = Color(0xFF059669);

/// Keyword hints that suggest a sector from a business name or role (web suggestCategory).
const _categoryHints = <String, List<String>>{
  'Manufacturing': ['manufactur', 'industr', 'fabricat', 'engineer', 'cnc', 'machin', 'tools', 'plastic', 'packag', 'steel', 'casting', 'mill', 'works', 'operator', 'welder', 'fitter', 'turner'],
  'Trading / Wholesale': ['trader', 'trading', 'wholesale', 'distribut', 'agenc', 'suppl', 'export', 'import', 'merchant', 'enterprise'],
  'Retail': ['store', 'shop', 'mart', 'retail', 'boutique', 'supermarket', 'bazaar', 'emporium', 'salesman', 'cashier'],
  'IT & Software': ['tech', 'soft', 'digital', 'web', 'app', 'cloud', 'cyber', 'data', 'developer', 'programmer', 'designer', 'seo', 'network'],
  'Logistics & Transport': ['logistic', 'transport', 'cargo', 'courier', 'freight', 'carrier', 'travels', 'driver', 'warehouse', 'mover', 'packers', 'fleet'],
  'Construction & Real Estate': ['construct', 'builder', 'realty', 'real estate', 'infra', 'contractor', 'interior', 'architect', 'civil', 'developers', 'plumb', 'electric'],
  'Food & Beverage': ['food', 'restaurant', 'cafe', 'kitchen', 'cater', 'bakery', 'sweet', 'hotel', 'tiffin', 'juice', 'chef', 'dhaba', 'snack'],
  'Healthcare': ['clinic', 'hospital', 'pharma', 'medical', 'health', 'diagnostic', 'dental', 'doctor', 'nurse', 'lab', 'ayurved'],
  'Education & Training': ['school', 'class', 'academy', 'institute', 'tuition', 'coaching', 'training', 'educat', 'teacher', 'tutor'],
  'Professional Services': ['consult', 'associate', 'chartered', 'advocate', 'legal', 'account', 'audit', 'tax', 'ca ', 'finance', 'insurance', 'services'],
};

String? _suggestCategory(String text) {
  final s = ' ${text.toLowerCase()} ';
  String? best;
  var score = 0;
  _categoryHints.forEach((cat, words) {
    final n = words.where(s.contains).length;
    if (n > score) {
      score = n;
      best = cat;
    }
  });
  return best;
}

/// First sign-in, as the web /onboarding: step 1 makes the page (type, name, @link), step 2 offers
/// optional extras (photo, business / role, sector, location, one line) that fill the strength bar.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});
  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  Profile? _created;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final created = _created;
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 448),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    const LogoInline(size: 30, stacked: false),
                    const Spacer(),
                    if (created == null)
                      GestureDetector(
                        onTap: () => context.read<AuthProvider>().logout(),
                        child: Padding(padding: const EdgeInsets.only(right: 12), child: Text(t('Log out'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted))),
                      ),
                    Text('${created == null ? 1 : 2} / 2', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted)),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: Container(height: 4, decoration: BoxDecoration(color: kGold, borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(width: 6),
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 4,
                        decoration: BoxDecoration(color: created == null ? p.chip : kGold, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                  ]),
                ]),
              ),
              Expanded(
                child: created == null
                    ? _CreateStep(onCreated: (pr) => setState(() => _created = pr))
                    : _BoostStep(initial: created, onFinish: () => context.read<AuthProvider>().loadProfile()),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ----------------------------- step 1: required -----------------------------

class _CreateStep extends StatefulWidget {
  final ValueChanged<Profile> onCreated;
  const _CreateStep({required this.onCreated});
  @override
  State<_CreateStep> createState() => _CreateStepState();
}

class _CreateStepState extends State<_CreateStep> {
  String _type = 'entrepreneur';
  final _name = TextEditingController();
  final _handle = TextEditingController();
  bool _handleTouched = false;
  String _avail = 'idle'; // idle checking free taken reserved protected
  bool _busy = false;
  String? _error;
  Timer? _debounce;
  int _checkSeq = 0;

  bool get _valid => _name.text.trim().length >= 2 && RegExp(r'^[a-z0-9]{5,20}$').hasMatch(_handle.text);

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _handle.dispose();
    super.dispose();
  }

  void _nameChanged(String v) {
    if (!_handleTouched) _setHandle(_slug(v));
    setState(() {});
  }

  void _setHandle(String h) {
    _handle.value = TextEditingValue(text: h, selection: TextSelection.collapsed(offset: h.length));
    _check(h);
  }

  void _check(String h) {
    _debounce?.cancel();
    final seq = ++_checkSeq;
    if (!RegExp(r'^[a-z0-9]{5,20}$').hasMatch(h)) return setState(() => _avail = 'idle');
    if (_reserved.contains(h)) return setState(() => _avail = 'reserved');
    setState(() => _avail = 'checking');
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final r = await context.read<AuthProvider>().api.get('/public/handle-check/$h') as Map;
        final st = '${r['status']}';
        if (mounted && seq == _checkSeq) setState(() => _avail = st == 'free' || st == 'taken' || st == 'protected' ? st : 'reserved');
      } catch (_) {
        if (mounted && seq == _checkSeq) setState(() => _avail = 'idle'); // the server decides on submit
      }
    });
  }

  Future<void> _submit() async {
    if (!_valid || _busy || _avail == 'taken' || _avail == 'reserved' || _avail == 'protected') return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pr = await context.read<AuthProvider>().createProfile({'name': _name.text.trim(), 'handle': _handle.text, 'userType': _type});
      widget.onCreated(pr);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = t('Could not create your page. Try again.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final auth = context.watch<AuthProvider>();
    final phone = auth.phone;
    final email = auth.accountEmail ?? auth.email;
    final h = _handle.text;
    InputDecoration deco(String hint) => InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          hintText: hint,
          hintStyle: TextStyle(fontSize: 16, color: p.muted, fontWeight: FontWeight.w400),
        );
    BoxDecoration box() => BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border));

    return ListView(padding: const EdgeInsets.fromLTRB(16, 24, 16, 24), children: [
      Text(t('Create your free page'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.25)),
      const SizedBox(height: 4),
      Text(t('Under a minute. Only your name is required.'), style: TextStyle(fontSize: 14, color: p.muted)),
      if (phone.isNotEmpty || (email ?? '').isNotEmpty) ...[
        const SizedBox(height: 12),
        Align(alignment: Alignment.centerLeft, child: _VerifiedPill(phone: phone, email: email)),
      ],
      const SizedBox(height: 20),
      Row(children: [
        for (final (i, o) in const [('entrepreneur', 'Business', 'I sell or serve', WI.business), ('job_seeker', 'Job seeker', 'I look for work', WI.user)].indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _type = o.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _type == o.$1 ? kGold.withValues(alpha: .1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _type == o.$1 ? kGold : p.border),
                ),
                child: Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: _type == o.$1 ? p.ink : p.chip),
                    child: WIcon(o.$4, size: 18, strokeWidth: 2, color: _type == o.$1 ? p.onInk : p.muted),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t(o.$2), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.25)),
                      Text(t(o.$3), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted, height: 1.25)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 20),
      Text(t('Your name'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Container(
        height: 48,
        decoration: box(),
        child: TextField(
          controller: _name,
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          textInputAction: TextInputAction.next,
          onChanged: _nameChanged,
          style: const TextStyle(fontSize: 16),
          decoration: deco(t('e.g. Rahul Sharma')).copyWith(counterText: ''),
        ),
      ),
      const SizedBox(height: 20),
      Text(t('Your page link'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Container(
        height: 48,
        clipBehavior: Clip.antiAlias,
        decoration: box(),
        child: Row(children: [
          Container(
            height: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            color: p.chip.withValues(alpha: .7),
            child: Text('@', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.muted)),
          ),
          Expanded(
            child: TextField(
              controller: _handle,
              maxLength: 20,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (v) {
                _handleTouched = true;
                _setHandle(_slug(v));
              },
              onSubmitted: (_) => _submit(),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              decoration: deco('yourname').copyWith(counterText: '', contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 6),
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 16),
        child: switch (_avail) {
          'checking' => Text(t('Checking…'), style: TextStyle(fontSize: 12, color: p.muted)),
          'free' => Text('✓ ${t('Available')}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _emerald600)),
          'taken' => Text(t('Taken. Try another.'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.danger)),
          'reserved' => Text(t('Not available. Try another.'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.danger)),
          'protected' => Text(t('A protected name (a place, an industry or an institution). Choose another, or claim it with documents.'),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.danger)),
          _ => Text(t(h.isNotEmpty && h.length < 5 ? 'At least 5 letters or numbers' : 'Letters and numbers only'), style: TextStyle(fontSize: 12, color: p.muted)),
        },
      ),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(fontSize: 14, color: p.danger))),
      const SizedBox(height: 20),
      GoldButton(
        label: t('Create my page'),
        loading: _busy,
        onPressed: !_valid || _avail == 'taken' || _avail == 'reserved' || _avail == 'checking' || _avail == 'protected' ? null : _submit,
      ),
      const SizedBox(height: 20),
      Text(t('Next you can add a photo and more, or skip.'), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.muted)),
    ]);
  }
}

/// How the member signed in, shown as the first earned badge.
class _VerifiedPill extends StatelessWidget {
  final String phone;
  final String? email;
  const _VerifiedPill({required this.phone, this.email});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final fg = p.dark ? const Color(0xFF5FCF9A) : const Color(0xFF1F7A50);
    final text = phone.length >= 10
        ? '${t('Mobile verified')} · +91 ${phone.substring(0, 2)}••••••${phone.substring(phone.length - 2)}'
        : '${t('Email verified')} · ${email ?? ''}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: _green.withValues(alpha: .15), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        WIcon(WI.checkCircle, size: 14, color: fg),
        const SizedBox(width: 6),
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg))),
      ]),
    );
  }
}

// ----------------------------- step 2: optional -----------------------------

class _BoostStep extends StatefulWidget {
  final Profile initial;
  final Future<void> Function() onFinish;
  const _BoostStep({required this.initial, required this.onFinish});
  @override
  State<_BoostStep> createState() => _BoostStepState();
}

class _BoostStepState extends State<_BoostStep> {
  late Profile _profile = widget.initial;
  String? _open = 'photo';
  String? _busy;
  String? _error;
  String? _justEarned;
  bool _locating = false;
  bool _finishing = false;
  final _company = TextEditingController();
  final _bio = TextEditingController();

  static const _order = ['photo', 'company', 'category', 'location', 'bio'];

  bool get _isJob => _profile.userType == 'job_seeker';

  bool _done(String k, [Profile? pr]) {
    final x = pr ?? _profile;
    return switch (k) {
      'photo' => (x.photoUrl ?? '').isNotEmpty,
      'company' => x.company.isNotEmpty,
      'category' => x.category.isNotEmpty,
      'location' => x.location.isNotEmpty,
      _ => (x.bio ?? '').isNotEmpty,
    };
  }

  int _weight(String k) {
    for (final i in _profile.completion?.items ?? const <CompletionItem>[]) {
      if (i.key == k) return i.weight;
    }
    return 0;
  }

  @override
  void dispose() {
    _company.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save(String key, Map<String, dynamic> patch, [String? badge]) async {
    setState(() {
      _busy = key;
      _error = null;
    });
    try {
      final next = await context.read<AuthProvider>().patchProfile(patch);
      if (!mounted) return;
      setState(() {
        _profile = next;
        if (badge != null) _justEarned = badge;
        // on to the next thing that is still empty
        _open = _order.where((k) => k != key && !_done(k, next)).firstOrNull;
      });
      if (badge != null) {
        Future.delayed(const Duration(milliseconds: 2200), () {
          if (mounted) setState(() => _justEarned = null);
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = t('Could not save. Try again.'));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _pickPhoto() async {
    final auth = context.read<AuthProvider>();
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1000, maxHeight: 1000, imageQuality: 82);
    if (f == null) return;
    setState(() {
      _busy = 'photo';
      _error = null;
    });
    try {
      final url = await auth.uploadAvatar(await f.readAsBytes(), f.name);
      if (!mounted) return;
      await _save('photo', {'photoURL': url}, t('Photo added'));
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is ApiException ? e.message : '$e';
          _busy = null;
        });
      }
    }
  }

  Future<void> _detect() async {
    setState(() => _locating = true);
    try {
      final here = await currentLocation();
      if (!mounted) return;
      setState(() => _locating = false);
      await _save('location', {'location': here.node}, t('Location set'));
    } catch (_) {
      if (mounted) {
        setState(() {
          _locating = false;
          _error = t('Could not get your location. Pick one below.');
        });
      }
    }
  }

  Future<void> _finish() async {
    setState(() => _finishing = true);
    await widget.onFinish();
    if (mounted) setState(() => _finishing = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final completion = _profile.completion ?? const Completion(0, [], []);
    final suggested = _suggestCategory('${_profile.name} ${_profile.company}');
    final tasks = [
      ('photo', 'Add a photo', 'People reply to faces', _weight('photo') == 0 ? 10 : _weight('photo')),
      ('company', _isJob ? 'Your current role' : 'Your business name', _isJob ? 'For example: CNC operator' : 'Shown on your page', _weight('company') == 0 ? 5 : _weight('company')),
      ('category', _isJob ? 'Field you work in' : 'Business sector', 'Helps the right people find you', _weight('category') == 0 ? 5 : _weight('category')),
      ('location', 'Where you are', 'Matches you with nearby asks', _weight('location') == 0 ? 5 : _weight('location')),
      ('bio', 'One line about you', 'Up to 160 characters', _weight('bio') == 0 ? 10 : _weight('bio')),
    ];
    final anyAdded = _order.any(_done);
    final goldText = p.dark ? const Color(0xFFFFD84A) : const Color(0xFF7A5A00);

    Widget chip(String label, VoidCallback? onTap, {bool hint = false}) => GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: hint ? kGold.withValues(alpha: .1) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: hint ? kGold : p.border),
            ),
            child: Text(t(label), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        );

    Widget inputBox(TextEditingController c, String hint, {int lines = 1, int max = 80}) => Container(
          constraints: BoxConstraints(minHeight: lines > 1 ? 0 : 44),
          decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
          child: TextField(
            controller: c,
            autofocus: true,
            maxLines: lines,
            maxLength: max,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              hintText: hint,
              hintStyle: TextStyle(fontSize: 16, color: p.muted),
            ),
          ),
        );

    Widget body(String key) => switch (key) {
          'photo' => GoldButton(label: t('Choose a photo'), wi: WI.camera, outlined: true, height: 40, loading: _busy == 'photo', onPressed: _pickPhoto),
          'company' => Row(children: [
              Expanded(child: inputBox(_company, t(_isJob ? 'e.g. CNC operator' : 'e.g. Rahul Traders'))),
              const SizedBox(width: 8),
              SizedBox(
                width: 84,
                child: GoldButton(
                  label: t('Save'),
                  height: 40,
                  loading: _busy == 'company',
                  onPressed: _company.text.trim().length < 2 ? null : () => _save('company', {'company': _company.text.trim()}),
                ),
              ),
            ]),
          'category' => Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in kProfileCategories) chip(c.label, _busy == 'category' ? null : () => _save('category', {'category': c.value}, t('Sector added')), hint: suggested == c.value),
            ]),
          'location' => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              GoldButton(label: t('Use my location'), wi: WI.pin, outlined: true, height: 40, loading: _locating, onPressed: _detect),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final l in kLocations) chip(l.label, _busy == 'location' ? null : () => _save('location', {'location': l.value}, t('Location set'))),
              ]),
            ]),
          _ => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              inputBox(_bio, t('What you do, in one line'), lines: 2, max: 160),
              const SizedBox(height: 8),
              Row(children: [
                Text('${_bio.text.length}/160', style: TextStyle(fontSize: 12, color: p.muted)),
                const Spacer(),
                SizedBox(
                  width: 84,
                  child: GoldButton(
                    label: t('Save'),
                    height: 40,
                    loading: _busy == 'bio',
                    onPressed: _bio.text.trim().length < 3 ? null : () => _save('bio', {'bio': _bio.text.trim()}, t('About added')),
                  ),
                ),
              ]),
            ]),
        };

    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 24, 16, 16), children: [
          Text('${t('Your page is live')} 🎉', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.25)),
          const SizedBox(height: 4),
          Text('@${_profile.handle} · ${t('Add more to earn badges. Every step is optional.')}', style: TextStyle(fontSize: 14, color: p.muted)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      height: 8,
                      color: p.chip,
                      alignment: Alignment.centerLeft,
                      child: AnimatedFractionallySizedBox(
                        duration: const Duration(milliseconds: 500),
                        widthFactor: completion.percent.clamp(0, 100) / 100,
                        child: Container(decoration: BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(4))),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text('${completion.percent}%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
                ),
              ]),
              if (completion.badges.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final b in completion.badges)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: kGold.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _justEarned == b ? kGold : Colors.transparent, width: 2),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        WIcon(WI.checkCircle, size: 12, color: goldText),
                        const SizedBox(width: 4),
                        Text(t(b), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: goldText)),
                      ]),
                    ),
                ]),
              ],
            ]),
          ),
          const SizedBox(height: 20),
          for (final task in tasks) ...[
            Builder(builder: (_) {
              final done = _done(task.$1);
              final open = _open == task.$1 && !done;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 8),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: done ? _green.withValues(alpha: .05) : p.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: done ? _green.withValues(alpha: .4) : p.border),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  InkWell(
                    onTap: done ? null : () => setState(() => _open = open ? null : task.$1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(children: [
                        Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: done ? _green : p.chip),
                          child: WIcon(WI.checkCircle, size: 16, color: done ? Colors.white : p.muted),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(t(task.$2), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.25)),
                            Text(t(task.$3), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted, height: 1.25)),
                          ]),
                        ),
                        if (!done)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: kGold.withValues(alpha: .2), borderRadius: BorderRadius.circular(20)),
                            child: Text('+${task.$4}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: goldText)),
                          ),
                      ]),
                    ),
                  ),
                  if (open)
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
                      child: body(task.$1),
                    ),
                ]),
              );
            }),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(fontSize: 14, color: p.danger))),
        ]),
      ),
      // stays reachable while the cards are long
      Container(
        padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 16),
        decoration: BoxDecoration(color: p.canvas.withValues(alpha: .95), border: Border(top: BorderSide(color: p.border))),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          GoldButton(label: t(anyAdded ? 'Done, take me to my feed' : 'Go to my feed'), loading: _finishing, onPressed: _finish),
          if (!anyAdded) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _finishing ? null : _finish,
              child: Text(t('Skip for now'), textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.muted)),
            ),
          ],
          const SizedBox(height: 8),
          Text(t('You can finish the rest from your profile any time.'), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.muted)),
        ]),
      ),
    ]);
  }
}

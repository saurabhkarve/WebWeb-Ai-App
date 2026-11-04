import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../auth_provider.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets.dart';

const _green = Color(0xFF2F9E6B);

/// The business categories, in their usual order; the sub-categories come from GET /service-contacts/categories.
const _parents = [
  'Manufacturing', 'Trading / Wholesale', 'Retail', 'IT & Software', 'Logistics & Transport', 'Construction & Real Estate',
  'Food & Beverage', 'Healthcare', 'Education & Training', 'Professional Services', 'Other',
];

/// What they do: business, freelancing, a job, or nothing. "Nothing" joins as a plain member.
enum _Doing { business, freelancing, job, nothing }

/// First sign-in (as the web /onboarding): after the phone number and the code, one question (what do you do?), then,
/// unless the answer is "Nothing", the categories and sub-categories that fit. That is all; the rest is done from the profile.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});
  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  _Doing? _doing;
  bool _busy = false;
  String? _error;
  /// the page to go back to from a new page's set-up: the one it was added from, else any other page that is set up
  String? _back;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _back = auth.previousPageUid;
    if (_back == null) {
      auth.accounts().then((l) {
        final other = l.where((a) => a['active'] != true && a['handle'] != null).toList();
        if (mounted && other.isNotEmpty) setState(() => _back = other.first['uid'] as String?);
      }).catchError((_) {});
    }
  }

  /// The one call that makes the account: only what they do and their categories.
  Future<void> _create(_Doing d, {String? category, List<String> subs = const []}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    try {
      await auth.createProfile({
        'userType': d == _Doing.nothing ? 'consumer' : d == _Doing.job ? 'job_seeker' : 'entrepreneur',
        if (category != null) 'category': category,
        if (subs.isNotEmpty) 'services': subs.join('\n'),
      });
      await auth.loadProfile(); // the app opens
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
    final more = _doing != null && _doing != _Doing.nothing;
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    // a page added from the account menu: Back returns to the page they came from
                    if (!more && _back != null)
                      GestureDetector(
                        onTap: () async {
                          final auth = context.read<AuthProvider>();
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await auth.switchAccount(_back);
                          } catch (_) {
                            messenger.showSnackBar(SnackBar(content: Text(t('Could not switch page'))));
                          }
                        },
                        child: Container(
                          height: 36,
                          margin: const EdgeInsets.only(right: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(border: Border.all(color: p.border), borderRadius: BorderRadius.circular(18)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.arrow_back_rounded, size: 16),
                            const SizedBox(width: 4),
                            Text(t('Back'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ),
                    const LogoInline(size: 28, markSize: 36, tagline: true),
                    const Spacer(),
                    if (!more)
                      GestureDetector(
                        onTap: () => context.read<AuthProvider>().logout(),
                        child: Padding(padding: const EdgeInsets.only(right: 12), child: Text(t('Log out'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted))),
                      ),
                    Text('${more ? 2 : 1} / 2', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted)),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: Container(height: 4, decoration: BoxDecoration(color: kGold, borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(width: 6),
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 4,
                        decoration: BoxDecoration(color: more ? kGold : p.chip, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                  ]),
                ]),
              ),
              Expanded(
                child: more
                    ? _CategoryStep(
                        busy: _busy,
                        error: _error,
                        onBack: () => setState(() {
                          _doing = null;
                          _error = null;
                        }),
                        onDone: (c, subs) => _create(_doing!, category: c, subs: subs),
                      )
                    : _DoingStep(
                        busy: _busy,
                        error: _error,
                        onPick: (d) {
                          setState(() {
                            _error = null;
                            _doing = d;
                          });
                          if (d == _Doing.nothing) _create(d);
                        },
                      ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ----------------------------- step 1: what do you do? -----------------------------

class _DoingStep extends StatelessWidget {
  final bool busy;
  final String? error;
  final ValueChanged<_Doing> onPick;
  const _DoingStep({required this.busy, required this.error, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final auth = context.watch<AuthProvider>();
    final opts = [
      (_Doing.business, 'Business', 'I run a shop, a company or a service', WI.business),
      (_Doing.freelancing, 'Freelancing', 'I work for myself', WI.user),
      (_Doing.job, 'Job', 'I work in a job, or look for one', WI.job),
      (_Doing.nothing, 'Nothing', 'I am just looking', WI.search),
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 24, 16, 32), children: [
      Text(t('What do you do?'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.2)),
      const SizedBox(height: 4),
      Text(t('One tap. You can change it later.'), style: TextStyle(fontSize: 14, color: p.muted)),
      if (auth.phone.isNotEmpty || auth.accountEmail != null) ...[
        const SizedBox(height: 12),
        Align(alignment: Alignment.centerLeft, child: _VerifiedPill(phone: auth.phone, email: auth.accountEmail)),
      ],
      const SizedBox(height: 20),
      for (final (d, label, hint, icon) in opts)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: busy ? null : () => onPick(d),
              child: Container(
                constraints: const BoxConstraints(minHeight: 68),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(border: Border.all(color: p.border), borderRadius: BorderRadius.circular(18)),
                child: Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: p.chip, shape: BoxShape.circle),
                    child: Center(child: WIcon(icon, size: 22, color: p.muted)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t(label), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      Text(t(hint), style: TextStyle(fontSize: 13.5, height: 1.3, color: p.muted)),
                    ]),
                  ),
                  if (busy && d == _Doing.nothing) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: kGold)),
                ]),
              ),
            ),
          ),
        ),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(error!, style: const TextStyle(color: Colors.red, fontSize: 13.5))),
    ]);
  }
}

// ----------------------------- step 2: categories and sub-categories -----------------------------

class _CategoryStep extends StatefulWidget {
  final bool busy;
  final String? error;
  final VoidCallback onBack;
  final void Function(String? category, List<String> subs) onDone;
  const _CategoryStep({required this.busy, required this.error, required this.onBack, required this.onDone});
  @override
  State<_CategoryStep> createState() => _CategoryStepState();
}

class _CategoryStepState extends State<_CategoryStep> {
  List<Map>? _cats;
  String? _open;
  final _parentsPicked = <String>[];
  final _subs = <String>[];

  @override
  void initState() {
    super.initState();
    context.read<AuthProvider>().api.get('/service-contacts/categories').then((d) {
      if (mounted) setState(() => _cats = ((d as Map)['categories'] as List).cast<Map>());
    }).catchError((_) {
      if (mounted) setState(() => _cats = const []);
    });
  }

  List<Map> _under(String parent) => (_cats ?? const <Map>[]).where((c) => c['parent'] == parent).toList()..sort((a, b) => '${a['tag']}'.compareTo('${b['tag']}'));

  String? get _primary {
    if (_parentsPicked.isNotEmpty) return _parentsPicked.first;
    if (_subs.isEmpty) return null;
    return (_cats ?? const <Map>[]).where((c) => c['tag'] == _subs.first).map((c) => '${c['parent']}').firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final any = _parentsPicked.isNotEmpty || _subs.isNotEmpty;
    final groups = [for (final g in _parents) if (g != 'Other' || _under('Other').isNotEmpty) g];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), children: [
          GestureDetector(
            onTap: widget.onBack,
            child: Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('← ${t('Back')}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.muted))),
          ),
          Text(t('Pick your categories'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.2)),
          const SizedBox(height: 4),
          Text(t('Choose a category, then what fits under it. As many as you like.'), style: TextStyle(fontSize: 14, color: p.muted)),
          const SizedBox(height: 16),
          if (_cats == null)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: kGold)))
          else
            for (final g in groups) _group(p, g),
          if (widget.error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(widget.error!, style: const TextStyle(color: Colors.red, fontSize: 13.5))),
        ]),
      ),
      Container(
        padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.paddingOf(context).bottom),
        decoration: BoxDecoration(color: p.canvas, border: Border(top: BorderSide(color: p.border))),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: !any || widget.busy ? null : () => widget.onDone(_primary, List.of(_subs)),
              style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: kInk, shape: const StadiumBorder(), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              child: widget.busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: kInk)) : Text(t('Continue')),
            ),
          ),
          TextButton(onPressed: widget.busy ? null : () => widget.onDone(null, const []), child: Text(t('Skip for now'), style: TextStyle(fontWeight: FontWeight.w700, color: p.muted))),
        ]),
      ),
    ]);
  }

  Widget _group(Pal p, String parent) {
    final items = _under(parent);
    final on = _parentsPicked.contains(parent);
    final n = items.where((c) => _subs.contains(c['tag'])).length;
    final open = _open == parent;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: on ? kGold.withValues(alpha: .1) : null,
        border: Border.all(color: on ? kGold : p.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => on ? _parentsPicked.remove(parent) : _parentsPicked.add(parent)),
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(color: on ? kGold : null, border: Border.all(color: on ? kGold : p.border), borderRadius: BorderRadius.circular(6)),
                    child: on ? const Icon(Icons.check_rounded, size: 15, color: kInk) : null,
                  ),
                  const SizedBox(width: 12),
                  Flexible(child: Text(t(parent), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                  if (n > 0) ...[
                    const SizedBox(width: 8),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1), decoration: BoxDecoration(color: kGold.withValues(alpha: .3), borderRadius: BorderRadius.circular(10)), child: Text('$n', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                  ],
                ]),
              ),
            ),
          ),
          if (items.isNotEmpty)
            IconButton(
              onPressed: () => setState(() => _open = open ? null : parent),
              icon: Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: p.muted),
            ),
        ]),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in items) _chip(p, c),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _chip(Pal p, Map c) {
    final tag = '${c['tag']}';
    final sel = _subs.contains(tag);
    return GestureDetector(
      onTap: () => setState(() {
        if (sel) {
          _subs.remove(tag);
        } else {
          _subs.add(tag);
          if (!_parentsPicked.contains('${c['parent']}')) _parentsPicked.add('${c['parent']}');
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          gradient: sel ? kGoldGradient : null,
          color: sel ? null : p.card,
          border: sel ? null : Border.all(color: p.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('${c['emoji'] ?? ''} ${t(tag)}', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: sel ? kInk : p.text)),
      ),
    );
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

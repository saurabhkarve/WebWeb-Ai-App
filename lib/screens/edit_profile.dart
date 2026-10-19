import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, TextInputFormatter, TextEditingValue;
import 'package:provider/provider.dart';

import '../api.dart';
import '../auth_provider.dart';
import '../i18n.dart';
import '../location.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'account_settings.dart';
import 'catalog.dart';
import '../widgets/picture_picker.dart';
import '../widgets/resume.dart';
import '../widgets/upi.dart';

/// Edit profile (web profile/edit): cover, photo, name, organisation, sector, location, about, then
/// services (business) or skills / experience / education (job seeker), GST verification and the catalog.
/// The photo and cover save at once; the rest saves with "Save changes".
class EditProfileScreen extends StatefulWidget {
  final Profile profile;
  /// 'account' opens the Account and privacy tab
  final String? tab;
  const EditProfileScreen({super.key, required this.profile, this.tab});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final _name = TextEditingController(text: widget.profile.name);
  late final _company = TextEditingController(text: widget.profile.company);
  late final _bio = TextEditingController(text: widget.profile.bio ?? '');
  late final _services = TextEditingController(text: widget.profile.services.join('\n'));
  late final _skills = TextEditingController(text: widget.profile.skills.join('\n'));
  late final _experience = TextEditingController(text: widget.profile.experience ?? '');
  late final _education = TextEditingController(text: widget.profile.education ?? '');
  late final _gst = TextEditingController(text: widget.profile.gstin ?? '');
  late final _handle = TextEditingController(text: widget.profile.handle);
  /// idle, checking, free, yours, taken, invalid, protected, system
  String _handleState = 'idle';
  bool _handleBusy = false;
  (bool, String)? _handleMsg;
  Timer? _handleDebounce;
  int _handleSeq = 0;
  late String _category = widget.profile.category;
  late String _location = widget.profile.location;
  bool _gstBusy = false;
  String? _gstMsg;
  bool _locating = false;
  bool _saving = false;
  bool _changed = false;
  String? _error;

  AuthProvider get _auth => context.read<AuthProvider>();

  /// The photo / cover picker: a new picture (cropped), an earlier one, or (covers) a WEBWEB design.
  Future<void> _pick(String kind) async {
    if (await showPicturePicker(context, kind)) _changed = true;
  }

  Future<void> _detect() async {
    setState(() => _locating = true);
    try {
      final h = await currentLocation(context, reason: t('To set the area on your page, so nearby members and asks can find you.'), source: 'profile');
      if (mounted) setState(() => _location = h.node);
    } on PermissionNotGiven {
      // explained in the pop-up
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // members may have joined with just a name: empty optional fields are simply left unset
      await _auth.updateProfile({
        'name': _name.text.trim(),
        if (_company.text.trim().isNotEmpty) 'company': _company.text.trim(),
        if (_category.isNotEmpty) 'category': _category,
        if (_location.isNotEmpty) 'location': _location,
        'bio': _bio.text.trim(),
        'services': _services.text.trim(),
        'skills': _skills.text.replaceAll(',', '\n').trim(),
        'experience': _experience.text.trim(),
        'education': _education.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Live check of a new page link as it is typed (5 to 20 small letters or numbers).
  void _checkHandle(String h) {
    _handleDebounce?.cancel();
    final seq = ++_handleSeq;
    setState(() => _handleMsg = null);
    final current = _auth.profile?.handle ?? widget.profile.handle;
    if (h == current) return setState(() => _handleState = 'idle');
    if (!RegExp(r'^[a-z0-9]{5,20}$').hasMatch(h)) return setState(() => _handleState = 'invalid');
    setState(() => _handleState = 'checking');
    _handleDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final r = await _auth.api.get('/public/handle-check/$h') as Map;
        if (mounted && seq == _handleSeq) setState(() => _handleState = '${r['status']}');
      } catch (_) {
        if (mounted && seq == _handleSeq) setState(() => _handleState = 'idle');
      }
    });
  }

  /// Change the page link. The old one keeps opening the page; once a day.
  Future<void> _saveHandle() async {
    setState(() {
      _handleBusy = true;
      _handleMsg = null;
    });
    try {
      await _auth.api.put('/me/handle', {'handle': _handle.text});
      await _auth.loadProfile();
      _changed = true;
      if (mounted) {
        setState(() {
          _handleState = 'idle';
          _handleMsg = (true, t('Your new link is webweb.ai/@{handle}. The old link keeps opening your page.', {'handle': _handle.text}));
        });
      }
    } catch (e) {
      if (mounted) setState(() => _handleMsg = (false, e is ApiException ? t(e.message) : '$e'));
    } finally {
      if (mounted) setState(() => _handleBusy = false);
    }
  }

  String? get _handleNote => switch (_handleState) {
        'checking' => t('Checking…'),
        'free' => t('Available'),
        'yours' => t('This was your earlier link. You can take it back.'),
        'taken' => t('That link is already taken. Try another.'),
        'invalid' => t('Use 5 to 20 letters or numbers'),
        'protected' => t('That is a protected name (a place, an industry or an institution). Choose another.'),
        'system' => t('That link is not available. Try another.'),
        _ => null,
      };

  Future<void> _saveGst() async {
    setState(() {
      _gstBusy = true;
      _gstMsg = null;
    });
    try {
      await _auth.updateProfile({'gstNumber': _gst.text.trim().toUpperCase()});
      _changed = true;
      final lvl = _auth.profile?.verification ?? 1;
      if (mounted) {
        setState(() => _gstMsg = lvl >= 2 ? 'Verified as: ${kVerificationLabel[lvl]}' : 'GST number removed. You are back to Mobile number verified.');
      }
    } catch (e) {
      if (mounted) setState(() => _gstMsg = e is ApiException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _gstBusy = false);
    }
  }

  @override
  void dispose() {
    _handleDebounce?.cancel();
    for (final c in [_name, _company, _bio, _services, _skills, _experience, _education, _gst, _handle]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _label(String text) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(text, style: const TextStyle(fontSize: 14)));

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    // photo, cover and verification change as they save: show the live profile
    final me = context.watch<AuthProvider>().profile ?? widget.profile;
    final job = me.isJobSeeker;
    final banner = me.bannerUrl;

    Widget pill(String label, VoidCallback? onTap) => GestureDetector(
          onTap: onTap,
          child: Opacity(
            opacity: onTap == null ? .6 : 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .85), borderRadius: BorderRadius.circular(20)),
              child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kInk)),
            ),
          ),
        );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: SubPage(
        title: t('Edit profile'),
        body: DefaultTabController(
          length: job ? 3 : 4,
          initialIndex: switch (widget.tab) { 'account' => job ? 2 : 3, 'upi' => job ? 1 : 2, _ => 0 },
          child: Column(children: [
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: p.text,
              unselectedLabelColor: p.muted,
              indicatorColor: p.text,
              labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              tabs: [Tab(text: t('Profile')), if (!job) Tab(text: t('Business')), Tab(text: t('UPI')), Tab(text: t('Account and privacy'))],
            ),
            Expanded(
              child: TabBarView(children: [
                ListView(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 32),
                  children: [
                    // ---- cover ----
                    Text(t('Cover'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    AspectRatio(
                      aspectRatio: 3, // the shape the cover is cropped to
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
                        child: Stack(fit: StackFit.expand, children: [
                          if ((banner ?? '').isNotEmpty) NetImg(banner!, fit: BoxFit.cover) else CoverPattern(seed: me.handle.isNotEmpty ? me.handle : me.name),
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: Row(children: [
                              pill(t((banner ?? '').isNotEmpty ? 'Change cover' : 'Add cover'), () => _pick('cover')),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(t('Upload one and crop it, or pick a WEBWEB design. Without one we show a yellow pattern.'), style: TextStyle(fontSize: 12, color: p.muted)),
                    const SizedBox(height: 16),
                    // ---- photo ----
                    GestureDetector(
                      onTap: () => _pick('avatar'),
                      child: Row(children: [
                        SizedBox(
                          width: 84,
                          height: 84,
                          child: Stack(clipBehavior: Clip.none, children: [
                            Avatar(name: me.name, photoUrl: me.photoUrl, size: 80, ring: me.hasUpdate, type: me.userType, badge: 26),
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Container(
                                width: 32,
                                height: 32,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(shape: BoxShape.circle, color: p.ink, border: Border.all(color: p.canvas, width: 2)),
                                child: WIcon(WI.camera, size: 16, strokeWidth: 2.1, color: p.onInk),
                              ),
                            ),
                          ]),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(t((me.photoUrl ?? '').isNotEmpty ? 'Change photo' : 'Add profile photo'),
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.link)),
                            Text(t('A clear face or logo helps people trust you. JPG, PNG or WebP.'), style: TextStyle(fontSize: 12, color: p.muted)),
                          ]),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    AppField(controller: _name, label: t('Your name'), caps: TextCapitalization.words, maxLength: 60, onChanged: (_) => setState(() {})),
                    const SizedBox(height: 16),
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Expanded(
                        child: AppField(
                          controller: _handle,
                          label: t('Page link'),
                          prefixText: 'webweb.ai/@',
                          maxLength: 20,
                          keyboard: TextInputType.visiblePassword, // no autocorrect or capitals
                          inputFormatters: [_LowerCase(), FilteringTextInputFormatter.allow(RegExp('[a-z0-9]'))],
                          onChanged: _checkHandle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 22),
                        child: SizedBox(
                          width: 96,
                          child: GoldButton(
                            label: t('Change'),
                            outlined: true,
                            height: 48,
                            loading: _handleBusy,
                            onPressed: _handleState == 'free' || _handleState == 'yours' ? _saveHandle : null,
                          ),
                        ),
                      ),
                    ]),
                    if (_handleMsg != null || _handleNote != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _handleMsg?.$2 ?? _handleNote!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _handleMsg != null
                                ? (_handleMsg!.$1 ? const Color(0xFF2F9E6E) : p.danger)
                                : _handleState == 'free' || _handleState == 'yours'
                                    ? const Color(0xFF2F9E6E)
                                    : _handleState == 'checking'
                                        ? p.muted
                                        : p.danger,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(t('5 to 20 small letters or numbers. You can change it once a day; the old link keeps opening your page.'),
                          style: TextStyle(fontSize: 12, color: p.muted)),
                    ),
                    const SizedBox(height: 16),
                    AppField(controller: _company, label: t('Organisation name'), caps: TextCapitalization.words, maxLength: 80),
                    const SizedBox(height: 16),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          _label(t('Category')),
                          SelectPill(
                            value: _category,
                            placeholder: t('Not set'),
                            rounded: false,
                            height: 44,
                            options: [for (final o in kProfileCategories) Option(o.value, t(o.label))],
                            onChanged: (v) => setState(() => _category = v),
                          ),
                        ]),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          _label(t('Location')),
                          SelectPill(
                            value: _location,
                            placeholder: t('Not set'),
                            rounded: false,
                            height: 44,
                            options: [for (final o in kLocations) Option(o.value, t(o.label))],
                            onChanged: (v) => setState(() => _location = v),
                          ),
                        ]),
                      ),
                    ]),
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: _locating ? null : _detect,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (_locating) const LogoLoader(size: 16) else WIcon(WI.locate, size: 16, color: p.link),
                            const SizedBox(width: 4),
                            Text(t('Use my location'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.link)),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    AppField(controller: _bio, label: t('About'), maxLines: 3, maxLength: 300, caps: TextCapitalization.sentences),
                    if (!job) ...[
                      const SizedBox(height: 16),
                      AppField(controller: _services, label: t('Services'), helper: t('One per line'), maxLines: 4, caps: TextCapitalization.sentences),
                    ] else ...[
                      const SizedBox(height: 16),
                      AppField(controller: _skills, label: t('Skills'), helper: t('One per line or comma separated'), maxLines: 3),
                      const SizedBox(height: 16),
                      // one entry at a time, as on the profile page; kept with the form until Save changes
                      ResumeList(title: t('Experience'), text: _experience.text, icon: WI.business, kind: 'experience', editable: true, onSave: (v) async => setState(() => _experience.text = v)),
                      const SizedBox(height: 20),
                      ResumeList(title: t('Education'), text: _education.text, icon: WI.school, kind: 'education', editable: true, onSave: (v) async => setState(() => _education.text = v)),
                    ],
                    if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(fontSize: 14, color: p.danger))),
                    const SizedBox(height: 16),
                    GoldButton(label: t('Save changes'), loading: _saving, onPressed: _name.text.trim().length >= 2 ? _save : null),
                  ],
                ),
                // ---- business: verification and catalog ----
                if (!job)
                ListView(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 32),
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Text(t('Business verification'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(width: 8),
                          VerifiedBadge(level: me.verification, premium: me.premium, size: 20),
                        ]),
                        const SizedBox(height: 12),
                        Text.rich(
                          TextSpan(children: [
                            const TextSpan(text: 'Now: '),
                            TextSpan(text: kVerificationLabel[me.verification] ?? '', style: TextStyle(fontWeight: FontWeight.w700, color: p.text)),
                            const TextSpan(text: '. Add your GST number to get the blue '),
                            TextSpan(text: t('Documents verified'), style: const TextStyle(fontWeight: FontWeight.w700)),
                            const TextSpan(text: ' seal. After 3 positive ratings from other members you become the gold '),
                            TextSpan(text: t('Owner verified'), style: const TextStyle(fontWeight: FontWeight.w700)),
                            const TextSpan(text: '.'),
                          ]),
                          style: TextStyle(fontSize: 14, color: p.muted, height: 1.4),
                        ),
                        const SizedBox(height: 12),
                        AppField(
                          controller: _gst,
                          label: t('GST number (GSTIN)'),
                          helper: t('15 characters, e.g. 27ABCDE1234F1Z5'),
                          maxLength: 15,
                          caps: TextCapitalization.characters,
                          onChanged: (_) => setState(() {}),
                        ),
                        if (_gstMsg != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_gstMsg!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                        const SizedBox(height: 12),
                        GoldButton(label: _gst.text.isNotEmpty ? 'Verify GST number' : 'Remove GST number', outlined: true, height: 40, loading: _gstBusy, onPressed: _saveGst),
                    ]),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.only(top: 16),
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
                      child: GoldButton(
                        label: t('Manage products & services'),
                        outlined: true,
                        height: 40,
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogScreen())),
                      ),
                    ),
                  ],
                ),
                // ---- UPI IDs on the page ----
                ListView(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 32),
                  children: [
                    Text(t('UPI IDs'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(t('Get paid straight to your bank. Add one or more UPI IDs and pick the one to show first.'), style: TextStyle(fontSize: 14, color: p.muted, height: 1.4)),
                    const SizedBox(height: 12),
                    UpiManager(onChanged: () => _changed = true),
                  ],
                ),
                const AccountSettingsTab(),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _LowerCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) => newValue.copyWith(text: newValue.text.toLowerCase());
}

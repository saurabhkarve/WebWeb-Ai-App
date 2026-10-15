import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/pickers.dart';

/// First-login profile setup, same fields as the web onboarding (POST /me/profile):
/// type, name, company / current role, category, location, short bio, products & services, photo.
/// The @handle is made by the server from the company name.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});
  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  int _step = 0; // 0 type, 1 name/company, 2 category/location, 3 bio/services/photo
  String? _type;
  final _name = TextEditingController();
  final _company = TextEditingController();
  final _bio = TextEditingController();
  final _services = TextEditingController();
  String? _category;
  String? _location;
  String? _photoUrl;
  bool _uploading = false;
  bool _saving = false;
  String? _error;

  bool get _ent => _type == 'entrepreneur';

  bool get _canContinue {
    switch (_step) {
      case 1:
        return _name.text.trim().length >= 2 && _company.text.trim().length >= 2;
      case 2:
        return _category != null && _location != null;
      default:
        return true;
    }
  }

  Future<void> _pickPhoto() async {
    final auth = context.read<AuthProvider>();
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 75);
    if (f == null) return;
    setState(() => _uploading = true);
    try {
      final url = await auth.uploadAvatar(await f.readAsBytes(), f.name);
      if (mounted) setState(() => _photoUrl = url);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _finish() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<AuthProvider>().createProfile({
        'name': _name.text.trim(),
        'company': _company.text.trim(),
        'userType': _type,
        'category': _category,
        'location': _location,
        if (_bio.text.trim().isNotEmpty) 'bio': _bio.text.trim(),
        if (_services.text.trim().isNotEmpty) 'services': _services.text.trim(),
        if (_photoUrl != null) 'photoURL': _photoUrl,
      });
    } catch (e) {
      if (mounted) setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _company, _bio, _services]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: _step > 0 ? IconButton(icon: const Icon(Icons.chevron_left, size: 30), onPressed: _saving ? null : () => setState(() => _step--)) : null,
        actions: [TextButton(onPressed: () => context.read<AuthProvider>().logout(), child: Text('Log out', style: TextStyle(color: p.muted)))],
        title: _step > 0
            ? ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: _step / 3, minHeight: 5, backgroundColor: p.field, color: kGold))
            : null,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: _step == 0 ? _pickType(p) : _stepBody()),
        ),
      ),
    );
  }

  Widget _pickType(Pal p) {
    Widget card(String type, IconData icon, String title, String sub) => GestureDetector(
          onTap: () => setState(() {
            _type = type;
            _step = 1;
          }),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: p.border)),
            child: Row(children: [
              Container(width: 52, height: 52, decoration: const BoxDecoration(gradient: kGoldGradient, shape: BoxShape.circle), child: Icon(icon, color: p.onGold)),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(sub, style: TextStyle(color: p.muted, fontWeight: FontWeight.w500)),
              ])),
              Icon(Icons.chevron_right, color: p.muted),
            ]),
          ),
        );
    return ListView(padding: const EdgeInsets.all(24), children: [
      const SizedBox(height: 8),
      const Center(child: LogoStack(size: 64)),
      const SizedBox(height: 28),
      const Text('Set up your free page', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text('Tell us who you are. It takes under a minute.', style: TextStyle(color: p.muted, fontWeight: FontWeight.w500)),
      const SizedBox(height: 22),
      card('entrepreneur', Icons.business_center_outlined, 'Entrepreneur', 'Run a business, offer products & services'),
      const SizedBox(height: 14),
      card('job_seeker', Icons.person_outline, 'Job Seeker', 'Find jobs, share skills and connect'),
    ]);
  }

  Widget _stepBody() {
    final isLast = _step == 3;
    Widget body;
    switch (_step) {
      case 1:
        body = _nameStep();
        break;
      case 2:
        body = _categoryStep();
        break;
      default:
        body = _detailsStep();
    }
    return Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(24, 12, 24, 24), children: [body])),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600))),
          SizedBox(
            width: double.infinity,
            child: GoldButton(
              label: isLast ? 'Create my page' : 'Continue',
              loading: _saving,
              onPressed: _canContinue ? (isLast ? _finish : () => setState(() => _step++)) : null,
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _nameStep() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('About you', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 22),
        AppField(controller: _name, label: 'Full name *', hint: 'e.g. Tanmay Kulkarni', caps: TextCapitalization.words, autofocus: true, onChanged: (_) => setState(() {})),
        const SizedBox(height: 18),
        AppField(
          controller: _company,
          label: _ent ? 'Company name *' : 'Current role *',
          hint: _ent ? 'e.g. SkyQ Tech' : 'e.g. Accounts Executive',
          caps: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Text('Your @handle is made from this name.', style: TextStyle(color: Pal.of(context).muted, fontSize: 12.5, fontWeight: FontWeight.w500)),
      ]);

  Widget _categoryStep() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Where and what?', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 22),
        PickerField(label: 'Category', required: true, options: kProfileCategories, value: _category, hint: 'Select a category', onChanged: (v) => setState(() => _category = v)),
        const SizedBox(height: 18),
        PickerField(label: 'Location', required: true, options: kLocations, value: _location, hint: 'Select your location', onChanged: (v) => setState(() => _location = v)),
      ]);

  Widget _detailsStep() {
    final p = Pal.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Almost done', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
      const SizedBox(height: 22),
      Row(children: [
        GestureDetector(
          onTap: _uploading ? null : _pickPhoto,
          child: Stack(alignment: Alignment.center, children: [
            Avatar(name: _name.text, size: 76, photoUrl: _photoUrl),
            if (_uploading) const LogoLoader(size: 32),
          ]),
        ),
        const SizedBox(width: 16),
        Expanded(child: Text(_photoUrl == null ? 'Add a photo (optional)' : 'Tap to change photo', style: TextStyle(color: p.muted, fontWeight: FontWeight.w600))),
      ]),
      const SizedBox(height: 22),
      AppField(controller: _bio, label: 'Short bio (optional)', hint: 'What do you do? Max 160 characters', maxLines: 2, maxLength: 160, caps: TextCapitalization.sentences),
      const SizedBox(height: 18),
      AppField(
        controller: _services,
        label: _ent ? 'Products & services (optional)' : 'Skills & services (optional)',
        hint: 'One per line',
        maxLines: 4,
        maxLength: 600,
        caps: TextCapitalization.sentences,
      ),
    ]);
  }
}

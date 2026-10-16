import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../auth_provider.dart';
import '../location.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/pickers.dart';

/// Edit profile / resume (PATCH /me/profile, only changed fields are sent).
class EditProfileScreen extends StatefulWidget {
  final Profile profile;
  const EditProfileScreen({super.key, required this.profile});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final _name = TextEditingController(text: widget.profile.name);
  late final _company = TextEditingController(text: widget.profile.company);
  late final _bio = TextEditingController(text: widget.profile.bio ?? '');
  late final _services = TextEditingController(text: widget.profile.services.join('\n'));
  late final _skills = TextEditingController(text: widget.profile.skills.join(', '));
  late final _experience = TextEditingController(text: widget.profile.experience ?? '');
  late final _education = TextEditingController(text: widget.profile.education ?? '');
  late String _category = widget.profile.category;
  late String _location = widget.profile.location;
  late String? _photo = widget.profile.photoUrl;
  late String? _banner = widget.profile.bannerUrl;
  late final _gst = TextEditingController(text: widget.profile.gstin ?? '');
  bool _locating = false;
  bool _saving = false;
  bool _uploading = false;

  Profile get _p => widget.profile;

  Future<void> _pickPhoto() async {
    final auth = context.read<AuthProvider>();
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 75);
    if (f == null) return;
    setState(() => _uploading = true);
    try {
      final url = await auth.uploadAvatar(await f.readAsBytes(), f.name);
      if (mounted) setState(() => _photo = url);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickBanner() async {
    final api = context.read<AuthProvider>().api;
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 75);
    if (f == null) return;
    setState(() => _uploading = true);
    try {
      final url = await api.uploadImage(await f.readAsBytes(), f.name);
      if (mounted) setState(() => _banner = url);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _detect() async {
    setState(() => _locating = true);
    try {
      final h = await currentLocation();
      if (mounted) setState(() => _location = h.node);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    final patch = <String, dynamic>{};
    void ifChanged(String k, String now, String? before) {
      if (now.trim() != (before ?? '')) patch[k] = now.trim();
    }

    ifChanged('name', _name.text, _p.name);
    ifChanged('company', _company.text, _p.company);
    ifChanged('bio', _bio.text, _p.bio);
    ifChanged('experience', _experience.text, _p.experience);
    ifChanged('education', _education.text, _p.education);
    if (_category != _p.category) patch['category'] = _category;
    if (_location != _p.location) patch['location'] = _location;
    if (_services.text.trim() != _p.services.join('\n')) patch['services'] = _services.text.trim();
    if (_skills.text.trim() != _p.skills.join(', ')) patch['skills'] = _skills.text.trim();
    if (_photo != null && _photo != _p.photoUrl) patch['photoURL'] = _photo;
    if (_banner != _p.bannerUrl) patch['bannerURL'] = _banner;
    final gst = _gst.text.trim().toUpperCase();
    if (gst != (_p.gstin ?? '')) {
      if (gst.isNotEmpty && !RegExp(r'^\d{2}[A-Z]{5}\d{4}[A-Z][A-Z\d]Z[A-Z\d]$').hasMatch(gst)) {
        return toast(context, 'Enter a valid 15-character GSTIN', error: true);
      }
      patch['gstNumber'] = gst;
    }
    if (patch.isEmpty) return Navigator.pop(context, false);
    setState(() => _saving = true);
    try {
      await context.read<AuthProvider>().updateProfile(patch);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        toast(context, '$e', error: true);
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _company, _bio, _services, _skills, _experience, _education, _gst]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final job = _p.isJobSeeker;
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile', style: TextStyle(fontWeight: FontWeight.w700))),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.all(20), children: [
              // cover photo, shown behind the profile header
              GestureDetector(
                onTap: _uploading ? null : _pickBanner,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    height: 96,
                    decoration: const BoxDecoration(gradient: kGoldGradient),
                    child: Stack(fit: StackFit.expand, children: [
                      if (_banner != null) Image.network(mediaUrl(_banner!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Container(
                          margin: const EdgeInsets.all(8),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                          child: Text(_banner == null ? 'Add cover photo' : 'Change cover', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                GestureDetector(
                  onTap: _uploading ? null : _pickPhoto,
                  child: Stack(alignment: Alignment.center, children: [Avatar(name: _name.text, size: 76, photoUrl: _photo), if (_uploading) const LogoLoader(size: 32)]),
                ),
                const SizedBox(width: 16),
                Expanded(child: Text('Tap to change your photo', style: TextStyle(color: p.muted, fontWeight: FontWeight.w500))),
              ]),
              const SizedBox(height: 20),
              AppField(controller: _name, label: 'Full name', caps: TextCapitalization.words, maxLength: 60, onChanged: (_) => setState(() {})),
              const SizedBox(height: 14),
              AppField(controller: _company, label: job ? 'Current role' : 'Company name', caps: TextCapitalization.words, maxLength: 80),
              const SizedBox(height: 14),
              PickerField(label: 'Category', options: kProfileCategories, value: _category, onChanged: (v) => setState(() => _category = v)),
              const SizedBox(height: 14),
              PickerField(label: 'Location', options: kLocations, value: _location, onChanged: (v) => setState(() => _location = v)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _locating ? null : _detect,
                  icon: _locating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location, size: 18, color: kGold),
                  label: const Text('Detect my location', style: TextStyle(color: kGold, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 14),
              AppField(controller: _bio, label: 'Short bio', maxLines: 2, maxLength: 160, caps: TextCapitalization.sentences),
              if (!job) ...[
                const SizedBox(height: 14),
                AppField(controller: _services, label: 'Services (one per line)', maxLines: 4, maxLength: 600),
                const SizedBox(height: 14),
                AppField(controller: _gst, label: 'GSTIN (optional)', hint: '15 characters, e.g. 27ABCDE1234F1Z5', maxLength: 15, caps: TextCapitalization.characters),
              ] else ...[
                const SizedBox(height: 14),
                AppField(controller: _skills, label: 'Skills (comma separated)', hint: 'e.g. Tally, GST, Excel', maxLines: 2, maxLength: 400),
                const SizedBox(height: 14),
                AppField(controller: _experience, label: 'Experience (one per line)', hint: 'Role · Company · Years', maxLines: 4, maxLength: 800),
                const SizedBox(height: 14),
                AppField(controller: _education, label: 'Education (one per line)', hint: 'Degree · College · Year', maxLines: 3, maxLength: 400),
              ],
            ]),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 16), child: SizedBox(width: double.infinity, child: GoldButton(label: 'Save', loading: _saving, onPressed: _name.text.trim().length >= 2 ? _save : null))),
        ]),
      ),
    );
  }
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../contact_sync.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/whatsapp_icon.dart';
import 'profile.dart' show ProfileActionBtn;

/// A contact saved only on this phone (no WEBWEB page), as a page like a member's: the picture, the name and company, Call and
/// WhatsApp, then everything saved on it and an invitation to make a page.
class LocalContactScreen extends StatelessWidget {
  final String name;
  final String org;
  final Uint8List? photo;
  final List<String> phones;
  final List<String> emails;
  final List<String> places;
  const LocalContactScreen({super.key, required this.name, required this.org, required this.photo, required this.phones, required this.emails, required this.places});

  static void _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);
  static String _tel(String n) => 'tel:${n.replaceAll(RegExp(r'[^\d+]'), '')}';

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final ten = phones.map(ContactSync.mobile10).whereType<String>().firstOrNull;
    final invite = '${t('I have a free business page on WEBWEB, the AI Phonebook. Make yours so customers can find and review you:')} https://webweb.ai';
    Widget row(IconData i, String text, VoidCallback onTap, {Widget? trailing}) => InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Icon(i, color: p.muted, size: 22),
              const SizedBox(width: 14),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
              if (trailing != null) trailing,
            ]),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
        Center(child: photo != null && photo!.isNotEmpty ? ClipOval(child: Image.memory(photo!, width: 96, height: 96, fit: BoxFit.cover, gaplessPlayback: true)) : Avatar(name: name, size: 96)),
        const SizedBox(height: 12),
        Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        if (org.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(org, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: p.muted))),
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(t('Saved on this phone'), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.muted))),
        const SizedBox(height: 16),
        if (phones.isNotEmpty)
          Row(children: [
            Expanded(child: ProfileActionBtn(label: t('Call'), leading: const Icon(Icons.call_rounded, size: 16, color: Color(0xFF1E9E5A)), gold: true, onTap: () => _open(_tel(phones.first)))),
            if (ten != null) ...[
              const SizedBox(width: 10),
              Expanded(child: ProfileActionBtn(label: 'WhatsApp', leading: const WhatsAppIcon(size: 18), onTap: () => _open('https://wa.me/91$ten'))),
            ],
          ]),
        const SizedBox(height: 12),
        for (final ph in phones)
          row(Icons.phone_rounded, ph, () => _open(_tel(ph)),
              trailing: ContactSync.mobile10(ph) != null ? IconButton(tooltip: 'WhatsApp', onPressed: () => _open('https://wa.me/91${ContactSync.mobile10(ph)}'), icon: const WhatsAppIcon(size: 24)) : null),
        for (final m in emails) row(Icons.mail_outline_rounded, m, () => _open('mailto:$m')),
        for (final a in places) row(Icons.place_outlined, a, () => _open('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(a)}')),
        if (ten != null) ...[
          const Divider(height: 28),
          row(Icons.person_add_alt_1_rounded, t('Invite to the phonebook'), () => _open('https://wa.me/91$ten?text=${Uri.encodeComponent(invite)}')),
        ],
      ]),
    );
  }
}

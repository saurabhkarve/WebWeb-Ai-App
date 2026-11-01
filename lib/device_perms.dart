import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'contact_sync.dart';
import 'i18n.dart';
import 'models.dart';
import 'permissions.dart';
import 'screens/service_contacts_sheet.dart';

/// What the phone has allowed, for the profile's strength: the page is not complete until location and contacts are
/// allowed on the phone (the website cannot grant them, so only the app counts them). Read again each time the app
/// comes back to the front, and after the member answers a prompt.
class DevicePerms extends ChangeNotifier {
  DevicePerms._();
  static final i = DevicePerms._();

  bool loaded = false;
  bool location = false, contacts = false;

  Future<void> refresh() async {
    if (!ContactSync.supported) return;
    final l = await Permissions.granted(Need.location);
    final c = await Permissions.granted(Need.contacts);
    if (loaded && l == location && c == contacts) return;
    loaded = true;
    location = l;
    contacts = c;
    notifyListeners();
  }

  /// The strength with the two phone steps added (10% each); null stays null.
  Completion? apply(Completion? c) {
    if (c == null || !loaded || !ContactSync.supported) return c;
    final items = [
      ...c.items,
      CompletionItem('perm_location', 'Allow location on your phone', 10, location),
      CompletionItem('perm_contacts', 'Share service contacts from your phone', 10, contacts),
    ];
    final total = items.fold<int>(0, (n, e) => n + e.weight);
    final done = items.where((e) => e.done).fold<int>(0, (n, e) => n + e.weight);
    // never 100 while a step is open, whatever the rounding
    final pct = done >= total ? 100 : (done * 100 / total).floor().clamp(0, 99);
    return Completion(pct, items, c.badges);
  }

  /// A tap on a phone step of the strength. Returns true when it was one (and handled).
  static Future<bool> handle(BuildContext context, CompletionItem? item) async {
    if (item == null || !item.key.startsWith('perm_')) return false;
    if (item.key == 'perm_location') {
      await Permissions.ensure(context, Need.location, reason: t('So we can show you people and asks near you.'));
    } else {
      await showServiceContactsSheet(context);
    }
    await i.refresh();
    return true;
  }
}

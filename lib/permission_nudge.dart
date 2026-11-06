import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'contact_sync.dart';
import 'i18n.dart';
import 'native_calls.dart';
import 'permissions.dart';
import 'screens/service_contacts_sheet.dart';

/// A note sent by hand from Admin ("Ask to allow") was tapped: open the screen that explains the permission and has its
/// Allow button (Settings when it can only be turned on there). Does nothing when it is already allowed. [perm] is the
/// name the app reports for it (contacts, location, camera, microphone, notifications, battery, fullScreenCalls).
Future<void> handlePermissionNudge(BuildContext context, String perm) async {
  Future<void> ensure(Need need, String reason) async {
    await Permissions.ensure(context, need, reason: reason);
  }

  switch (perm) {
    case 'contacts':
      if (ContactSync.supported && !await Permissions.granted(Need.contacts) && context.mounted) {
        await showServiceContactsSheet(context, invite: true);
      }
    case 'location':
      await ensure(Need.location, t('So asks and contacts near you show first. Only used while the app is open.'));
    case 'camera':
      await ensure(Need.camera, t('To take photos for your asks and page, and for video calls.'));
    case 'microphone':
      await ensure(Need.microphone, t('So members can hear you on calls and voice asks.'));
    case 'notifications':
      await ensure(Need.notifications, t('So you do not miss replies, messages and calls.'));
    case 'battery':
      if (await Permission.ignoreBatteryOptimizations.isGranted || !context.mounted) break;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('Do not miss calls')),
          content: Text(t('Let WEBWEB run in the background so calls and messages reach you on time.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Not now'))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Allow'))),
          ],
        ),
      );
      if (ok == true) await Permission.ignoreBatteryOptimizations.request();
    case 'fullScreenCalls':
      await NativeCalls.requestPermissions();
  }
}

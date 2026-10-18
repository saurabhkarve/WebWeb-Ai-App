import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'i18n.dart';
import 'theme.dart';
import 'widgets.dart';

/// What the app may ask for, and why (shown in the pop-up before the phone's own prompt).
enum Need { location, contacts, camera, microphone, notifications }

extension on Need {
  Permission get permission => switch (this) {
        Need.location => Permission.locationWhenInUse, // never in the background
        Need.contacts => Permission.contacts,
        Need.camera => Permission.camera,
        Need.microphone => Permission.microphone,
        Need.notifications => Permission.notification,
      };

  WI get icon => switch (this) {
        Need.location => WI.pin,
        Need.contacts => WI.contactCard,
        Need.camera => WI.camera,
        Need.microphone => WI.mic,
        Need.notifications => WI.bell,
      };

  String get title => switch (this) {
        Need.location => 'Allow location',
        Need.contacts => 'Allow contacts',
        Need.camera => 'Allow camera',
        Need.microphone => 'Allow microphone',
        Need.notifications => 'Allow notifications',
      };

  /// Shown under the reason: what the app does NOT do, so people can decide with confidence.
  String get promise => switch (this) {
        Need.location => 'Used only while you use the app, never in the background. Your exact location is never shown to other members.',
        Need.contacts => 'Only the contacts you pick are shared. Your phone book is never uploaded.',
        Need.camera => 'Used only when you take a photo or turn on video in a call.',
        Need.microphone => 'Used only during calls. Calls are never recorded.',
        Need.notifications => 'Only for messages, calls and replies to your asks.',
      };
}

/// One place for every permission, the same way each time (WhatsApp-style):
/// 1. Checks the permission right before it is needed, every time (it may have been turned off in Settings).
/// 2. Not given yet: a pop-up says why it is needed, then "Allow" shows the phone's own prompt.
/// 3. Turned off for good (or "Don't ask again"): the pop-up explains how, "Open Settings" goes there, and
///    when the person comes back the permission is checked again; the pop-up closes on its own once it is on.
/// 4. Returns true only when the permission is really granted, so the caller can go ahead.
/// For location, the phone's location service (GPS) must also be on.
class Permissions {
  static bool get _phone => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  static Future<bool> granted(Need need) async {
    if (!_phone) return true;
    final s = await need.permission.status;
    return s.isGranted || s.isLimited;
  }

  /// [reason]: one translated sentence on what it is for right now, e.g. "To share your location in this chat."
  static Future<bool> ensure(BuildContext context, Need need, {required String reason}) async {
    if (!_phone) return true;
    if (need == Need.location && !await Geolocator.isLocationServiceEnabled()) {
      if (!context.mounted) return false;
      final on = await _dialog(context, need, reason: reason, mode: _Mode.service);
      if (!on) return false;
    }
    var s = await need.permission.status;
    if (s.isGranted || s.isLimited) return true;
    if (!context.mounted) return false;
    // iOS reports "permanently denied" once the person said no; Android after "Don't allow" twice
    final blocked = s.isPermanentlyDenied || s.isRestricted;
    return _dialog(context, need, reason: reason, mode: blocked ? _Mode.settings : _Mode.ask);
  }

  static Future<bool> _dialog(BuildContext context, Need need, {required String reason, required _Mode mode}) async {
    final r = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _PermissionDialog(need: need, reason: reason, mode: mode),
    );
    return r == true;
  }
}

enum _Mode { ask, settings, service }

class _PermissionDialog extends StatefulWidget {
  final Need need;
  final String reason;
  final _Mode mode;
  const _PermissionDialog({required this.need, required this.reason, required this.mode});
  @override
  State<_PermissionDialog> createState() => _PermissionDialogState();
}

class _PermissionDialogState extends State<_PermissionDialog> with WidgetsBindingObserver {
  late _Mode _mode = widget.mode;
  bool _busy = false;
  bool _wentToSettings = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from Settings: check again, and carry on by itself when it is now allowed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _wentToSettings) _recheck();
  }

  Future<void> _recheck() async {
    if (_mode == _Mode.service) {
      if (await Geolocator.isLocationServiceEnabled()) {
        if (mounted) Navigator.pop(context, true);
      } else if (mounted) {
        setState(() => _note = t('Location is still off.'));
      }
      return;
    }
    final s = await widget.need.permission.status;
    if (!mounted) return;
    if (s.isGranted || s.isLimited) {
      Navigator.pop(context, true);
    } else {
      setState(() => _note = t('It is still turned off.'));
    }
  }

  Future<void> _primary() async {
    setState(() {
      _busy = true;
      _note = null;
    });
    try {
      switch (_mode) {
        case _Mode.service:
          _wentToSettings = true;
          await Geolocator.openLocationSettings();
        case _Mode.settings:
          _wentToSettings = true;
          await openAppSettings();
        case _Mode.ask:
          final s = await widget.need.permission.request();
          if (!mounted) return;
          if (s.isGranted || s.isLimited) {
            Navigator.pop(context, true);
            return;
          }
          // said no: from now on only Settings can turn it on
          setState(() {
            _mode = _Mode.settings;
            _note = t('Permission was not given.');
          });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final need = widget.need;
    final (title, how, button) = switch (_mode) {
      _Mode.service => (
          t('Turn on location'),
          t('Location is switched off on your phone. Turn it on, then come back here.'),
          t('Open location settings'),
        ),
      _Mode.settings => (
          t(need.title),
          t('It is turned off for WEBWEB in your phone settings. Open Settings, tap Permissions if you see it, and allow it. Then come back here.'),
          t('Open Settings'),
        ),
      _Mode.ask => (t(need.title), null, t('Allow')),
    };
    return AlertDialog(
      backgroundColor: p.canvas,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: kGold.withValues(alpha: .18), shape: BoxShape.circle),
          child: Center(child: WIcon(need.icon, size: 24, color: p.text)),
        ),
        const SizedBox(height: 14),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(widget.reason, style: const TextStyle(fontSize: 14, height: 1.45)),
        if (how != null) ...[
          const SizedBox(height: 8),
          Text(how, style: const TextStyle(fontSize: 14, height: 1.45)),
        ],
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: WIcon(WI.lock, size: 14, color: p.muted)),
          const SizedBox(width: 6),
          Expanded(child: Text(t(need.promise), style: TextStyle(fontSize: 12, color: p.muted, height: 1.4))),
        ]),
        if (_note != null) ...[
          const SizedBox(height: 10),
          Text(_note!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.danger)),
        ],
      ]),
      actions: [
        Row(children: [
          Expanded(child: GoldButton(label: t('Not now'), outlined: true, height: 44, onPressed: () => Navigator.pop(context, false))),
          const SizedBox(width: 8),
          Expanded(child: GoldButton(label: button, height: 44, loading: _busy, onPressed: _busy ? null : _primary)),
        ]),
      ],
    );
  }
}

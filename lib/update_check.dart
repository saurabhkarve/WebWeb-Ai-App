import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config.dart';
import 'i18n.dart';
import 'theme.dart';
import 'widgets.dart';

/// App updates, set in Admin > App updates (GET /app/release). Checked on launch and when the app comes back
/// after a few hours. Older than the minimum version: a full-screen "Update required" that cannot be closed.
/// Older than the latest version: an "Update available" card, once per new version.
class UpdateGate extends StatefulWidget {
  final Widget child;
  const UpdateGate({super.key, required this.child});

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> with WidgetsBindingObserver {
  static const _dismissedKey = 'update_dismissed_version';
  bool _force = false;
  String? _offer; // latest version offered (optional update)
  String? _storeUrl, _message;
  DateTime? _checkedAt;

  bool get _supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && (_force || _checkedAt == null || DateTime.now().difference(_checkedAt!) > const Duration(hours: 3))) _check();
  }

  Future<void> _check() async {
    if (!_supported) return;
    _checkedAt = DateTime.now();
    try {
      final platform = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
      final res = await http.get(Uri.parse('$apiUrl/app/release?platform=$platform')).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return;
      final r = jsonDecode(res.body) as Map<String, dynamic>;
      final info = await PackageInfo.fromPlatform();
      final mine = '${info.version}+${info.buildNumber}';
      final latest = '${r['latest'] ?? '0.0.0'}';
      final force = compareVersions(mine, '${r['min'] ?? '0.0.0'}') < 0;
      String? offer;
      if (!force && compareVersions(mine, latest) < 0) {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getString(_dismissedKey) != latest) offer = latest;
      }
      if (!mounted) return;
      setState(() {
        _force = force;
        _offer = offer;
        _storeUrl = r['storeUrl'] as String?;
        _message = (r['message'] as String?)?.trim();
      });
    } catch (_) {
      // offline or the server is unreachable: never block the app on this check
    }
  }

  Future<void> _openStore() async {
    final url = _storeUrl;
    if (url == null || url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _later() async {
    final v = _offer;
    setState(() => _offer = null);
    if (v != null) (await SharedPreferences.getInstance()).setString(_dismissedKey, v);
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Stack(children: [
      widget.child,
      if (_force)
        Positioned.fill(
          child: PopScope(
            canPop: false,
            child: Material(
              color: p.canvas,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Center(child: LogoMark(size: 64)),
                    const SizedBox(height: 24),
                    Text(t('Update required'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Text(
                      _message?.isNotEmpty == true ? _message! : t('This version of WEBWEB AI is no longer supported. Update the app to keep using it.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: p.muted, height: 1.4),
                    ),
                    const SizedBox(height: 28),
                    GoldButton(label: t('Update now'), onPressed: _openStore),
                  ]),
                ),
              ),
            ),
          ),
        )
      else if (_offer != null)
        Positioned(
          left: 12,
          right: 12,
          bottom: MediaQuery.paddingOf(context).bottom + 84,
          child: Material(
            color: p.card,
            elevation: 8,
            shadowColor: const Color(0x611E1E1E),
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(t('Update available'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  _message?.isNotEmpty == true ? _message! : t('A new version of WEBWEB AI is ready, with fixes and improvements.'),
                  style: TextStyle(fontSize: 13.5, color: p.muted, height: 1.35),
                ),
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(onPressed: _later, child: Text(t('Later'))),
                  const SizedBox(width: 6),
                  GoldButton(
                      label: t('Update app'),
                      onPressed: () {
                        _openStore();
                        _later();
                      }),
                ]),
              ]),
            ),
          ),
        ),
    ]);
  }
}

/// Compares versions like 1.2.0+7: the numbers first, then the build number after "+".
int compareVersions(String a, String b) {
  List<int> parts(String v) {
    final s = v.split('+');
    final n = s[0].split('.').map((x) => int.tryParse(x) ?? 0).toList();
    while (n.length < 3) {
      n.add(0);
    }
    return [...n.take(3), int.tryParse(s.length > 1 ? s[1] : '0') ?? 0];
  }

  final x = parts(a), y = parts(b);
  for (var i = 0; i < 4; i++) {
    if (x[i] != y[i]) return x[i] < y[i] ? -1 : 1;
  }
  return 0;
}

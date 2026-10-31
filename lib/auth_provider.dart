import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'config.dart';
import 'crash_reporter.dart';
import 'offline_cache.dart';
import 'outbox.dart';
import 'models.dart';

/// Session + profile. Login is the same two calls the web uses (`/auth/send-otp`, `/auth/verify-otp`);
/// the profile comes from `GET /me` and stays null until onboarding is finished.
class AuthProvider extends ChangeNotifier {
  late final Api api = Api(() => token, onUnauthorized: () => logout(), onRenewed: _renewed);

  String? token;
  String? userId;
  Profile? profile;
  bool ready = false; // saved session checked
  bool profileLoaded = false; // /me answered (profile may still be null = needs onboarding)
  bool loading = false;
  bool otpSent = false;
  String phone = ''; // 10 digits
  /// set when signing in by email instead of a mobile number (web "Use email instead")
  String? email;
  /// the signed-in account's email, when it has one (from /me)
  String? accountEmail;
  String? error;
  /// Two-step verification is on for this account: the sign-in waits for an authenticator or recovery code
  /// (POST /auth/two-step with this ticket) before there is a session.
  String? twoStepTicket;
  /// recovery codes left after one was used to sign in (shown once, then cleared)
  int? recoveryCodesLeft;
  /// after 2 wrong codes every try needs a captcha first ([captchaGate]: the last try was refused for lacking one)
  bool captchaNeeded = false;
  bool captchaGate = false;

  bool get isLoggedIn => token != null;

  /// Runs while the token is still valid (e.g. to drop this device's push token).
  Future<void> Function()? beforeLogout;
  bool _loggingOut = false;

  Future<void> init() async {
    // whatever happens below, the opening screen must end: a stuck read or a slow network never leaves it up for good
    try {
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 6));
      // for the iPhone's own code (AppDelegate.onDecline), which tells the API a call was declined when the app is closed
      prefs.setString('apiUrl', apiUrl);
      final saved = prefs.getString('token');
      if (saved != null) {
        token = saved;
        await loadProfile(silent: true).timeout(const Duration(seconds: 10), onTimeout: () {});
      }
    } catch (_) {
      // no saved session readable: the login screen
    }
    ready = true;
    notifyListeners();
  }

  Future<void> loadProfile({bool silent = false}) async {
    try {
      final d = await api.get('/me') as Map;
      userId = d['user']?['id'] as String?;
      CrashReporter.setUser(userId);
      final ph = '${d['user']?['phone'] ?? ''}'.replaceAll(RegExp(r'\D'), '');
      if (ph.length >= 10) phone = ph.substring(ph.length - 10);
      accountEmail = d['user']?['email'] as String?;
      profile = d['profile'] == null ? null : Profile.fromJson(d['profile'] as Map);
      profileLoaded = true;
      error = null;
    } catch (e) {
      if (token != null) {
        error = _msg(e);
        profileLoaded = false;
      }
    }
    if (!silent) notifyListeners();
  }

  // ---------- login ----------
  Future<bool> sendOtp(String phone10) => _send({'phone': phone10}, () {
        phone = phone10;
        email = null;
      });

  Future<bool> sendEmailOtp(String address) {
    final clean = address.trim().toLowerCase();
    return _send({'email': clean}, () => email = clean);
  }

  /// Sends the code again to the same number or email.
  Future<bool> resendOtp() => email != null ? sendEmailOtp(email!) : sendOtp(phone);

  Future<bool> _send(Map<String, dynamic> target, void Function() onSent) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await api.post('/auth/send-otp', target);
      onSent();
      otpSent = true;
      return true;
    } catch (e) {
      error = _msg(e);
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> verifyOtp(String code, {String? captcha}) async {
    loading = true;
    error = null;
    captchaGate = false;
    notifyListeners();
    try {
      final d = await api.post('/auth/verify-otp', {if (email != null) 'email': email else 'phone': phone, 'code': code, if (captcha != null) 'captcha': captcha}) as Map;
      captchaNeeded = false;
      if (d['twoStep'] == true) {
        twoStepTicket = d['ticket'] as String;
        return true;
      }
      await _signedIn(d['token'] as String);
      return true;
    } catch (e) {
      _noteCaptcha(e);
      error = _msg(e);
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void _noteCaptcha(Object e) {
    if (e is! ApiException) return;
    if (e.status == 428) captchaGate = true;
    if (e.status == 428 || e.captcha) captchaNeeded = true;
  }

  /// Second step: a code from the authenticator app (or a recovery code) for [twoStepTicket].
  Future<bool> verifyTwoStep(String code, {String? captcha}) async {
    if (twoStepTicket == null) return false;
    loading = true;
    error = null;
    captchaGate = false;
    notifyListeners();
    try {
      final d = await api.post('/auth/two-step', {'ticket': twoStepTicket, 'code': code.trim(), if (captcha != null) 'captcha': captcha}) as Map;
      captchaNeeded = false;
      recoveryCodesLeft = (d['recoveryCodesLeft'] as num?)?.toInt();
      await _signedIn(d['token'] as String);
      return true;
    } catch (e) {
      _noteCaptcha(e);
      if (e is ApiException && e.status == 401) {
        // the ticket ran out (10 minutes): start again from the number
        twoStepTicket = null;
        otpSent = false;
        error = 'This sign-in has expired. Please start again.';
      } else {
        error = _msg(e);
      }
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// a renewed session replaces the saved one quietly (no rebuild: nothing on screen changes)
  Future<void> _renewed(String t) async {
    token = t;
    try {
      (await SharedPreferences.getInstance()).setString('token', t);
    } catch (_) {}
  }

  Future<void> _signedIn(String t) async {
    token = t;
    twoStepTicket = null;
    (await SharedPreferences.getInstance()).setString('token', t);
    otpSent = false;
    profileLoaded = false;
    await loadProfile(silent: true);
  }

  void backToLogin() {
    otpSent = false;
    twoStepTicket = null;
    error = null;
    notifyListeners();
  }

  // ---------- profile ----------
  /// One-time onboarding (POST /me/profile): name, @handle and type. Returns the new profile without
  /// switching to the app yet, so onboarding can show its optional second step first.
  Future<Profile> createProfile(Map<String, dynamic> body) async =>
      Profile.fromJson((await api.post('/me/profile', body) as Map)['profile'] as Map);

  /// PATCH /me/profile and return the updated profile (with its completion), without a reload.
  Future<Profile> patchProfile(Map<String, dynamic> patch) async =>
      Profile.fromJson((await api.patch('/me/profile', patch) as Map)['profile'] as Map);

  Future<void> updateProfile(Map<String, dynamic> patch) async {
    await api.patch('/me/profile', patch);
    await loadProfile();
  }

  /// Uploads a profile photo ([kind] avatar) or cover ([kind] cover) and returns its URL (to pass as
  /// `photoURL` / `bannerURL`). The server crops it to the exact shape and keeps a large and a small size.
  Future<String> uploadAvatar(List<int> bytes, String filename, {String kind = 'avatar'}) async =>
      (await api.upload('/me/photo?kind=$kind', bytes, filename, Api.mimeOf(filename)))['url'] as String;

  /// Business pages under this sign-in (GET /me/accounts): the page itself and the others.
  Future<List<Map>> accounts() async => ((await api.get('/me/accounts') as Map)['accounts'] as List).cast<Map>();

  /// A new session for another page of this sign-in ([uid]), or for a new empty page (null; onboarding opens next).
  Future<void> switchAccount(String? uid) async {
    final d = (uid == null ? await api.post('/me/accounts', {}) : await api.post('/me/accounts/switch', {'uid': uid})) as Map;
    // nothing of the last page stays on screen, in the cache or in the live connection
    profile = null;
    profileLoaded = false;
    notifyListeners();
    await OfflineCache.clear();
    await Outbox.clear();
    await _signedIn(d['token'] as String);
    notifyListeners();
  }

  Future<void> logout() async {
    if (_loggingOut) return; // a 401 inside beforeLogout calls logout again
    _loggingOut = true;
    try {
      if (token != null) await beforeLogout?.call();
    } catch (_) {
    } finally {
      _loggingOut = false;
    }
    token = null;
    userId = null;
    CrashReporter.setUser(null);
    profile = null;
    profileLoaded = false;
    otpSent = false;
    twoStepTicket = null;
    error = null;
    (await SharedPreferences.getInstance()).remove('token');
    await OfflineCache.clear(); // nothing of this account stays on the phone
    await Outbox.clear();
    notifyListeners();
  }

  String _msg(Object e) => e is ApiException ? e.message : 'Cannot reach the server.';
}

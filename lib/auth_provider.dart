import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'crash_reporter.dart';
import 'offline_cache.dart';
import 'outbox.dart';
import 'models.dart';

/// Session + profile. Login is the same two calls the web uses (`/auth/send-otp`, `/auth/verify-otp`);
/// the profile comes from `GET /me` and stays null until onboarding is finished.
class AuthProvider extends ChangeNotifier {
  late final Api api = Api(() => token, onUnauthorized: () => logout());

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

  bool get isLoggedIn => token != null;

  /// Runs while the token is still valid (e.g. to drop this device's push token).
  Future<void> Function()? beforeLogout;
  bool _loggingOut = false;

  Future<void> init() async {
    final saved = (await SharedPreferences.getInstance()).getString('token');
    if (saved != null) {
      token = saved;
      await loadProfile(silent: true);
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

  Future<bool> verifyOtp(String code) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final d = await api.post('/auth/verify-otp', {if (email != null) 'email': email else 'phone': phone, 'code': code}) as Map;
      token = d['token'] as String;
      (await SharedPreferences.getInstance()).setString('token', token!);
      otpSent = false;
      profileLoaded = false;
      await loadProfile(silent: true);
      return true;
    } catch (e) {
      error = _msg(e);
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void backToLogin() {
    otpSent = false;
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

  /// Uploads an avatar and returns its URL (to pass as `photoURL`).
  Future<String> uploadAvatar(List<int> bytes, String filename) async =>
      (await api.upload('/me/photo', bytes, filename, Api.mimeOf(filename)))['url'] as String;

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
    error = null;
    (await SharedPreferences.getInstance()).remove('token');
    await OfflineCache.clear(); // nothing of this account stays on the phone
    await Outbox.clear();
    notifyListeners();
  }

  String _msg(Object e) => e is ApiException ? e.message : 'Cannot reach the server.';
}

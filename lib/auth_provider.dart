import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
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
  Future<bool> sendOtp(String phone10) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await api.post('/auth/send-otp', {'phone': phone10});
      phone = phone10;
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
      final d = await api.post('/auth/verify-otp', {'phone': phone, 'code': code}) as Map;
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
  /// One-time onboarding (POST /me/profile). The server makes the @handle from the company name.
  Future<void> createProfile(Map<String, dynamic> body) async {
    await api.post('/me/profile', body);
    await loadProfile();
  }

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
    profile = null;
    profileLoaded = false;
    otpSent = false;
    error = null;
    (await SharedPreferences.getInstance()).remove('token');
    notifyListeners();
  }

  String _msg(Object e) => e is ApiException ? e.message : 'Cannot reach the server.';
}

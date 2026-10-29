import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'config.dart';
import 'offline_cache.dart';

typedef Json = Map<String, dynamic>;

class ApiException implements Exception {
  final String message;
  final int status;
  /// the API wants a captcha with the next try (after 2 wrong sign-in codes); status 428 means this one needed it
  final bool captcha;
  ApiException(this.message, [this.status = 0, this.captcha = false]);
  /// No answer from the server at all (no network, timeout): worth retrying later.
  bool get isNetwork => status == 0;
  @override
  String toString() => message;
}

/// Thin client for the WebWeb API (same contract the web app uses: Bearer JWT, `{error}` on failure).
class Api {
  final String? Function() token;
  final void Function()? onUnauthorized;
  Api(this.token, {this.onUnauthorized});

  Map<String, String> _headers({bool json = false}) => {
        if (token() != null) 'Authorization': 'Bearer ${token()!}',
        if (json) 'Content-Type': 'application/json',
      };

  Uri _u(String path, [Map<String, dynamic>? q]) {
    final query = <String, String>{};
    q?.forEach((k, v) {
      if (v != null) query[k] = '$v';
    });
    return Uri.parse('$apiUrl$path').replace(queryParameters: query.isEmpty ? null : query);
  }

  /// [sent] is the session the request carried: a 401 only ends the session it was sent with, never one that has
  /// since been renewed or signed in again, and never a request made with none (the sign-in itself).
  dynamic _decode(http.Response r, [String? sent]) {
    dynamic data;
    try {
      data = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      data = null;
    }
    if (r.statusCode == 401) {
      if (sent != null && sent == token()) onUnauthorized?.call();
      throw ApiException('Please sign in again.', 401);
    }
    if (r.statusCode >= 400) {
      final msg = data is Map ? data['error'] : null;
      throw ApiException('${msg ?? 'Something went wrong.'}', r.statusCode, data is Map && data['captcha'] == true);
    }
    return data;
  }

  Future<T> _send<T>(Future<http.Response> Function() call) async {
    final sent = token();
    try {
      return _decode(await call().timeout(const Duration(seconds: 25)), sent) as T;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Network error. Check your connection.');
    }
  }

  /// GET. Answers of the common screens are kept on the phone; with no network the last one is returned
  /// instead of an error (see [OfflineCache]), so screens keep working offline.
  Future<dynamic> get(String path, [Map<String, dynamic>? q]) async {
    final keep = token() != null && OfflineCache.cacheable(path, q);
    try {
      return await _send(() async {
        final r = await http.get(_u(path, q), headers: _headers());
        if (keep && r.statusCode == 200) OfflineCache.put(path, q, utf8.decode(r.bodyBytes, allowMalformed: true));
        return r;
      });
    } on ApiException catch (e) {
      if (keep && e.isNetwork) {
        final cached = await OfflineCache.get(path, q);
        if (cached != null) return cached;
      }
      rethrow;
    }
  }

  /// The last answer kept on the phone for a GET (null if none): screens show it at once, then refresh.
  Future<dynamic> cached(String path, [Map<String, dynamic>? q]) => OfflineCache.get(path, q);
  Future<dynamic> post(String path, [Object? body]) =>
      _send(() => http.post(_u(path), headers: _headers(json: true), body: jsonEncode(body ?? {})));
  Future<dynamic> patch(String path, Object body) => _send(() => http.patch(_u(path), headers: _headers(json: true), body: jsonEncode(body)));
  Future<dynamic> put(String path, Object body) => _send(() => http.put(_u(path), headers: _headers(json: true), body: jsonEncode(body)));
  Future<dynamic> delete(String path, [Map<String, dynamic>? q]) => _send(() => http.delete(_u(path, q), headers: _headers()));

  /// Multipart upload (field name `file`). Returns the decoded JSON.
  Future<Json> upload(String path, List<int> bytes, String filename, String mime) async {
    final sent = token();
    try {
      final req = http.MultipartRequest('POST', _u(path))
        ..headers.addAll(_headers())
        ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename, contentType: MediaType.parse(mime)));
      final res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 60)));
      return Map<String, dynamic>.from(_decode(res, sent) as Map);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Upload failed. Check your connection.');
    }
  }

  static String mimeOf(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  /// Uploads a photo for a post/story/product and returns its public URL.
  Future<String> uploadImage(List<int> bytes, String filename) async =>
      (await upload('/media', bytes, filename, mimeOf(filename)))['url'] as String;
}

/// Absolute URL for an image. The API returns absolute URLs for uploads; relative paths are either
/// uploads on the API (`/uploads/...`) or static files of the website (`/demo/...`, as the web serves them).
String mediaUrl(String path) {
  if (path.startsWith('http')) return path;
  if (path.startsWith('/uploads/')) return '$apiUrl$path';
  return '$siteUrl$path';
}

/// The small copy of a profile photo (160px) or cover (750px) that the server keeps next to the large one
/// (av-x.jpg -> av-x_160.jpg); any other URL (older uploads, other sites) comes back unchanged.
String smallImage(String url) {
  // our uploads (av- photo, cv- cover), the starter pictures (/defaults/av|cv/…) and WEBWEB's cover designs (/covers/…)
  final m = RegExp(r'(?:/uploads/(av|cv)-[\w-]+|^/defaults/(av|cv)/[\w-]+|^/covers/[\w-]+)\.jpg$').firstMatch(url);
  if (m == null) return url;
  return url.replaceFirst(RegExp(r'\.jpg$'), (m.group(1) ?? m.group(2)) == 'av' ? '_160.jpg' : '_750.jpg');
}

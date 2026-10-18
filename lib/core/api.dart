import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'bridge.dart';
import 'config.dart';

class ApiError implements Exception {
  final int status;
  final String message;
  final Map<String, dynamic> data;
  ApiError(this.status, this.message, [this.data = const {}]);
  @override
  String toString() => message;
}

typedef Json = Map<String, dynamic>;

const kSessionKey = 'agrisense.session';
const kBaseKey = 'agrisense.base';

/// REST client. The session lives in the secure store that the Android widget also reads,
/// so the widget keeps working while the app is closed.
class Api {
  Api._();
  static final Api i = Api._();

  String base = Cfg.apiUrl;
  Json? session; // { access_token, refresh_token, expires_at (epoch s), user:{email,role} }
  void Function()? onAuthLost;
  Future<bool>? _refreshing;

  static String clean(String u) => u.trim().replaceAll(RegExp(r'/+$'), '');

  Future<void> init() async {
    final saved = await Native.kvGet(kBaseKey);
    base = clean((saved != null && saved.isNotEmpty) ? saved : Cfg.apiUrl);
    await Native.setBaseUrl(base);
    session = await _readStore();
  }

  Future<void> setBase(String url) async {
    base = clean(url.isEmpty ? Cfg.apiUrl : url);
    await Native.kvSet(kBaseKey, base);
    await Native.setBaseUrl(base);
  }

  Future<Json?> _readStore() async {
    try {
      final raw = await Native.kvGet(kSessionKey);
      if (raw == null || raw.isEmpty) return null;
      final d = jsonDecode(raw);
      return d is Map<String, dynamic> ? d : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _save(Json? s) async {
    session = s;
    if (s != null) {
      await Native.kvSet(kSessionKey, jsonEncode(s));
      await Native.setBaseUrl(base);
    } else {
      await Native.kvDelete(kSessionKey);
    }
  }

  Future<Json> _raw(String path, {String method = 'GET', Object? body, String? token}) async {
    final uri = Uri.parse(base + path);
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': 'AgriSense-Flutter',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    try {
      late http.Response res;
      final enc = body == null ? null : jsonEncode(body);
      const to = Duration(seconds: 25);
      switch (method) {
        case 'POST':
          res = await http.post(uri, headers: headers, body: enc).timeout(to);
          break;
        case 'PUT':
          res = await http.put(uri, headers: headers, body: enc).timeout(to);
          break;
        default:
          res = await http.get(uri, headers: headers).timeout(to);
      }
      Json data = {};
      try {
        final d = jsonDecode(utf8.decode(res.bodyBytes));
        if (d is Map<String, dynamic>) data = d;
      } catch (_) {}
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw ApiError(res.statusCode, (data['error'] ?? 'request failed').toString(), data);
      }
      return data;
    } on ApiError {
      rethrow;
    } on TimeoutException {
      throw ApiError(0, 'The server took too long to answer.');
    } catch (_) {
      throw ApiError(0, 'Cannot reach the server.');
    }
  }

  Future<bool> _refresh() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    // The widget / live service may already have refreshed the session.
    final stored = await _readStore();
    if (stored != null && session != null && stored['access_token'] != session!['access_token']) {
      session = stored;
      return true;
    }
    final rt = session?['refresh_token'];
    if (rt == null) return false;
    try {
      final s = await _raw('/api/auth/refresh', method: 'POST', body: {'refresh_token': rt});
      await _save(s);
      return true;
    } on ApiError catch (e) {
      if (e.status == 401 || e.status == 403) {
        await _save(null);
        await Native.clearWidgetData();
      }
      return false;
    }
  }

  /// Authenticated call with one automatic refresh-and-retry.
  Future<Json> call(String path, {String method = 'GET', Object? body}) async {
    if (session == null) throw ApiError(401, 'signed out');
    try {
      return await _raw(path, method: method, body: body, token: session!['access_token'] as String?);
    } on ApiError catch (e) {
      if (e.status != 401) rethrow;
      if (await _refresh()) {
        return _raw(path, method: method, body: body, token: session!['access_token'] as String?);
      }
      if (session == null) onAuthLost?.call();
      rethrow;
    }
  }

  Future<Json> login(String email, String password, String captcha) async {
    final s = await _raw('/api/auth/login',
        method: 'POST', body: {'email': email.trim(), 'password': password, 'captcha': captcha});
    await _save(s);
    return (s['user'] as Json?) ?? {};
  }

  Future<void> logout() async {
    try {
      if (session != null) {
        await _raw('/api/auth/logout', method: 'POST', token: session!['access_token'] as String?);
      }
    } catch (_) {}
    await _save(null);
    await Native.clearWidgetData();
  }

  Future<Json> me() => call('/api/auth/me');
}

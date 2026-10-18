import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'bridge.dart';

/// Fetches a path, optionally polling while [active]. Listen to it like any ChangeNotifier.
class ApiQuery extends ChangeNotifier {
  ApiQuery(this._path, {this.interval});

  String _path;
  final Duration? interval;
  Json? data;
  ApiError? error;
  bool loading = true;

  Timer? _timer;
  bool _active = false;
  bool _disposed = false;
  int _seq = 0;

  String get path => _path;

  @protected
  void onData(Json d) {}

  void setActive(bool v) {
    if (v == _active) return;
    _active = v;
    _timer?.cancel();
    _timer = null;
    if (v) {
      reload();
      if (interval != null) _timer = Timer.periodic(interval!, (_) => reload());
    }
  }

  /// A new path means different data: drop the old and fetch straight away.
  void setPath(String p) {
    if (p == _path) return;
    _path = p;
    data = null;
    error = null;
    loading = true;
    _safeNotify();
    if (_active) reload();
  }

  Future<void> reload() async {
    final my = ++_seq;
    try {
      final d = await Api.i.call(_path);
      if (_disposed || my != _seq) return;
      data = d;
      error = null;
      loading = false;
      onData(d);
    } on ApiError catch (e) {
      if (_disposed || my != _seq) return;
      error = e;
      loading = false;
    }
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

/// The shared live status (readings, alerts, open commands). Every screen reads this one poll,
/// and every fresh answer is also pushed to the home-screen widget.
class StatusStore extends ApiQuery {
  StatusStore._() : super('/api/status', interval: const Duration(seconds: 5));
  static final StatusStore i = StatusStore._();

  @override
  void onData(Json d) {
    Native.pushStatus(jsonEncode(d));
  }

  Json get telemetry => (data?['telemetry'] as Json?) ?? const {};
  bool? get online => data == null ? null : data!['online'] == true;
}

/// Cursor-paged list (events, audit logs).
class PagedQuery extends ChangeNotifier {
  PagedQuery(this.path, this.key);
  final String path;
  final String key;
  List<Json> items = [];
  Object? next;
  bool loading = true;
  ApiError? error;
  bool _disposed = false;

  Future<Json> _page([Object? before]) {
    final sep = path.contains('?') ? '&' : '?';
    return Api.i.call('$path${sep}limit=20${before != null ? '&before=$before' : ''}');
  }

  List<Json> _list(Json d) => ((d[key] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  Future<void> reload() async {
    loading = true;
    _n();
    try {
      final d = await _page();
      items = _list(d);
      next = d['next_before'];
      error = null;
    } on ApiError catch (e) {
      error = e;
    }
    loading = false;
    _n();
  }

  Future<void> more() async {
    if (next == null) return;
    try {
      final d = await _page(next);
      items = [...items, ..._list(d)];
      next = d['next_before'];
      _n();
    } on ApiError {
      // keep what we have
    }
  }

  void _n() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

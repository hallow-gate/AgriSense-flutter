import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Talks to the Android side (secure storage shared with the widget, widget refresh,
/// live-update service). Every call is safe on platforms without the native part.
class Native {
  static const _ch = MethodChannel('com.agrisense.app/native');
  static final Map<String, String> _mem = {};
  static bool get supported {
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  static Future<T?> _call<T>(String m, [Object? args]) async {
    if (!supported) return null;
    try {
      return await _ch.invokeMethod<T>(m, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }

  // ---- secure key/value store (same store the widget reads) ----
  static Future<String?> kvGet(String key) async {
    if (!supported) return _mem[key];
    return _call<String>('kvGet', key);
  }

  static Future<void> kvSet(String key, String value) async {
    if (!supported) {
      _mem[key] = value;
      return;
    }
    await _call<void>('kvSet', {'key': key, 'value': value});
  }

  static Future<void> kvDelete(String key) async {
    if (!supported) {
      _mem.remove(key);
      return;
    }
    await _call<void>('kvDelete', key);
  }

  // ---- widget ----
  static Future<void> setBaseUrl(String url) => _call<void>('setBaseUrl', url);
  static Future<void> pushStatus(String json) => _call<void>('pushStatus', json);
  static Future<void> clearWidgetData() => _call<void>('clearWidgetData');

  static Future<int> widgetCount() async => (await _call<int>('widgetCount')) ?? 0;
  static Future<bool> requestPinWidget() async => (await _call<bool>('requestPinWidget')) ?? false;

  // ---- live updates (foreground service) ----
  static Future<({bool enabled, int intervalSec})> getLive() async {
    final m = await _call<Map<dynamic, dynamic>>('getLive');
    if (m == null) return (enabled: false, intervalSec: 10);
    return (
      enabled: m['enabled'] == true,
      intervalSec: (m['intervalSec'] is num) ? (m['intervalSec'] as num).toInt() : 10,
    );
  }

  static Future<void> setLive(bool enabled, int intervalSec) =>
      _call<void>('setLive', {'enabled': enabled, 'intervalSec': intervalSec});

  static Future<bool> requestNotificationPermission() async =>
      (await _call<bool>('requestNotificationPermission')) ?? true;

  static Future<void> openBatterySettings() => _call<void>('openBatterySettings');
}

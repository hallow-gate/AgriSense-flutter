import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

String fmt(num? v, [String u = '', int d = 0]) => (v == null || (v is double && v.isNaN)) ? '–' : '${v.toStringAsFixed(d)}$u';

DateTime? parseIso(String? s) {
  if (s == null || s.isEmpty) return null;
  return DateTime.tryParse(s)?.toLocal();
}

String ago(String? iso) {
  final d = parseIso(iso);
  if (d == null) return '–';
  final s = max(0, DateTime.now().difference(d).inSeconds);
  if (s < 60) return 'just now';
  if (s < 3600) return '${s ~/ 60} min ago';
  if (s < 86400) return '${s ~/ 3600} h ago';
  return '${s ~/ 86400} d ago';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _wdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

String clockOf(DateTime d, {bool minutes = true}) {
  final h = ((d.hour + 11) % 12) + 1;
  final ap = d.hour < 12 ? 'AM' : 'PM';
  if (!minutes) return '$h $ap';
  return '$h:${d.minute.toString().padLeft(2, '0')} $ap';
}

String dayLabelOf(DateTime d) => '${_months[d.month - 1]} ${d.day}';
String stampOf(DateTime d) => '${dayLabelOf(d)}, ${clockOf(d)}';
String stamp(String? iso) {
  final d = parseIso(iso);
  return d == null ? '' : stampOf(d);
}

String weekdayShort(DateTime d) => _wdays[d.weekday - 1];
String hourLabel(num h) {
  final x = h.toInt();
  return '${((x + 11) % 12) + 1}:00 ${x < 12 ? 'AM' : 'PM'}';
}

String uptime(num? s) {
  if (s == null) return '–';
  final d = s ~/ 86400, h = (s % 86400) ~/ 3600, m = (s % 3600) ~/ 60;
  return d > 0 ? '${d}d ${h}h' : h > 0 ? '${h}h ${m}m' : '${m}m';
}

String uuid() {
  final r = Random.secure();
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final tail = List.generate(10, (_) => chars[r.nextInt(chars.length)]).join();
  return 'k${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}$tail';
}

void tick() {
  try {
    HapticFeedback.selectionClick();
  } catch (_) {}
}

num? numOf(dynamic v) => v is num ? v : (v is String ? num.tryParse(v) : null);

// ---------- readable labels for log rows ----------
class Meta {
  final String icon, tone, title;
  final String? sub;
  const Meta(this.icon, this.tone, this.title, [this.sub]);
}

const _src = {'schedule': 'Scheduled', 'manual': 'Manual', 'auto_heat': 'Auto, heat'};
const _why = {'wet': 'Soil was moist enough', 'sensor_fault': 'Soil sensor fault', 'busy': 'Pump was busy', 'cooldown': 'Cooling down'};

String? _join(List<String?> a) {
  final l = a.where((e) => e != null && e.isNotEmpty).cast<String>().toList();
  return l.isEmpty ? null : l.join(' · ');
}

Meta eventMeta(Map<String, dynamic> e) {
  final d = (e['detail'] is Map) ? Map<String, dynamic>.from(e['detail'] as Map) : <String, dynamic>{};
  final result = d['result'];
  final bad = result != null && result != 'ok';
  final srcRaw = e['source']?.toString();
  final src = _src[srcRaw] ?? srcRaw;
  final sp = numOf(d['soil_pct']);
  final soil = (sp != null && sp >= 0) ? 'soil $sp%' : null;
  final type = e['type']?.toString() ?? '';
  switch (type) {
    case 'water_auto':
    case 'water_manual':
      if (bad) return Meta('drop', 'bad', 'Watering refused', _join([src, _why[result] ?? result.toString()]));
      final secs = numOf(d['seconds']);
      return Meta('drop', 'ok', 'Watered', _join([src, (secs != null && secs != 0) ? '$secs s' : null, soil]));
    case 'water_skipped':
      final r = d['reason']?.toString();
      return Meta('pause', 'mute', 'Watering skipped', _join([_why[r] ?? r, soil]));
    case 'shade_close':
    case 'shade_open':
      final closing = type == 'shade_close';
      if (bad) return Meta('shade', 'bad', 'Cover move refused', _join([src, _why[result] ?? result.toString()]));
      final tc = numOf(d['temp_c']);
      return Meta('shade', 'ok', closing ? 'Cover closed' : 'Cover opened',
          _join([src, (tc != null && tc != 0) ? '$tc°C' : null, d['noop'] == true ? 'already there' : null]));
    default:
      return Meta('list', 'mute', type, src);
  }
}

const _act = {
  'login_ok': ['shield', 'ok', 'Signed in'],
  'login_failed': ['lock', 'bad', 'Failed sign-in'],
  'login_locked': ['lock', 'bad', 'Locked out'],
  'captcha_failed': ['shield', 'bad', 'Security check failed'],
  'logout': ['logout', 'mute', 'Signed out'],
  'device_auth_failed': ['chip', 'bad', 'Device request rejected'],
};

Meta auditMeta(Map<String, dynamic> l) {
  final action = l['action']?.toString() ?? '';
  final meta = (l['meta'] is Map) ? Map<String, dynamic>.from(l['meta'] as Map) : <String, dynamic>{};
  if (action == 'command_created') {
    final a = meta['action']?.toString();
    return Meta(a == 'water' ? 'drop' : 'shade', 'ok', 'Sent: ${a == 'water' ? 'water now' : a}');
  }
  if (action == 'settings_changed') {
    final keys = meta.keys.toList();
    return Meta('sliders', 'info', 'Changed ${keys.length} setting${keys.length == 1 ? '' : 's'}', keys.map((k) => k.replaceAll('_', ' ')).join(', '));
  }
  final m = _act[action];
  return m != null ? Meta(m[0], m[1], m[2]) : Meta('list', 'mute', action);
}

String deviceName(String? ua) {
  final u = ua ?? '';
  if (RegExp(r'okhttp|Expo|AgriSense', caseSensitive: false).hasMatch(u)) return 'Phone app';
  if (RegExp(r'CFNetwork|Darwin', caseSensitive: false).hasMatch(u)) return 'iPhone app';
  return u.length > 28 ? u.substring(0, 28) : u;
}

Color toneColor(String tone) {
  switch (tone) {
    case 'ok':
      return C.matchaFlat;
    case 'bad':
      return C.bad;
    case 'info':
      return C.info;
    case 'warn':
      return C.warn;
    default:
      return C.faint;
  }
}

/// Simple confirm dialog.
Future<void> confirmAsk(BuildContext context, String title, String msg, String okLabel, VoidCallback onOk) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: C.card[0],
      title: Text(title, style: ts(18, C.matchaInk, 'black')),
      content: Text(msg, style: ts(14.5, C.ink, 'reg')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: ts(14.5, C.mute, 'bold'))),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(okLabel, style: ts(14.5, C.matchaDeep, 'bold'))),
      ],
    ),
  );
  if (ok == true) onOk();
}

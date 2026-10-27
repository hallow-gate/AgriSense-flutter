import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/query.dart';
import '../core/theme.dart';
import '../core/util.dart';
import '../widgets/clay.dart';
import '../widgets/icons.dart';

const _keys = ['auto_water', 'auto_shade', 'soil_dry_pct', 'hot_c', 'cool_c', 'pump_seconds', 'shade_close_seconds', 'shade_open_seconds', 'water_hour_1', 'water_hour_2', 'pump_ml_per_s', 'sms_enabled', 'sms_recipients'];

String _dur(num v) => v < 60 ? '${v.toInt()} s' : '${v ~/ 60}m ${(v % 60).toInt().toString().padLeft(2, '0')}s';
List<String> _nums(dynamic a) => ((a as List?) ?? const []).map((x) => '$x'.trim()).where((x) => x.isNotEmpty).toList();
bool _same(List a, List b) => a.length == b.length && List.generate(a.length, (i) => a[i] == b[i]).every((x) => x);

// stepping onto the other slot's hour jumps one further so the two times never match
num _skip(num v, num cur, num other) => v == other ? (v + (v > cur ? 1 : -1)).clamp(0, 23) : v;

class ControlScreen extends StatefulWidget {
  final bool active;
  final Map<String, dynamic>? user;
  const ControlScreen({super.key, required this.active, required this.user});
  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  final st = StatusStore.i;
  Map<String, dynamic>? draft;
  String msg = '', err = '';
  String? busy;
  final List<TextEditingController> _phones = [];

  bool get admin => widget.user?['role'] == 'admin';

  @override
  void initState() {
    super.initState();
    st.addListener(_seed);
    _seed();
  }

  @override
  void dispose() {
    st.removeListener(_seed);
    for (final c in _phones) {
      c.dispose();
    }
    super.dispose();
  }

  void _seed() {
    final s = st.data?['settings'];
    if (draft == null && s is Map) {
      setState(() => _setDraft(Map<String, dynamic>.from(s)));
    }
  }

  void _setDraft(Map<String, dynamic> d) {
    draft = d;
    final list = _nums(d['sms_recipients']);
    for (final c in _phones) {
      c.dispose();
    }
    _phones.clear();
    for (final n in (list.isEmpty ? [''] : list)) {
      _phones.add(TextEditingController(text: n));
    }
  }

  List<String> get _draftNums => _phones.map((c) => c.text.trim()).where((x) => x.isNotEmpty).toList();

  bool get dirty {
    final s = st.data?['settings'];
    if (draft == null || s is! Map) return false;
    for (final k in _keys) {
      if (k == 'sms_recipients') {
        if (!_same(_draftNums, _nums(s[k]))) return true;
      } else if (draft![k] != s[k]) {
        return true;
      }
    }
    return false;
  }

  void up(String k, dynamic v) => setState(() {
        draft = {...draft!, k: v};
        if (k == 'hot_c' && (numOf(draft!['cool_c']) ?? 0) > v - 1) draft!['cool_c'] = v - 1;
      });

  Future<void> _send(String action) async {
    setState(() {
      busy = action;
      msg = '';
    });
    try {
      final r = await Api.i.call('/api/commands', method: 'POST', body: {'action': action, 'idem_key': uuid()});
      msg = r['duplicate'] == true
          ? 'That is already queued.'
          : r['device_online'] == false
              ? 'Queued, but the device looks offline. It will run if it reconnects within 10 minutes.'
              : 'Sent. The device picks it up within about 30 seconds.';
      st.reload();
    } on ApiError catch (e) {
      msg = e.status == 403 ? 'This account is view-only.' : e.message;
    }
    if (mounted) setState(() => busy = null);
  }

  Future<void> _save() async {
    setState(() => err = '');
    final list = _draftNums;
    if (draft!['sms_enabled'] == true && list.isEmpty) return setState(() => err = 'Add at least 1 phone number to turn SMS on.');
    setState(() => busy = 'save');
    try {
      final body = {for (final k in _keys) k: draft![k], 'sms_recipients': list};
      final r = await Api.i.call('/api/settings', method: 'PUT', body: body);
      _setDraft(Map<String, dynamic>.from(r));
      st.reload();
      msg = 'Saved. The device applies it on its next check-in.';
    } on ApiError catch (e) {
      err = e.message;
    }
    if (mounted) setState(() => busy = null);
  }

  Widget _toggleRow(String title, String sub, String key) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [T(title, s: 15, f: 'bold'), T(sub, s: 12.5, c: C.mute, f: 'reg')]),
            ),
          ),
          ClayToggle(value: draft![key] == true, onChanged: (v) => up(key, v), disabled: !admin),
        ]),
      );

  Widget _step(String label, String key, num min, num max, {num step = 1, String unit = '', String? hint, String Function(num)? format, num? maxOverride}) => NumStepper(
        label: label,
        hint: hint,
        value: numOf(draft![key]) ?? min,
        unit: unit,
        min: min,
        max: maxOverride ?? max,
        step: step,
        format: format,
        disabled: !admin,
        onChanged: (v) => up(key, v),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: st,
      builder: (context, _) {
        final s = st.data;
        final open = ((s?['open'] as List?) ?? const []).map((c) => '${(c as Map)['action']}').toList();
        final tel = st.telemetry;
        final closed = tel['shade'] == 'closed';
        final online = s?['online'] == true;
        final D = draft;
        final pumpSecs = numOf((s?['settings'] as Map?)?['pump_seconds']) ?? 30;

        return PageScroll(
          onRefresh: st.reload,
          children: [
            Header(title: 'Control', sub: admin ? 'Run things now, or let it run itself' : 'View-only account'),
            const Label('Right now'),
            Clay(
              radius: 28,
              child: Column(children: [
                ClayButton(
                  label: open.contains('water') ? 'Waiting for device…' : 'Water now',
                  icon: 'drop',
                  loading: busy == 'water',
                  disabled: !admin || open.contains('water'),
                  onPressed: () => confirmAsk(context, 'Water now?', 'The pump will run for ${pumpSecs.toInt()} seconds.', 'Water', () => _send('water')),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: ClayButton(kind: BtnKind.soft, icon: 'shade', label: open.contains('cover') ? 'Closing…' : 'Cover', loading: busy == 'cover', disabled: !admin || open.contains('cover') || closed, onPressed: () => _send('cover'))),
                  const SizedBox(width: 12),
                  Expanded(child: ClayButton(kind: BtnKind.soft, icon: 'sun', label: open.contains('uncover') ? 'Opening…' : 'Uncover', loading: busy == 'uncover', disabled: !admin || open.contains('uncover') || tel['shade'] == 'open', onPressed: () => _send('uncover'))),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: T(msg.isEmpty ? 'Manual cover moves pause automatic shading for an hour.' : msg, s: 13, c: C.mute, f: 'reg')),
                  if (s != null) Pill(online ? 'Device online' : 'Device offline', tone: online ? 'ok' : 'bad'),
                ]),
              ]),
            ),
            const Gap(22),
            const Label('Automation'),
            if (D == null)
              T(st.error != null ? st.error!.message : 'Loading…', c: C.mute)
            else
              Clay(
                radius: 28,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _toggleRow('Scheduled watering', 'Checks the soil at the two times below and only waters if dry.', 'auto_water'),
                  _toggleRow('Automatic shade', 'Closes the cover when it stays hot, reopens when it cools.', 'auto_shade'),
                  const Div(),
                  NumStepper(label: 'Water first at', value: numOf(D['water_hour_1']) ?? 6, min: 0, max: 23, format: hourLabel, disabled: !admin, onChanged: (v) => up('water_hour_1', _skip(v, numOf(D['water_hour_1']) ?? 6, numOf(D['water_hour_2']) ?? 18).toInt())),
                  NumStepper(label: 'Water again at', value: numOf(D['water_hour_2']) ?? 18, min: 0, max: 23, format: hourLabel, disabled: !admin, onChanged: (v) => up('water_hour_2', _skip(v, numOf(D['water_hour_2']) ?? 18, numOf(D['water_hour_1']) ?? 6).toInt())),
                  _step('Soil counts as dry below', 'soil_dry_pct', 10, 80, step: 5, unit: '%'),
                  _step('Pump runs for', 'pump_seconds', 5, 180, step: 5, format: _dur, hint: 'Calibrate how long each watering lasts. Max 3 min'),
                  _step('Cover (close) time', 'shade_close_seconds', 10, 600, step: 5, format: _dur, hint: 'Seconds to fully close the shade. Max 10 min'),
                  _step('Uncover (open) time', 'shade_open_seconds', 10, 600, step: 5, format: _dur, hint: 'Seconds to fully open the shade. Max 10 min'),
                  const Div(),
                  _step('Close cover at', 'hot_c', 30, 45, unit: '°C'),
                  NumStepper(label: 'Reopen at', value: numOf(D['cool_c']) ?? 25, unit: '°C', min: 25, max: (numOf(D['hot_c']) ?? 35) - 1, disabled: !admin, onChanged: (v) => up('cool_c', v)),
                  const Div(),
                  _step('Pump flow', 'pump_ml_per_s', 1, 200, step: 5, unit: ' ml/s', hint: 'Only used for the litres estimate'),
                  const Div(),
                  _toggleRow('SMS notifications', 'Text the numbers below when watering or the cover moves. Only events from the last 5 minutes are sent, once each.', 'sms_enabled'),
                  if (D['sms_enabled'] == true) _smsBlock(),
                  if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: T(err, s: 13, c: C.bad)),
                  if (admin && dirty)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Row(children: [
                        Expanded(child: ClayButton(kind: BtnKind.soft, label: 'Undo', onPressed: () => setState(() => _setDraft(Map<String, dynamic>.from(s!['settings'] as Map))))),
                        const SizedBox(width: 12),
                        Expanded(flex: 2, child: ClayButton(label: 'Save changes', icon: 'check', loading: busy == 'save', onPressed: _save)),
                      ]),
                    ),
                ]),
              ),
          ],
        );
      },
    );
  }

  Widget _smsBlock() {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < _phones.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _phones[i],
                  enabled: admin,
                  keyboardType: TextInputType.phone,
                  maxLength: 20,
                  onChanged: (_) => setState(() {}),
                  style: ts(16, C.ink),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '+639171234567',
                    hintStyle: ts(16, C.faint),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: a(C.shadow, 0.22), width: 1.5)),
                    disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: a(C.shadow, 0.12), width: 1.5)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.matchaFlat, width: 1.5)),
                  ),
                ),
              ),
              if (admin && _phones.length > 1) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 68,
                  child: ClayButton(
                    kind: BtnKind.soft,
                    icon: 'minus',
                    label: '',
                    onPressed: () => setState(() {
                      _phones.removeAt(i).dispose();
                    }),
                  ),
                ),
              ],
            ]),
          ),
        if (admin && _phones.length < 3) ClayButton(kind: BtnKind.soft, icon: 'plus', label: 'Add number', onPressed: () => setState(() => _phones.add(TextEditingController()))),
        const Padding(padding: EdgeInsets.only(top: 8), child: T('1 to 3 numbers, e.g. 09171234567 or +639171234567. Tap Save changes to apply.', s: 12, c: C.faint, f: 'reg')),
      ]),
    );
  }
}

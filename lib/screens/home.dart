import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/query.dart';
import '../core/theme.dart';
import '../core/util.dart';
import '../widgets/charts.dart';
import '../widgets/clay.dart';
import '../widgets/icons.dart';

const _tone = {'critical': C.bad, 'warning': C.warn, 'info': C.info};

String _greet() {
  final h = DateTime.now().hour;
  return h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening';
}

class HomeScreen extends StatefulWidget {
  final bool active;
  final void Function(String tab) go;
  const HomeScreen({super.key, required this.active, required this.go});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final st = StatusStore.i;
  final hist = ApiQuery('/api/history?range=6h', interval: const Duration(seconds: 60));

  @override
  void initState() {
    super.initState();
    hist.setActive(widget.active);
  }

  @override
  void didUpdateWidget(HomeScreen o) {
    super.didUpdateWidget(o);
    hist.setActive(widget.active);
  }

  @override
  void dispose() {
    hist.dispose();
    super.dispose();
  }

  List<double?> _series(String k) => ((hist.data?['points'] as List?) ?? const []).map((p) => numOf((p as Map)[k])?.toDouble()).toList();

  Widget _tile(String icon, Color color, String label, String value, [Widget? extra]) => Expanded(
        child: Clay(
          radius: 24,
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [AIcon(icon, size: 17, color: color), const SizedBox(width: 6), T(label, s: 12.5, f: 'bold', c: C.mute)]),
            const SizedBox(height: 4),
            T(value, s: 26, f: 'black', c: C.ink, ls: -0.5),
            if (extra != null) ...[const SizedBox(height: 4), extra],
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([st, hist]),
      builder: (context, _) {
        final s = st.data;
        final t = st.telemetry;
        final set = s?['settings'] as Map?;
        final soilPct = numOf(t['soil_pct']);
        final dry = numOf(set?['soil_dry_pct']) ?? 40;
        final soilState = t['soil_fault'] == true
            ? 'Sensor fault'
            : soilPct == null
                ? 'No reading'
                : soilPct < dry
                    ? 'Dry'
                    : soilPct > 75
                        ? 'Wet'
                        : 'Comfortable';
        final nw = s?['next_watering'] as Map?;
        final online = s?['online'] == true;
        final vpd = s?['vpd'] as Map?;
        final events = ((s?['events'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        final alerts = ((s?['alerts'] as List?) ?? const []).whereType<Map>().toList();

        return PageScroll(
          onRefresh: () async {
            await Future.wait([st.reload(), hist.reload()]);
          },
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                const Sprout(size: 28),
                const SizedBox(width: 8),
                T('AgriSense', s: 20, f: 'black', c: C.matchaInk, ls: -0.4),
              ]),
              if (s != null) Pill(online ? 'Online' : 'Offline', tone: online ? 'ok' : 'bad'),
            ]),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: T('${_greet()}. ${online ? 'Everything is reporting in.' : s != null ? 'The device has gone quiet.' : ' '}', s: 14, c: C.mute, f: 'reg'),
            ),
            if (st.error != null && s == null) Clay(child: T(st.error!.message, c: C.bad)),
            for (final al in alerts)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Clay(
                  radius: 20,
                  padding: const EdgeInsets.all(12),
                  child: IntrinsicHeight(
                    child: Row(children: [
                      Container(width: 8, decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: _tone[al['level']] ?? C.info)),
                      const SizedBox(width: 10),
                      Expanded(child: T('${al['text']}', s: 14, f: 'semi')),
                    ]),
                  ),
                ),
              ),
            Clay(
              radius: 30,
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                Ring(
                  size: 132,
                  stroke: 15,
                  value: soilPct?.toDouble() ?? 0,
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: soilPct == null ? '–' : '$soilPct', style: ts(30, C.matchaInk, 'black', -1)),
                    TextSpan(text: '%', style: ts(15, C.mute)),
                  ])),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    T('Soil moisture', s: 13, f: 'bold', c: C.mute),
                    const SizedBox(height: 6),
                    T(soilState, s: 21, f: 'black', c: C.matchaInk),
                    if (nw != null) ...[
                      const SizedBox(height: 10),
                      Row(children: [
                        const AIcon('clock', size: 15, color: C.mute),
                        const SizedBox(width: 6),
                        Expanded(child: T('Next water ${nw['day']}, ${hourLabel(numOf(nw['hour']) ?? 0)}', s: 13, c: C.mute)),
                      ]),
                    ],
                    const SizedBox(height: 6),
                    T(t['updated_at'] != null ? 'Updated ${ago(t['updated_at'] as String?)}' : '', s: 12, c: C.faint, f: 'reg'),
                  ]),
                ),
              ]),
            ),
            const Gap(),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _tile('thermo', C.temp, 'Temperature', fmt(numOf(t['temp_c']), '°', 1), Spark(values: _series('temp'), color: C.temp)),
              const SizedBox(width: 14),
              _tile('drop', C.hum, 'Humidity', fmt(numOf(t['humidity']), '%'), Spark(values: _series('hum'), color: C.hum)),
            ]),
            const Gap(),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _tile('shade', C.matchaFlat, 'Cover', t['shade'] != null ? (t['shade'] == 'closed' ? 'Closed' : 'Open') : '–'),
              const SizedBox(width: 14),
              _tile('drop', C.matchaFlat, 'Pump', t['pump'] == true || (t['pump'] is num && t['pump'] != 0) ? 'Running' : 'Idle'),
            ]),
            if (vpd != null) ...[
              const Gap(),
              _vpdCard(vpd),
            ],
            const Gap(22),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Label('Recent', padding: EdgeInsets.only(bottom: 6)),
              Press(onTap: () => widget.go('logs'), child: T('See all', s: 13, f: 'bold', c: C.matchaFlat)),
            ]),
            Clay(
              radius: 26,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: events.isEmpty
                  ? const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: T('Nothing has happened yet.', s: 14, c: C.mute))
                  : Column(children: [
                      for (var i = 0; i < events.length; i++) ...[
                        if (i > 0) const Div(),
                        _eventRow(events[i]),
                      ],
                    ]),
            ),
          ],
        );
      },
    );
  }

  Widget _eventRow(Map<String, dynamic> e) {
    final m = eventMeta(e);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        AIcon(m.icon, size: 19, color: m.tone == 'bad' ? C.bad : C.matchaFlat),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            T(m.title, s: 14.5, f: 'bold'),
            if (m.sub != null) T(m.sub!, s: 12.5, c: C.mute, f: 'reg'),
          ]),
        ),
        T(ago(e['occurred_at'] as String?), s: 12, c: C.faint),
      ]),
    );
  }

  Widget _vpdCard(Map vpd) {
    final kpa = numOf(vpd['kpa'])?.toDouble() ?? 0;
    final zone = '${vpd['zone']}';
    const segs = [C.info, Color(0xFFB7CC95), C.ok, C.warn, C.bad];
    return Clay(
      radius: 26,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            T('Air dryness (VPD)', s: 13, f: 'bold', c: C.mute),
            Text.rich(TextSpan(children: [
              TextSpan(text: '${kpa.toStringAsFixed(2)} ', style: ts(24, C.ink, 'black')),
              TextSpan(text: 'kPa', style: ts(14, C.mute)),
            ])),
          ]),
          Pill(zone, tone: zone == 'ideal' ? 'ok' : (zone == 'low' || zone == 'high') ? 'warn' : 'bad'),
        ]),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, cons) {
          final x = (kpa / 2).clamp(0.0, 1.0) * cons.maxWidth;
          return SizedBox(
            height: 26,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(
                left: 0,
                right: 0,
                top: 6,
                height: 14,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Row(children: [for (final c in segs) Expanded(child: Container(color: a(c, 0.85)))]),
                ),
              ),
              Positioned(
                left: x - 9,
                top: 0,
                child: Container(
                  width: 18,
                  height: 26,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9), border: Border.all(color: C.matchaInk, width: 3)),
                ),
              ),
            ]),
          );
        }),
        const SizedBox(height: 10),
        T('Around 0.8 to 1.2 kPa most plants drink comfortably.', s: 12, c: C.faint, f: 'reg'),
      ]),
    );
  }
}

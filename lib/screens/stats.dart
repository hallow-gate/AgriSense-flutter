import 'dart:async';

import 'package:flutter/material.dart';

import '../core/query.dart';
import '../core/theme.dart';
import '../core/util.dart';
import '../widgets/charts.dart';
import '../widgets/clay.dart';
import '../widgets/icons.dart';

const _ranges = [('6h', '6 h'), ('24h', '24 h'), ('7d', '7 days'), ('30d', '30 days')];
const _span = {'6h': 6 * 3600000, '24h': 24 * 3600000, '7d': 7 * 86400000, '30d': 30 * 86400000};
bool _short(String r) => r == '6h' || r == '24h';

String Function(int) _fmtTick(String r) => (ms) {
      final d = DateTime.fromMillisecondsSinceEpoch(ms);
      if (!_short(r)) return dayLabelOf(d);
      return clockOf(d, minutes: d.minute != 0);
    };

class StatsScreen extends StatefulWidget {
  final bool active;
  const StatsScreen({super.key, required this.active});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  String range = '24h';
  int now = DateTime.now().millisecondsSinceEpoch;
  Timer? _clock;
  final st = StatusStore.i;
  late final ApiQuery hist = ApiQuery('/api/history?range=$range', interval: const Duration(seconds: 30));
  late final ApiQuery stats = ApiQuery('/api/stats?days=7', interval: const Duration(seconds: 120));
  // the status poll adds a fresh point every few seconds so the chart moves in real time
  final Map<int, Map<String, double?>> buf = {};
  String? _lastStamp;

  int get days => range == '30d' ? 30 : 7;

  @override
  void initState() {
    super.initState();
    hist.setActive(widget.active);
    stats.setActive(widget.active);
    st.addListener(_onStatus);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.active) setState(() => now = DateTime.now().millisecondsSinceEpoch);
    });
  }

  @override
  void didUpdateWidget(StatsScreen o) {
    super.didUpdateWidget(o);
    hist.setActive(widget.active);
    stats.setActive(widget.active);
  }

  @override
  void dispose() {
    st.removeListener(_onStatus);
    _clock?.cancel();
    hist.dispose();
    stats.dispose();
    super.dispose();
  }

  void _onStatus() {
    final t = st.telemetry;
    final iso = t['updated_at'] as String?;
    if (iso == null || iso == _lastStamp) return;
    _lastStamp = iso;
    final ms = parseIso(iso)?.millisecondsSinceEpoch;
    if (ms == null || buf.containsKey(ms)) return;
    buf[ms] = {
      'temp': numOf(t['temp_c'])?.toDouble(),
      'hum': numOf(t['humidity'])?.toDouble(),
      'soil': t['soil_fault'] == true ? null : numOf(t['soil_pct'])?.toDouble(),
    };
    if (buf.length > 600) buf.remove(buf.keys.first);
  }

  void _setRange(String r) {
    setState(() => range = r);
    hist.setPath('/api/history?range=$r');
    stats.setPath('/api/stats?days=${r == '30d' ? 30 : 7}');
  }

  List<ChartPoint> _series(String k, int t0) {
    final pts = ((hist.data?['points'] as List?) ?? const []).whereType<Map>().toList();
    final base = <ChartPoint>[
      for (final p in pts)
        if (parseIso(p['t'] as String?) != null) ChartPoint(parseIso(p['t'] as String?)!.millisecondsSinceEpoch, numOf(p[k])?.toDouble()),
    ];
    if (!_short(range)) return base;
    final lastT = base.isEmpty ? 0 : base.last.t;
    final extra = buf.entries.where((e) => e.key > lastT && e.key >= t0).map((e) => ChartPoint(e.key, e.value[k]));
    return [...base, ...extra];
  }

  Widget _live(bool online, String? at) {
    final ms = parseIso(at)?.millisecondsSinceEpoch;
    final sec = ms == null ? null : ((now - ms) / 1000).round().clamp(0, 1 << 30);
    final label = ms == null
        ? 'Waiting for device'
        : !online
            ? 'Device offline'
            : sec! < 5
                ? 'Live · just now'
                : sec < 90
                    ? 'Live · ${sec}s ago'
                    : 'Live · ${(sec / 60).round()} min ago';
    final col = online ? C.ok : C.faint;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: a(col, 0.12), borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          T(label, s: 12.5, f: 'bold', c: online ? C.matchaDeep : C.mute),
        ]),
      ),
    );
  }

  Widget _series2(String title, String icon, Color color, String unit, int dec, List<ChartPoint> pts, int t0, int t1, double? liveValue, bool live, double h, int gapMs, {RefLine? ref}) {
    return _SeriesCard(
      title: title,
      icon: icon,
      color: color,
      unit: unit,
      dec: dec,
      points: pts,
      t0: t0,
      t1: t1,
      liveValue: liveValue,
      live: live,
      height: h,
      gapMs: gapMs,
      range: range,
      refLine: ref,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([hist, stats, st]),
      builder: (context, _) {
        final width = MediaQuery.of(context).size.width;
        final tel = st.telemetry;
        final online = st.online == true;
        final t1 = now, t0 = now - _span[range]!;
        final bucketMs = ((numOf(hist.data?['bucket_seconds']) ?? 300) * 1000).toInt();
        final gapMs = (bucketMs * 2.5).round() > 15 * 60000 ? (bucketMs * 2.5).round() : 15 * 60000;
        final cols = width >= 1180 ? 2 : 1;
        final chartH = width >= 768 ? 210.0 : width < 360 ? 160.0 : 185.0;
        final live = _short(range) && online;
        double? liveOf(num? v) => (tel['updated_at'] != null && v != null && online) ? v.toDouble() : null;
        final dry = numOf(st.data?['settings']?['soil_dry_pct']);

        final A = _series2('Temperature', 'thermo', C.temp, '°', 1, _series('temp', t0), t0, t1, liveOf(numOf(tel['temp_c'])), live, chartH, gapMs);
        final B = _series2('Humidity', 'drop', C.hum, '%', 0, _series('hum', t0), t0, t1, liveOf(numOf(tel['humidity'])), live, chartH, gapMs);
        final S = _series2('Soil moisture', 'leaf', C.soil, '%', 0, _series('soil', t0), t0, t1, liveOf(tel['soil_fault'] == true ? null : numOf(tel['soil_pct'])), live, chartH, gapMs,
            ref: dry != null ? RefLine(dry.toDouble(), 'Dry below $dry%') : null);

        final tot = stats.data?['totals'] as Map?;
        final d = ((stats.data?['days'] as List?) ?? const []).whereType<Map>().toList();
        final tileCols = width >= 700 ? 4 : 2;
        final tiles = <Widget>[
          _stat('drop', 'Waterings', tot != null ? '${tot['waterings']}' : '–', (numOf(tot?['skipped']) ?? 0) > 0 ? '${tot!['skipped']} skipped' : null),
          _stat('gauge', 'Water used', tot != null ? '${tot['liters']} L' : '–', 'estimated'),
          _stat('thermo', 'Avg temperature', tot != null ? fmt(numOf(tot['avg_temp']), '°', 1) : '–', tot?['max_temp'] != null ? 'peak ${tot!['max_temp']}°' : null),
          _stat('shade', 'Cover moves', tot != null ? '${tot['shade_moves']}' : '–', null),
        ];
        final rows = <Widget>[];
        for (var i = 0; i < tiles.length; i += tileCols) {
          final slice = tiles.sublist(i, i + tileCols > tiles.length ? tiles.length : i + tileCols);
          rows.add(Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var j = 0; j < slice.length; j++) ...[if (j > 0) const SizedBox(width: 14), slice[j]],
            ]),
          ));
        }

        final waterCard = Clay(
          radius: 26,
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const T('Water per day (litres)', s: 14, f: 'bold', c: C.mute),
            const SizedBox(height: 8),
            BarChart(data: [for (final x in d) BarDatum('${x['date']}'.substring(8), numOf(x['liters'])?.toDouble() ?? 0)]),
          ]),
        );
        final rangeCard = Clay(
          radius: 26,
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const T('Daily temperature range', s: 14, f: 'bold', c: C.mute),
            const T('Low to high, dot is the average', s: 12, c: C.faint, f: 'reg'),
            const SizedBox(height: 8),
            RangeChart(data: [for (final x in d) RangeDatum('${x['date']}'.substring(8), numOf(x['min_temp'])?.toDouble(), numOf(x['max_temp'])?.toDouble(), numOf(x['avg_temp'])?.toDouble())]),
          ]),
        );

        return PageScroll(
          maxWidth: cols == 2 ? 1100 : 760,
          onRefresh: () async {
            await Future.wait([hist.reload(), stats.reload(), st.reload()]);
          },
          children: [
            const Header(title: 'Statistics', sub: 'Drag across a chart to read exact values'),
            Padding(padding: const EdgeInsets.only(bottom: 14), child: _live(online, tel['updated_at'] as String?)),
            Segmented(options: _ranges, value: range, onChanged: _setRange),
            const Gap(18),
            if (cols == 2) ...[
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: A), const SizedBox(width: 16), Expanded(child: B)]),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: S), const SizedBox(width: 16), const Expanded(child: SizedBox())]),
            ] else ...[A, B, S],
            Label('Last $days days', padding: const EdgeInsets.only(top: 6, bottom: 8)),
            ...rows,
            if (cols == 2)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: waterCard), const SizedBox(width: 16), Expanded(child: rangeCard)])
            else ...[waterCard, const Gap(16), rangeCard],
          ],
        );
      },
    );
  }

  Widget _stat(String icon, String label, String value, String? sub) => Expanded(
        child: Clay(
          radius: 22,
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AIcon(icon, size: 18, color: C.matchaFlat),
            const SizedBox(height: 6),
            T(value, s: 24, f: 'black', c: C.ink, ls: -0.5),
            T(label, s: 12.5, f: 'bold', c: C.mute),
            if (sub != null) T(sub, s: 11.5, c: C.faint, f: 'reg'),
          ]),
        ),
      );
}

class _SeriesCard extends StatefulWidget {
  final String title, icon, unit, range;
  final Color color;
  final int dec, t0, t1, gapMs;
  final List<ChartPoint> points;
  final double? liveValue;
  final bool live;
  final double height;
  final RefLine? refLine;
  const _SeriesCard({required this.title, required this.icon, required this.color, required this.unit, required this.dec, required this.points, required this.t0, required this.t1, required this.liveValue, required this.live, required this.height, required this.gapMs, required this.range, this.refLine});

  @override
  State<_SeriesCard> createState() => _SeriesCardState();
}

class _SeriesCardState extends State<_SeriesCard> {
  ChartPoint? sel;

  @override
  Widget build(BuildContext context) {
    final vals = widget.points.where((p) => p.v != null).map((p) => p.v!).toList();
    final lastV = widget.liveValue ?? (vals.isEmpty ? null : vals.last);
    final shown = sel?.v ?? lastV;
    final avg = vals.isEmpty ? null : vals.reduce((a, b) => a + b) / vals.length;
    final lo = vals.isEmpty ? null : vals.reduce((a, b) => a < b ? a : b);
    final hi = vals.isEmpty ? null : vals.reduce((a, b) => a > b ? a : b);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Clay(
        radius: 26,
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(children: [
                Container(width: 30, height: 30, decoration: BoxDecoration(color: a(widget.color, 0.13), borderRadius: BorderRadius.circular(10)), child: Center(child: AIcon(widget.icon, size: 17, color: widget.color))),
                const SizedBox(width: 8),
                T(widget.title, s: 14.5, f: 'bold', c: C.mute),
              ]),
            ),
            const Spacer(),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              T(shown == null ? '–' : '${shown.toStringAsFixed(widget.dec)}${widget.unit}', s: 26, f: 'black', c: C.ink, ls: -0.6),
              T(shown == null ? '' : (sel != null ? stampOf(DateTime.fromMillisecondsSinceEpoch(sel!.t)) : 'Now'), s: 11.5, c: C.faint),
            ]),
          ]),
          const SizedBox(height: 8),
          LineChart(
            points: widget.points,
            t0: widget.t0,
            t1: widget.t1,
            color: widget.color,
            dec: widget.dec,
            unit: widget.unit,
            height: widget.height,
            gapMs: widget.gapMs,
            live: widget.live,
            refLine: widget.refLine,
            fmtX: _fmtTick(widget.range),
            onSelect: (p) => setState(() => sel = p),
          ),
          const SizedBox(height: 10),
          Row(children: [
            for (final e in [('Low', lo), ('Average', avg), ('High', hi)]) ...[
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  margin: EdgeInsets.only(right: e.$1 == 'High' ? 0 : 8),
                  decoration: BoxDecoration(color: C.well, borderRadius: BorderRadius.circular(14)),
                  child: Column(children: [
                    T(e.$1, s: 11, f: 'bold', c: C.mute),
                    T(fmt(e.$2, widget.unit, widget.dec), s: 15, f: 'black', c: C.matchaInk),
                  ]),
                ),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}

import 'dart:math';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'clay.dart';

// ---------- helpers ----------

/// Monotone cubic (Fritsch-Carlson): smooth like a spline but never overshoots the data.
Path curvePath(List<Offset> p, {Path? into}) {
  final path = into ?? Path();
  final n = p.length;
  if (n == 0) return path;
  path.moveTo(p[0].dx, p[0].dy);
  if (n == 1) return path;
  if (n == 2) {
    path.lineTo(p[1].dx, p[1].dy);
    return path;
  }
  final dx = List<double>.filled(n - 1, 0), m = List<double>.filled(n - 1, 0), t = List<double>.filled(n, 0);
  for (var i = 0; i < n - 1; i++) {
    dx[i] = (p[i + 1].dx - p[i].dx) == 0 ? 1e-6 : p[i + 1].dx - p[i].dx;
    m[i] = (p[i + 1].dy - p[i].dy) / dx[i];
  }
  t[0] = m[0];
  t[n - 1] = m[n - 2];
  for (var i = 1; i < n - 1; i++) {
    t[i] = m[i - 1] * m[i] <= 0
        ? 0
        : (3 * (dx[i - 1] + dx[i])) / ((2 * dx[i] + dx[i - 1]) / m[i - 1] + (dx[i] + 2 * dx[i - 1]) / m[i]);
  }
  for (var i = 0; i < n - 1; i++) {
    final h = dx[i] / 3;
    path.cubicTo(p[i].dx + h, p[i].dy + t[i] * h, p[i + 1].dx - h, p[i + 1].dy - t[i + 1] * h, p[i + 1].dx, p[i + 1].dy);
  }
  return path;
}

List<double> niceTicks(double lo, double hi, [int want = 4]) {
  final span = (hi - lo) == 0 ? 1.0 : hi - lo;
  final raw = span / want;
  final mag = pow(10, (log(raw) / ln10).floor()).toDouble();
  double step = raw;
  for (final k in [1.0, 2.0, 2.5, 5.0, 10.0]) {
    if (k * mag >= raw) {
      step = k * mag;
      break;
    }
  }
  final out = <double>[];
  for (var v = (lo / step).ceil() * step; v <= hi + 1e-9; v += step) {
    out.add(double.parse(v.toStringAsFixed(6)));
  }
  return out;
}

const _min = 60000, _hr = 3600000, _day = 86400000;

List<int> timeTicks(int t0, int t1, [int maxN = 5]) {
  final steps = [10 * _min, 30 * _min, _hr, 2 * _hr, 3 * _hr, 6 * _hr, 12 * _hr, _day, 2 * _day, 3 * _day, 5 * _day, 7 * _day];
  var step = steps.last;
  for (final s in steps) {
    if ((t1 - t0) / s <= maxN) {
      step = s;
      break;
    }
  }
  final off = DateTime.fromMillisecondsSinceEpoch(t0).timeZoneOffset.inMilliseconds;
  final out = <int>[];
  for (var t = ((t0 + off) / step).ceil() * step - off; t <= t1; t += step) {
    out.add(t);
  }
  return out;
}

void _text(Canvas c, String s, Offset at, {double size = 10.5, Color color = C.faint, String f = 'semi', TextAlign align = TextAlign.center}) {
  final tp = TextPainter(text: TextSpan(text: s, style: ts(size, color, f)), textDirection: TextDirection.ltr)..layout();
  double dx = at.dx;
  if (align == TextAlign.center) dx -= tp.width / 2;
  if (align == TextAlign.right || align == TextAlign.end) dx -= tp.width;
  tp.paint(c, Offset(dx, at.dy - tp.height / 2));
}

// ---------- ring gauge ----------
class Ring extends StatelessWidget {
  final double size, stroke, value;
  final Widget? child;
  const Ring({super.key, this.size = 150, this.stroke = 16, this.value = 0, this.child});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _RingPainter(stroke, value), child: Center(child: child)),
      );
}

class _RingPainter extends CustomPainter {
  final double stroke, value;
  _RingPainter(this.stroke, this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.width - stroke) / 2;
    final c = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = stroke..color = C.well);
    final p = value.clamp(0, 100) / 100;
    if (p > 0) {
      canvas.drawArc(
        rect,
        -pi / 2,
        2 * pi * p,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFB0CB84), Color(0xFF5F7F3A)])
              .createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.value != value || o.stroke != stroke;
}

// ---------- sparkline ----------
class Spark extends StatelessWidget {
  final List<double?> values;
  final Color color;
  final double height;
  const Spark({super.key, required this.values, this.color = C.matchaFlat, this.height = 34});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _SparkPainter(values.whereType<double>().toList(), color)),
      );
}

class _SparkPainter extends CustomPainter {
  final List<double> v;
  final Color color;
  _SparkPainter(this.v, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (v.length < 2) return;
    final lo = v.reduce(min), hi = v.reduce(max), span = (hi - lo) == 0 ? 1.0 : hi - lo;
    final pts = <Offset>[
      for (var i = 0; i < v.length; i++) Offset(3 + (i / (v.length - 1)) * (size.width - 6), 3 + (size.height - 6) * (1 - (v[i] - lo) / span)),
    ];
    canvas.drawPath(curvePath(pts), Paint()..style = PaintingStyle.stroke..strokeWidth = 2.4..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter o) => o.v != v || o.color != color;
}

// ---------- realtime line chart ----------
class ChartPoint {
  final int t; // epoch ms
  final double? v;
  const ChartPoint(this.t, this.v);
}

class RefLine {
  final double v;
  final String label;
  const RefLine(this.v, this.label);
}

/// x axis is real time (not point index). Drag across to read a value; release returns to live.
class LineChart extends StatefulWidget {
  final List<ChartPoint> points;
  final int t0, t1;
  final Color color;
  final double height;
  final int dec;
  final String unit;
  final void Function(ChartPoint?)? onSelect;
  final String Function(int)? fmtX;
  final int gapMs;
  final RefLine? refLine;
  final bool live;
  const LineChart({
    super.key,
    required this.points,
    required this.t0,
    required this.t1,
    this.color = C.matchaFlat,
    this.height = 190,
    this.dec = 0,
    this.unit = '',
    this.onSelect,
    this.fmtX,
    this.gapMs = 30 * _min,
    this.refLine,
    this.live = false,
  });

  @override
  State<LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<LineChart> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  int? _sel;
  double _w = 0;

  @override
  void initState() {
    super.initState();
    if (widget.live) _pulse.repeat();
  }

  @override
  void didUpdateWidget(LineChart o) {
    super.didUpdateWidget(o);
    if (widget.live && !_pulse.isAnimating) _pulse.repeat();
    if (!widget.live && _pulse.isAnimating) _pulse.stop();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  List<ChartPoint> get _pts => widget.points.where((p) => p.v != null).toList()..sort((a, b) => a.t.compareTo(b.t));

  static const _padL = 38.0, _padR = 12.0;

  void _pick(double x) {
    final pts = _pts;
    if (pts.isEmpty || _w <= 0) return;
    final iw = max(1.0, _w - _padL - _padR);
    final span = (widget.t1 - widget.t0) == 0 ? 1 : widget.t1 - widget.t0;
    var best = 0;
    var bd = double.infinity;
    for (var i = 0; i < pts.length; i++) {
      final px = _padL + ((pts[i].t - widget.t0) / span) * iw;
      final d = (px - x).abs();
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    if (best == _sel) return;
    setState(() => _sel = best);
    widget.onSelect?.call(pts[best]);
  }

  void _end() {
    if (_sel == null) return;
    setState(() => _sel = null);
    widget.onSelect?.call(null);
  }

  @override
  Widget build(BuildContext context) {
    final pts = _pts;
    if (pts.isEmpty) {
      return SizedBox(height: widget.height, child: const Center(child: T('No readings in this range yet', s: 13, c: C.faint)));
    }
    return LayoutBuilder(builder: (context, cons) {
      _w = cons.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (d) => _pick(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => _pick(d.localPosition.dx),
        onHorizontalDragEnd: (_) => _end(),
        onHorizontalDragCancel: _end,
        onTapDown: (d) => _pick(d.localPosition.dx),
        onTapUp: (_) => _end(),
        onTapCancel: _end,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) => CustomPaint(
            size: Size(cons.maxWidth, widget.height),
            painter: _LinePainter(
              pts: pts,
              t0: widget.t0,
              t1: widget.t1,
              color: widget.color,
              dec: widget.dec,
              unit: widget.unit,
              fmtX: widget.fmtX,
              gapMs: widget.gapMs,
              refLine: widget.refLine,
              live: widget.live,
              pulse: _pulse.value,
              sel: _sel,
            ),
          ),
        ),
      );
    });
  }
}

class _LinePainter extends CustomPainter {
  final List<ChartPoint> pts;
  final int t0, t1, gapMs, dec;
  final Color color;
  final String unit;
  final String Function(int)? fmtX;
  final RefLine? refLine;
  final bool live;
  final double pulse;
  final int? sel;
  _LinePainter({required this.pts, required this.t0, required this.t1, required this.color, required this.dec, required this.unit, this.fmtX, required this.gapMs, this.refLine, required this.live, required this.pulse, this.sel});

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 38.0, padR = 12.0, padT = 14.0, padB = 24.0;
    final w = size.width, height = size.height;
    var lo0 = pts.map((p) => p.v!).reduce(min), hi0 = pts.map((p) => p.v!).reduce(max);
    if (refLine != null) {
      lo0 = min(lo0, refLine!.v);
      hi0 = max(hi0, refLine!.v);
    }
    final span = (hi0 - lo0) == 0 ? max(1.0, hi0.abs() * 0.1) : hi0 - lo0;
    final lo = lo0 - span * 0.15, hi = hi0 + span * 0.15;
    final iw = max(1.0, w - padL - padR), ih = height - padT - padB;
    double X(int t) => padL + ((t - t0) / ((t1 - t0) == 0 ? 1 : t1 - t0)) * iw;
    double Y(double v) => padT + ih * (1 - (v - lo) / (hi - lo));

    final grid = Paint()..color = a(C.shadow, 0.13)..strokeWidth = 1.2;
    for (final tv in niceTicks(lo, hi, height > 170 ? 4 : 3)) {
      _dashed(canvas, Offset(padL, Y(tv)), Offset(w - padR, Y(tv)), grid, 3, 6);
      _text(canvas, tv.toStringAsFixed(dec), Offset(padL - 7, Y(tv)), align: TextAlign.right);
    }
    for (final t in timeTicks(t0, t1, w < 340 ? 3 : w < 520 ? 4 : 6)) {
      final x = X(t);
      if (x < padL + 14 || x > w - padR - 14) continue;
      _text(canvas, fmtX != null ? fmtX!(t) : '', Offset(x, height - 8));
    }
    if (refLine != null && refLine!.v >= lo && refLine!.v <= hi) {
      final y = Y(refLine!.v);
      _dashed(canvas, Offset(padL, y), Offset(w - padR, y), Paint()..color = a(C.warn, 0.8)..strokeWidth = 1.6, 6, 5);
      _text(canvas, refLine!.label, Offset(w - padR, y - 9), color: C.warn, f: 'bold', align: TextAlign.right);
    }

    // break the line wherever the device stopped reporting
    final runs = <List<Offset>>[];
    var cur = <Offset>[];
    for (var i = 0; i < pts.length; i++) {
      if (i > 0 && pts[i].t - pts[i - 1].t > gapMs) {
        runs.add(cur);
        cur = <Offset>[];
      }
      cur.add(Offset(X(pts[i].t), Y(pts[i].v!)));
    }
    runs.add(cur);

    final fill = Paint()
      ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [a(color, 0.32), a(color, 0)])
          .createShader(Rect.fromLTWH(0, padT, w, ih));
    final line = Paint()..style = PaintingStyle.stroke..strokeWidth = 2.6..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round..color = color;
    for (final r in runs) {
      if (r.length > 1) {
        final p = curvePath(r)..lineTo(r.last.dx, padT + ih)..lineTo(r.first.dx, padT + ih)..close();
        canvas.drawPath(p, fill);
      }
    }
    for (final r in runs) {
      if (r.length > 1) {
        canvas.drawPath(curvePath(r), line);
      } else if (r.length == 1) {
        canvas.drawCircle(r[0], 3.2, Paint()..color = color);
      }
    }

    final last = pts.last;
    final sp = sel != null ? pts[min(sel!, pts.length - 1)] : null;
    if (sp == null) {
      final c = Offset(X(last.t), Y(last.v!));
      if (live) {
        canvas.drawCircle(c, 11 * (0.5 + 1.1 * pulse), Paint()..color = a(color, 0.35 * (1 - pulse)));
      }
      canvas.drawCircle(c, 4.5, Paint()..color = Colors.white);
      canvas.drawCircle(c, 4.5, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.5..color = color);
    } else {
      final x = X(sp.t), y = Y(sp.v!);
      canvas.drawLine(Offset(x, padT), Offset(x, padT + ih), Paint()..color = a(color, 0.5)..strokeWidth = 1.4);
      canvas.drawCircle(Offset(x, y), 6, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(x, y), 6, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = color);
      final label = '${sp.v!.toStringAsFixed(dec)}$unit';
      final tw = max(46.0, label.length * 8.0 + 16);
      final tx = min(max(x - tw / 2, padL), w - padR - tw), ty = max(0.0, y - 40);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(tx, ty, tw, 26), const Radius.circular(9)), Paint()..color = C.matchaInk);
      _text(canvas, label, Offset(tx + tw / 2, ty + 13), size: 12.5, color: Colors.white, f: 'bold');
    }
  }

  void _dashed(Canvas c, Offset a0, Offset b, Paint p, double on, double off) {
    final len = (b - a0).distance;
    final dir = (b - a0) / len;
    var d = 0.0;
    while (d < len) {
      c.drawLine(a0 + dir * d, a0 + dir * min(d + on, len), p);
      d += on + off;
    }
  }

  @override
  bool shouldRepaint(_LinePainter o) => true;
}

// ---------- bars ----------
class BarDatum {
  final String label;
  final double value;
  const BarDatum(this.label, this.value);
}

class BarChart extends StatelessWidget {
  final List<BarDatum> data;
  final double height;
  final Color color;
  final int dec;
  const BarChart({super.key, required this.data, this.height = 140, this.color = C.matchaFlat, this.dec = 1});

  @override
  Widget build(BuildContext context) => SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: _BarPainter(data, color, dec)));
}

class _BarPainter extends CustomPainter {
  final List<BarDatum> data;
  final Color color;
  final int dec;
  _BarPainter(this.data, this.color, this.dec);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, height = size.height;
    final n = data.length;
    if (n == 0) return;
    final mx = max(0.1, data.map((d) => d.value).reduce(max));
    const padB = 20.0, padT = 16.0;
    final ih = height - padB - padT;
    final slot = w / n, bw = min(26.0, slot * 0.62);
    final every = n > 10 ? (n / 6).ceil() : 1;
    canvas.drawLine(Offset(0, padT + ih), Offset(w, padT + ih), Paint()..color = a(C.shadow, 0.16)..strokeWidth = 1.5);
    for (var i = 0; i < n; i++) {
      final d = data[i];
      final h = max(d.value > 0 ? 6.0 : 3.0, ih * (d.value / mx));
      final x = slot * i + (slot - bw) / 2, y = padT + ih - h;
      final rect = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, bw, h), Radius.circular(min(8.0, bw / 2)));
      if (d.value > 0) {
        canvas.drawRRect(rect, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [const Color(0xFFA9C57C), color]).createShader(rect.outerRect));
      } else {
        canvas.drawRRect(rect, Paint()..color = C.well);
      }
      if (n <= 10 && d.value > 0) _text(canvas, d.value.toStringAsFixed(dec), Offset(x + bw / 2, y - 9), color: C.matchaInk, f: 'bold');
      if (i % every == 0) _text(canvas, d.label, Offset(x + bw / 2, height - 8));
    }
  }

  @override
  bool shouldRepaint(_BarPainter o) => o.data != data;
}

// ---------- daily min/max temperature capsules ----------
class RangeDatum {
  final String label;
  final double? min, max, avg;
  const RangeDatum(this.label, this.min, this.max, this.avg);
}

class RangeChart extends StatelessWidget {
  final List<RangeDatum> data;
  final double height;
  const RangeChart({super.key, required this.data, this.height = 160});

  @override
  Widget build(BuildContext context) {
    if (!data.any((d) => d.min != null)) {
      return SizedBox(height: height, child: const Center(child: T('No temperature history yet', s: 13, c: C.faint)));
    }
    return SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: _RangePainter(data)));
  }
}

class _RangePainter extends CustomPainter {
  final List<RangeDatum> data;
  _RangePainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, height = size.height;
    final have = data.where((d) => d.min != null && d.max != null).toList();
    if (have.isEmpty) return;
    final lo0 = have.map((d) => d.min!).reduce(min) - 1, hi0 = have.map((d) => d.max!).reduce(max) + 1;
    const padL = 30.0, padB = 20.0, padT = 8.0;
    final ih = height - padB - padT, iw = max(1.0, w - padL - 4);
    double Y(double v) => padT + ih * (1 - (v - lo0) / (hi0 - lo0));
    final n = data.length, slot = iw / n, bw = min(16.0, slot * 0.55), every = n > 10 ? (n / 6).ceil() : 1;
    final gp = Paint()..color = a(C.shadow, 0.12)..strokeWidth = 1.5;
    for (final t in [hi0, (hi0 + lo0) / 2, lo0]) {
      var x = padL;
      while (x < w - 4) {
        canvas.drawLine(Offset(x, Y(t)), Offset(min(x + 4, w - 4), Y(t)), gp);
        x += 10;
      }
      _text(canvas, t.round().toString(), Offset(padL - 6, Y(t)), align: TextAlign.right);
    }
    for (var i = 0; i < n; i++) {
      final d = data[i];
      final x = padL + slot * i + slot / 2;
      if (d.min != null && d.max != null) {
        final rect = RRect.fromRectAndRadius(Rect.fromLTWH(x - bw / 2, Y(d.max!), bw, max(8.0, Y(d.min!) - Y(d.max!))), Radius.circular(bw / 2));
        canvas.drawRRect(rect, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE3A66E), Color(0xFFB9C98F)]).createShader(rect.outerRect));
      }
      if (d.avg != null) canvas.drawCircle(Offset(x, Y(d.avg!)), 3.2, Paint()..color = Colors.white);
      if (i % every == 0) _text(canvas, d.label, Offset(x, height - 8));
    }
  }

  @override
  bool shouldRepaint(_RangePainter o) => o.data != data;
}

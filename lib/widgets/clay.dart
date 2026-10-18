import 'dart:math';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/util.dart';
import 'icons.dart';

/// Text helper: size, colour, weight name (reg / semi / bold / black).
class T extends StatelessWidget {
  final String text;
  final double s;
  final Color c;
  final String f;
  final TextAlign? align;
  final int? maxLines;
  final double? ls, h;
  final TextStyle? style;
  const T(this.text, {super.key, this.s = 15, this.c = C.ink, this.f = 'semi', this.align, this.maxLines, this.ls, this.h, this.style});

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: align,
        maxLines: maxLines,
        overflow: maxLines != null ? TextOverflow.ellipsis : null,
        style: ts(s, c, f, ls, h).merge(style),
      );
}

/// Raised clay surface: diagonal gradient + lit top-left rim + soft drop shadow.
class Clay extends StatelessWidget {
  final Widget child;
  final double radius;
  final List<Color> colors;
  final double depth;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double? width, height;
  final AlignmentGeometry? alignment;
  const Clay({
    super.key,
    required this.child,
    this.radius = 26,
    this.colors = C.card,
    this.depth = 1,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.width,
    this.height,
    this.alignment,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    final ri = BorderRadius.circular(max(0, radius - 2));
    Widget w = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        color: colors[1],
        boxShadow: [
          BoxShadow(color: a(C.shadow, 0.26 * min(depth, 1.2)), blurRadius: 14 * depth, offset: Offset(6 * depth, 9 * depth)),
        ],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: r,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [a(Colors.white, 0.95), a(C.shadow, 0.16)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: ri,
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
            ),
            child: Container(alignment: alignment, width: width, height: height, padding: padding, child: child),
          ),
        ),
      ),
    );
    if (margin != null) w = Padding(padding: margin!, child: w);
    return w;
  }
}

/// Pressed-in surface (tracks, segmented control).
class Well extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  const Well({super.key, required this.child, this.radius = 18, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: C.well,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: a(C.shadow, 0.12), width: 2),
        ),
        child: Padding(padding: padding, child: child),
      );
}

/// Tap target with a small spring-scale and a light haptic.
class Press extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;
  final double scale;
  const Press({super.key, required this.onTap, required this.child, this.scale = 0.97});

  @override
  State<Press> createState() => _PressState();
}

class _PressState extends State<Press> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final on = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: on ? (_) => setState(() => _down = true) : null,
      onTapCancel: on ? () => setState(() => _down = false) : null,
      onTapUp: on ? (_) => setState(() => _down = false) : null,
      onTap: on
          ? () {
              tick();
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

enum BtnKind { matcha, soft, danger }

class ClayButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final BtnKind kind;
  final String? icon;
  final bool disabled, loading;
  const ClayButton({super.key, required this.label, this.onPressed, this.kind = BtnKind.matcha, this.icon, this.disabled = false, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final matcha = kind == BtnKind.matcha, danger = kind == BtnKind.danger;
    final colors = matcha ? C.matcha : danger ? const [Color(0xFFF8E7DF), Color(0xFFEDCFC3)] : C.card;
    final color = matcha ? Colors.white : danger ? C.bad : C.matchaInk;
    final off = disabled || loading;
    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: Press(
        onTap: off ? null : onPressed,
        child: Clay(
          colors: colors,
          radius: 22,
          depth: matcha ? 0.9 : 0.6,
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: color))
              else if (icon != null)
                AIcon(icon!, size: 20, color: color),
              if (loading || icon != null) const SizedBox(width: 8),
              if (label.isNotEmpty) Flexible(child: T(label, s: 15.5, f: 'bold', c: color, maxLines: 1)),
            ],
          ),
        ),
      ),
    );
  }
}

class Segmented extends StatelessWidget {
  final List<(String, String)> options; // (key, label)
  final String value;
  final ValueChanged<String> onChanged;
  const Segmented({super.key, required this.options, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final n = options.length;
    final idx = max(0, options.indexWhere((o) => o.$1 == value));
    return Well(
      radius: 22,
      padding: const EdgeInsets.all(4),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              alignment: Alignment(n == 1 ? 0 : -1 + 2 * idx / (n - 1), 0),
              child: FractionallySizedBox(
                widthFactor: 1 / n,
                heightFactor: 1,
                child: const Clay(radius: 17, depth: 0.45, padding: EdgeInsets.zero, child: SizedBox.expand()),
              ),
            ),
          ),
          Row(
            children: [
              for (final o in options)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      tick();
                      onChanged(o.$1);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                      child: Center(child: T(o.$2, s: 13.5, f: o.$1 == value ? 'bold' : 'semi', c: o.$1 == value ? C.matchaInk : C.mute, maxLines: 1)),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class ChipTag extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const ChipTag({super.key, required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) => Press(
        onTap: onTap,
        scale: 0.95,
        child: Clay(
          radius: 16,
          depth: on ? 0.5 : 0.3,
          colors: on ? C.matcha : C.card,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
          child: T(label, s: 13, f: 'bold', c: on ? Colors.white : C.mute),
        ),
      );
}

class ClayToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool disabled;
  const ClayToggle({super.key, required this.value, required this.onChanged, this.disabled = false});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: disabled
            ? null
            : () {
                tick();
                onChanged(!value);
              },
        child: Semantics(
          toggled: value,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 58,
            height: 34,
            decoration: BoxDecoration(
              color: value ? C.mist : C.well,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: a(C.shadow, 0.14), width: 2),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.all(1),
                child: Clay(radius: 13, depth: 0.35, colors: value ? C.matcha : C.card, width: 26, height: 26, padding: EdgeInsets.zero, child: const SizedBox.shrink()),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NumStepper extends StatelessWidget {
  final String label;
  final String? hint;
  final num value;
  final String unit;
  final ValueChanged<num> onChanged;
  final num min, max, step;
  final bool disabled;
  final String Function(num)? format;
  const NumStepper({
    super.key,
    required this.label,
    this.hint,
    required this.value,
    this.unit = '',
    required this.onChanged,
    required this.min,
    required this.max,
    this.step = 1,
    this.disabled = false,
    this.format,
  });

  void _set(num v) {
    final c = v < min ? min : (v > max ? max : v);
    onChanged(c is double ? double.parse(c.toStringAsFixed(1)) : c);
  }

  Widget _btn(String icon, num d) {
    final off = disabled || (d < 0 ? value <= min : value >= max);
    return Opacity(
      opacity: off ? 0.35 : 1,
      child: Press(
        onTap: off ? null : () => _set(value + d),
        child: Clay(radius: 15, depth: 0.4, width: 34, height: 34, padding: EdgeInsets.zero, alignment: Alignment.center, child: AIcon(icon, size: 18, color: C.matchaInk, sw: 2.2)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = format != null ? format!(value) : '${value is double && value == value.roundToDouble() ? value.toInt() : value}$unit';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                T(label, s: 15, f: 'bold'),
                if (hint != null) T(hint!, s: 12.5, c: C.mute, f: 'reg'),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _btn('minus', -step),
          const SizedBox(width: 6),
          SizedBox(width: 64, child: T(shown, s: 15.5, f: 'black', c: C.matchaInk, align: TextAlign.center)),
          const SizedBox(width: 6),
          _btn('plus', step),
        ],
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String label;
  final String tone;
  final bool dot;
  const Pill(this.label, {super.key, this.tone = 'ok', this.dot = true});

  @override
  Widget build(BuildContext context) {
    final col = const {'ok': C.ok, 'warn': C.warn, 'bad': C.bad, 'info': C.info, 'mute': C.mute}[tone] ?? C.ok;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: a(col, 0.13), borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) Container(width: 7, height: 7, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
        if (dot) const SizedBox(width: 6),
        T(label, s: 12, f: 'bold', c: col),
      ]),
    );
  }
}

class Div extends StatelessWidget {
  const Div({super.key});
  @override
  Widget build(BuildContext context) => Container(height: 1.5, margin: const EdgeInsets.symmetric(vertical: 6), color: a(C.shadow, 0.09));
}

class Gap extends StatelessWidget {
  final double h;
  const Gap([this.h = 14, Key? key]) : super(key: key);
  @override
  Widget build(BuildContext context) => SizedBox(height: h);
}

class Header extends StatelessWidget {
  final String title;
  final String? sub;
  final Widget? right;
  const Header({super.key, required this.title, this.sub, this.right});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                T(title, s: 28, f: 'black', c: C.matchaInk, ls: -0.6),
                if (sub != null) T(sub!, s: 14, c: C.mute, f: 'reg'),
              ]),
            ),
            if (right != null) right!,
          ],
        ),
      );
}

class Label extends StatelessWidget {
  final String text;
  final EdgeInsetsGeometry padding;
  const Label(this.text, {super.key, this.padding = const EdgeInsets.only(bottom: 8)});
  @override
  Widget build(BuildContext context) => Padding(padding: padding, child: T(text.toUpperCase(), s: 12.5, f: 'bold', c: C.mute, ls: 0.8));
}

/// Scrollable page with pull-to-refresh, safe-area padding and room for the floating tab bar.
class PageScroll extends StatelessWidget {
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final double maxWidth;
  final bool wide;
  const PageScroll({super.key, required this.children, this.onRefresh, this.maxWidth = 760, this.wide = false});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final pad = mq.size.width >= 768 ? 28.0 : 18.0;
    final body = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(pad, mq.padding.top + 14, pad, wide ? 40 : 130 + mq.padding.bottom),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    );
    if (onRefresh == null) return body;
    return RefreshIndicator(color: C.matchaDeep, backgroundColor: Colors.white, onRefresh: onRefresh!, child: body);
  }
}

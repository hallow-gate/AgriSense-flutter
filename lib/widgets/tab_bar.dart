import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/util.dart';
import 'clay.dart';
import 'icons.dart';

class TabDef {
  final String key, label, icon;
  const TabDef(this.key, this.label, this.icon);
}

/// Phones: floating bar at the bottom. Wide screens: a rail on the side.
class AppTabBar extends StatelessWidget {
  final List<TabDef> tabs;
  final String active;
  final ValueChanged<String> onChanged;
  final bool rail;
  const AppTabBar({super.key, required this.tabs, required this.active, required this.onChanged, this.rail = false});

  @override
  Widget build(BuildContext context) => rail ? _rail() : _bottom(context);

  Widget _bottom(BuildContext context) {
    final inset = MediaQuery.of(context).padding.bottom;
    final n = tabs.length, idx = tabs.indexWhere((t) => t.key == active);
    return Positioned(
      left: 0,
      right: 0,
      bottom: (inset > 10 ? inset : 10) + 2,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Clay(
              radius: 32,
              depth: 1.1,
              padding: const EdgeInsets.all(6),
              child: Stack(children: [
                Positioned.fill(
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutBack,
                    alignment: Alignment(n == 1 ? 0 : -1 + 2 * (idx < 0 ? 0 : idx) / (n - 1), 0),
                    child: FractionallySizedBox(
                      widthFactor: 1 / n,
                      heightFactor: 1,
                      child: const Padding(padding: EdgeInsets.all(1), child: Clay(colors: C.matcha, radius: 25, depth: 0.55, padding: EdgeInsets.zero, child: SizedBox.expand())),
                    ),
                  ),
                ),
                Row(children: [
                  for (final t in tabs)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          tick();
                          onChanged(t.key);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            AIcon(t.icon, size: 21, color: t.key == active ? Colors.white : C.mute),
                            const SizedBox(height: 3),
                            T(t.label, s: 10.5, f: t.key == active ? 'bold' : 'semi', c: t.key == active ? Colors.white : C.mute, maxLines: 1),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rail() {
    return SafeArea(
      child: Container(
        width: 220,
        padding: const EdgeInsets.fromLTRB(16, 22, 8, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(
            padding: EdgeInsets.only(left: 6, bottom: 26),
            child: Row(children: [Sprout(size: 30), SizedBox(width: 8), T('AgriSense', s: 20, f: 'black', c: C.matchaInk, ls: -0.4)]),
          ),
          for (final t in tabs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Press(
                onTap: () => onChanged(t.key),
                child: t.key == active
                    ? Clay(colors: C.matcha, radius: 20, depth: 0.5, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14), child: _railItem(t, true))
                    : Padding(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16), child: _railItem(t, false)),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _railItem(TabDef t, bool on) => Row(children: [
        AIcon(t.icon, size: 21, color: on ? Colors.white : C.mute),
        const SizedBox(width: 12),
        T(t.label, s: 15, f: on ? 'bold' : 'semi', c: on ? Colors.white : C.mute),
      ]);
}

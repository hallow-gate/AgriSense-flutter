import 'package:flutter/material.dart';

import '../core/query.dart';
import '../core/theme.dart';
import '../core/util.dart';
import '../widgets/clay.dart';
import '../widgets/icons.dart';

class _Row extends StatelessWidget {
  final String icon, tone, title;
  final String? sub, right, rightSub;
  const _Row({required this.icon, required this.tone, required this.title, this.sub, this.right, this.rightSub});

  @override
  Widget build(BuildContext context) {
    final col = toneColor(tone);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: a(col, 0.13), shape: BoxShape.circle), child: Center(child: AIcon(icon, size: 18, color: col))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            T(title, s: 14.5, f: 'bold'),
            if (sub != null && sub!.isNotEmpty) T(sub!, s: 12.5, c: C.mute, f: 'reg', maxLines: 3),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (right != null) T(right!, s: 12, c: C.mute, f: 'semi'),
          if (rightSub != null) T(rightSub!, s: 11.5, c: C.faint, f: 'reg'),
        ]),
      ]),
    );
  }
}

class _ListCard extends StatelessWidget {
  final List<Widget> rows;
  final String empty;
  final bool loading;
  final Object? error;
  final bool more;
  final VoidCallback? onMore;
  const _ListCard({required this.rows, required this.empty, required this.loading, this.error, this.more = false, this.onMore});

  @override
  Widget build(BuildContext context) => Clay(
        radius: 26,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
        child: Column(children: [
          if (rows.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 18), child: Center(child: T(loading ? 'Loading…' : error != null ? '$error' : empty, s: 14, c: C.mute)))
          else
            for (var i = 0; i < rows.length; i++) ...[if (i > 0) const Div(), rows[i]],
          if (more)
            Press(onTap: onMore, child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Center(child: T('Load older', s: 13.5, f: 'bold', c: C.matchaFlat)))),
        ]),
      );
}

class _Activity extends StatefulWidget {
  final bool active;
  const _Activity({super.key, required this.active});
  @override
  State<_Activity> createState() => _ActivityState();
}

class _ActivityState extends State<_Activity> {
  String group = 'all';
  late PagedQuery p = PagedQuery('/api/events?group=$group', 'events')..reload();

  void _set(String g) {
    setState(() {
      group = g;
      p.dispose();
      p = PagedQuery('/api/events?group=$g', 'events')..reload();
    });
  }

  @override
  void dispose() {
    p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: p,
        builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final g in const [('all', 'All'), ('water', 'Watering'), ('cover', 'Cover'), ('skipped', 'Skipped')])
                ChipTag(label: g.$2, on: group == g.$1, onTap: () => _set(g.$1)),
            ]),
          ),
          _ListCard(
            empty: 'No activity yet.',
            loading: p.loading,
            error: p.error,
            more: p.next != null,
            onMore: p.more,
            rows: [
              for (final e in p.items)
                Builder(builder: (_) {
                  final m = eventMeta(e);
                  return _Row(icon: m.icon, tone: m.tone, title: m.title, sub: m.sub, right: ago(e['occurred_at'] as String?), rightSub: stamp(e['occurred_at'] as String?));
                }),
            ],
          ),
        ]),
      );
}

class _History extends StatefulWidget {
  const _History({super.key});
  @override
  State<_History> createState() => _HistoryState();
}

class _HistoryState extends State<_History> {
  final q = ApiQuery('/api/stats?days=30')..setActive(true);

  @override
  void dispose() {
    q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: q,
        builder: (context, _) {
          final days = ((q.data?['days'] as List?) ?? const []).whereType<Map>().toList().reversed.toList();
          return _ListCard(
            empty: 'No history yet.',
            loading: q.loading,
            error: q.error,
            rows: [
              for (final d in days)
                Builder(builder: (_) {
                  final dt = DateTime.tryParse('${d['date']}T12:00:00') ?? DateTime.now();
                  final waterings = numOf(d['waterings']) ?? 0, skipped = numOf(d['skipped']) ?? 0, shade = numOf(d['shade_moves']) ?? 0;
                  final has = d['avg_temp'] != null || waterings > 0 || shade > 0;
                  final sub = [
                    if (d['avg_hum'] != null) 'humidity ${d['avg_hum']}%',
                    if (d['avg_soil'] != null) 'soil ${d['avg_soil']}%',
                  ].join(' · ');
                  return Opacity(
                    opacity: has ? 1 : 0.45,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(children: [
                        SizedBox(
                          width: 46,
                          child: Column(children: [
                            T(weekdayShort(dt), s: 11, f: 'bold', c: C.mute),
                            T('${dt.day}', s: 20, f: 'black', c: C.matchaInk),
                          ]),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            T(d['avg_temp'] != null ? '${fmt(numOf(d['min_temp']), '', 0)}–${fmt(numOf(d['max_temp']), '°', 0)}, avg ${fmt(numOf(d['avg_temp']), '°', 1)}' : 'No sensor data', s: 14, f: 'bold'),
                            T(sub.isEmpty ? ' ' : sub, s: 12.5, c: C.mute, f: 'reg'),
                          ]),
                        ),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          if (waterings > 0) Pill('${waterings.toInt()}× · ${d['liters']} L', tone: 'info', dot: false) else if (skipped > 0) const Pill('skipped', tone: 'mute', dot: false),
                          if (shade > 0) T('cover ×${shade.toInt()}', s: 11.5, c: C.faint),
                        ]),
                      ]),
                    ),
                  );
                }),
            ],
          );
        },
      );
}

class _Users extends StatefulWidget {
  final String? role;
  const _Users({super.key, required this.role});
  @override
  State<_Users> createState() => _UsersState();
}

class _UsersState extends State<_Users> {
  final p = PagedQuery('/api/audit', 'logs')..reload();

  @override
  void dispose() {
    p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: p,
        builder: (context, _) {
          final admin = widget.role == 'admin';
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: T(admin ? 'Every sign-in, command and settings change, newest first.' : 'Your own sign-ins and actions.', s: 13, c: C.mute, f: 'reg'),
            ),
            _ListCard(
              empty: 'No entries yet.',
              loading: p.loading,
              error: p.error,
              more: p.next != null,
              onMore: p.more,
              rows: [
                for (final l in p.items)
                  Builder(builder: (_) {
                    final m = auditMeta(l);
                    final dev = [l['ip'], deviceName(l['user_agent'] as String?)].where((x) => x != null && '$x'.isNotEmpty).join(' · ');
                    final sub = [if (admin) l['actor_email'], m.sub, dev].where((x) => x != null && '$x'.isNotEmpty).join('\n');
                    return _Row(icon: m.icon, tone: m.tone, title: m.title, sub: sub, right: ago(l['created_at'] as String?), rightSub: stamp(l['created_at'] as String?));
                  }),
              ],
            ),
          ]);
        },
      );
}

class LogsScreen extends StatefulWidget {
  final bool active;
  final Map<String, dynamic>? user;
  const LogsScreen({super.key, required this.active, required this.user});
  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  String tab = 'activity';
  int nonce = 0;

  @override
  Widget build(BuildContext context) {
    final admin = widget.user?['role'] == 'admin';
    return PageScroll(
      onRefresh: () async => setState(() => nonce++),
      children: [
        const Header(title: 'Logs', sub: 'What the garden and its people have been up to'),
        Segmented(options: [('activity', 'Activity'), ('history', 'History'), ('users', admin ? 'Users' : 'My access')], value: tab, onChanged: (v) => setState(() => tab = v)),
        const Gap(16),
        if (tab == 'activity') _Activity(key: ValueKey('a$nonce'), active: widget.active),
        if (tab == 'history') _History(key: ValueKey('h$nonce')),
        if (tab == 'users') _Users(key: ValueKey('u$nonce'), role: widget.user?['role'] as String?),
      ],
    );
  }
}

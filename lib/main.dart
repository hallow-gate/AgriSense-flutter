import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/api.dart';
import 'core/lock.dart';
import 'core/query.dart';
import 'core/theme.dart';
import 'screens/control.dart';
import 'screens/device.dart';
import 'screens/home.dart';
import 'screens/login.dart';
import 'screens/logs.dart';
import 'screens/stats.dart';
import 'widgets/clay.dart';
import 'widgets/icons.dart';
import 'widgets/tab_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  await Api.i.init();
  runApp(const AgriSenseApp());
}

class AgriSenseApp extends StatefulWidget {
  const AgriSenseApp({super.key});
  @override
  State<AgriSenseApp> createState() => _AgriSenseAppState();
}

class _AgriSenseAppState extends State<AgriSenseApp> {
  bool booted = false;
  Map<String, dynamic>? user;

  @override
  void initState() {
    super.initState();
    Api.i.onAuthLost = () {
      if (mounted) setState(() => user = null);
    };
    _boot();
  }

  Future<void> _boot() async {
    final s = Api.i.session;
    if (s != null) {
      try {
        user = await Api.i.me();
      } on ApiError catch (e) {
        // offline at launch: keep the session, the screens show the error
        if (e.status == 0) user = (s['user'] as Map?)?.cast<String, dynamic>();
      }
    }
    if (mounted) setState(() => booted = true);
  }

  Future<void> _signOut() async {
    StatusStore.i.setActive(false);
    await Api.i.logout();
    StatusStore.i.data = null;
    if (mounted) setState(() => user = null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AgriSense',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: !booted
          ? const Scaffold(backgroundColor: C.bg, body: Center(child: Sprout(size: 64)))
          : user == null
              ? LoginScreen(onDone: (u) => setState(() => user = u))
              : Shell(user: user!, onSignOut: _signOut),
    );
  }
}

const _tabs = [
  TabDef('home', 'Home', 'home'),
  TabDef('stats', 'Stats', 'chart'),
  TabDef('logs', 'Logs', 'list'),
  TabDef('control', 'Control', 'sliders'),
  TabDef('device', 'Device', 'chip'),
];

class Shell extends StatefulWidget {
  final Map<String, dynamic> user;
  final Future<void> Function() onSignOut;
  const Shell({super.key, required this.user, required this.onSignOut});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  String tab = 'home';
  final Set<String> seen = {'home'};
  bool locked = false;
  DateTime? bgAt;
  static const _relockAfter = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    StatusStore.i.setActive(true);
    lockEnabled().then((on) {
      if (on && mounted) setState(() => locked = true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    StatusStore.i.setActive(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      bgAt ??= DateTime.now();
      if (state != AppLifecycleState.inactive) StatusStore.i.setActive(false); // the widget / live service take over
    } else if (state == AppLifecycleState.resumed) {
      StatusStore.i.setActive(true);
      final since = bgAt;
      bgAt = null;
      if (since != null && DateTime.now().difference(since) > _relockAfter) {
        lockEnabled().then((on) {
          if (on && mounted) setState(() => locked = true);
        });
      }
    }
  }

  void _go(String k) => setState(() {
        tab = k;
        seen.add(k);
      });

  Widget _screen(String key, bool active) {
    switch (key) {
      case 'home':
        return HomeScreen(active: active, go: _go);
      case 'stats':
        return StatsScreen(active: active);
      case 'logs':
        return LogsScreen(active: active, user: widget.user);
      case 'control':
        return ControlScreen(active: active, user: widget.user);
      default:
        return DeviceScreen(active: active, user: widget.user, onSignOut: widget.onSignOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final idx = _tabs.indexWhere((t) => t.key == tab);
    final stack = Stack(children: [
      IndexedStack(
        index: idx,
        children: [
          for (final t in _tabs) seen.contains(t.key) ? _screen(t.key, t.key == tab && !locked) : const SizedBox.shrink(),
        ],
      ),
      if (!wide) AppTabBar(tabs: _tabs, active: tab, onChanged: _go),
    ]);
    return Scaffold(
      backgroundColor: C.bg,
      body: Stack(children: [
        Positioned.fill(
          child: wide
              ? Row(children: [
                  AppTabBar(tabs: _tabs, active: tab, onChanged: _go, rail: true),
                  Expanded(child: stack),
                ])
              : stack,
        ),
        if (locked) Positioned.fill(child: _LockScreen(onUnlock: () => setState(() => locked = false))),
      ]),
    );
  }
}

class _LockScreen extends StatefulWidget {
  final VoidCallback onUnlock;
  const _LockScreen({required this.onUnlock});
  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  bool busy = false;

  Future<void> _run() async {
    if (busy) return;
    setState(() => busy = true);
    if (await unlock()) {
      widget.onUnlock();
      return;
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  Widget build(BuildContext context) => Container(
        color: C.bg,
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Clay(radius: 48, padding: EdgeInsets.all(24), child: Sprout(size: 48)),
          const SizedBox(height: 18),
          const T('AgriSense is locked', s: 24, f: 'black', c: C.matchaInk),
          const SizedBox(height: 18),
          ClayButton(label: 'Unlock', icon: 'lock', loading: busy, onPressed: _run),
        ]),
      );
}

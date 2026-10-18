import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/bridge.dart';
import '../core/lock.dart';
import '../core/query.dart';
import '../core/theme.dart';
import '../core/util.dart';
import '../widgets/clay.dart';
import '../widgets/icons.dart';

class DeviceScreen extends StatefulWidget {
  final bool active;
  final Map<String, dynamic>? user;
  final Future<void> Function() onSignOut;
  const DeviceScreen({super.key, required this.active, required this.user, required this.onSignOut});
  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  final st = StatusStore.i;
  bool lock = false, bio = false;
  bool live = false;
  bool notify = false, notifyOnlyProblems = false, notifyInstant = false;
  int interval = 10;
  int widgets = 0;
  String widgetMsg = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DeviceScreen o) {
    super.didUpdateWidget(o);
    if (widget.active && !o.active) _load();
  }

  Future<void> _load() async {
    final l = await lockEnabled();
    final b = await biometricsAvailable();
    final lv = await Native.getLive();
    final nt = await Native.getNotify();
    final n = await Native.widgetCount();
    if (!mounted) return;
    setState(() {
      lock = l;
      bio = b;
      live = lv.enabled;
      notify = nt.enabled;
      notifyOnlyProblems = nt.onlyProblems;
      notifyInstant = nt.instant;
      interval = lv.intervalSec;
      widgets = n;
    });
  }

  Future<void> _setLive(bool on) async {
    if (on) await Native.requestNotificationPermission();
    await Native.setLive(on, interval);
    if (mounted) setState(() => live = on);
  }

  Future<void> _setNotify(bool on) async {
    if (on) await Native.requestNotificationPermission();
    await Native.setNotify(on, notifyOnlyProblems, notifyInstant);
    if (mounted) setState(() => notify = on);
  }

  Future<void> _setOnlyProblems(bool v) async {
    await Native.setNotify(notify, v, notifyInstant);
    if (mounted) setState(() => notifyOnlyProblems = v);
  }

  Future<void> _setInstant(bool v) async {
    await Native.setNotify(notify, notifyOnlyProblems, v);
    if (mounted) setState(() => notifyInstant = v);
  }

  Widget _notifyCard() {
    return Clay(
      radius: 28,
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                T('Notify me about new events', s: 15, f: 'bold'),
                T('Get a notification when the system waters, moves the cover, refuses an action, goes offline or reports a sensor fault.', s: 12.5, c: C.mute, f: 'reg'),
              ]),
            ),
          ),
          ClayToggle(value: notify, onChanged: _setNotify),
        ]),
        if (notify) ...[
          const Div(),
          Row(children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  T('Problems only', s: 15, f: 'bold'),
                  T('Skip routine watering and cover moves.', s: 12.5, c: C.mute, f: 'reg'),
                ]),
              ),
            ),
            ClayToggle(value: notifyOnlyProblems, onChanged: _setOnlyProblems),
          ]),
          const Div(),
          Row(children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  T('Instant alerts', s: 15, f: 'bold'),
                  T('Keeps watching every few seconds, even with the screen off, so you hear about events within seconds. Shows a small always-on notification and uses more battery.', s: 12.5, c: C.mute, f: 'reg'),
                ]),
              ),
            ),
            ClayToggle(value: notifyInstant, onChanged: _setInstant),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: T(notifyInstant ? 'If alerts still arrive late, set battery use for AgriSense to Unrestricted in your phone\'s battery settings.' : 'Without Instant alerts, new events are checked about every 15 minutes in the background.', s: 12, c: C.faint, f: 'reg'),
          ),
          if (notifyInstant) ...[const Gap(10), ClayButton(kind: BtnKind.soft, icon: 'bolt', label: 'Battery settings', onPressed: Native.openBatterySettings)],
        ],
      ]),
    );
  }

  Future<void> _setInterval(int s) async {
    setState(() => interval = s);
    await Native.setLive(live, s);
  }

  Future<void> _addWidget() async {
    final ok = await Native.requestPinWidget();
    if (!mounted) return;
    setState(() => widgetMsg = ok
        ? 'Confirm the prompt to place it. You can resize it afterwards by long-pressing it.'
        : 'Your launcher does not offer one-tap adding. Long-press the home screen, open Widgets and choose AgriSense.');
    Future.delayed(const Duration(seconds: 3), _load);
  }

  Widget _row(String label, String? value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [T(label, s: 14, c: C.mute), T(value ?? '–', s: 14, f: 'bold')]),
      );

  Widget _bars(num? rssi) {
    final n = rssi == null ? 0 : rssi > -55 ? 4 : rssi > -65 ? 3 : rssi > -75 ? 2 : 1;
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (var i = 0; i < 4; i++)
        Padding(
          padding: const EdgeInsets.only(left: 3),
          child: Container(width: 5, height: [6.0, 10.0, 14.0, 18.0][i], decoration: BoxDecoration(color: i < n ? C.matchaFlat : C.well, borderRadius: BorderRadius.circular(2.5))),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: st,
      builder: (context, _) {
        final t = st.telemetry;
        final online = st.data?['online'] == true;
        final host = Api.i.base.replaceFirst(RegExp(r'^https?://'), '');
        final heap = numOf(t['heap']);
        final user = widget.user;
        return PageScroll(
          onRefresh: st.reload,
          children: [
            const Header(title: 'Device', sub: 'The ESP32 in your garden'),
            Clay(
              radius: 28,
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Container(width: 52, height: 52, decoration: BoxDecoration(color: C.mist, borderRadius: BorderRadius.circular(18)), child: const Center(child: AIcon('chip', size: 26, color: C.matchaDeep))),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        T('AgriSense node', s: 18, f: 'black', c: C.matchaInk),
                        T(t['updated_at'] != null ? 'Last seen ${ago(t['updated_at'] as String?)}' : 'Never seen', s: 13, c: C.mute, f: 'reg'),
                      ]),
                    ),
                    if (st.data != null) Pill(online ? 'Online' : 'Offline', tone: online ? 'ok' : 'bad'),
                  ]),
                ),
                const Div(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    T('Wi-Fi signal', s: 14, c: C.mute),
                    Row(children: [T(t['rssi'] != null ? '${t['rssi']} dBm' : '', s: 13, c: C.faint), const SizedBox(width: 8), _bars(numOf(t['rssi']))]),
                  ]),
                ),
                _row('Uptime', uptime(numOf(t['uptime_s']))),
                _row('Restarts', t['boots']?.toString()),
                _row('Free memory', heap != null ? '${(heap / 1024).round()} KB' : null),
                _row('Firmware', t['fw']?.toString()),
                _row('Soil sensor', t['soil_fault'] == true ? 'Fault' : t['soil_pct'] != null ? 'Working' : null),
              ]),
            ),
            if (Native.supported) ...[
              const Gap(22),
              const Label('Notifications'),
              _notifyCard(),
              const Gap(22),
              const Label('Home & lock screen widget'),
              _widgetCard(),
            ],
            const Gap(22),
            const Label('Account'),
            Clay(
              radius: 28,
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Container(width: 46, height: 46, decoration: BoxDecoration(color: C.mist, borderRadius: BorderRadius.circular(16)), child: const Center(child: AIcon('user', size: 23, color: C.matchaDeep))),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      T('${user?['email'] ?? ''}', s: 15, f: 'bold', maxLines: 1),
                      T(user?['role'] == 'admin' ? 'Admin · can control and change settings' : 'Viewer · read only', s: 12.5, c: C.mute, f: 'reg'),
                    ]),
                  ),
                ]),
                const Div(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          T('Lock with biometrics', s: 15, f: 'bold'),
                          T(bio ? 'Ask for fingerprint or face when you come back to the app.' : 'Set up a fingerprint or face unlock on this phone first.', s: 12.5, c: C.mute, f: 'reg'),
                        ]),
                      ),
                    ),
                    ClayToggle(
                      value: lock,
                      disabled: !bio,
                      onChanged: (v) async {
                        if (await setLockEnabled(v) && mounted) setState(() => lock = v);
                      },
                    ),
                  ]),
                ),
                const Gap(10),
                ClayButton(kind: BtnKind.danger, icon: 'logout', label: 'Sign out', onPressed: () => widget.onSignOut()),
              ]),
            ),
            Padding(padding: const EdgeInsets.only(top: 22), child: T('AgriSense 2.1 · $host', s: 12, c: C.faint, f: 'reg', align: TextAlign.center)),
          ],
        );
      },
    );
  }

  Widget _widgetCard() {
    return Clay(
      radius: 28,
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(width: 46, height: 46, decoration: BoxDecoration(color: C.mist, borderRadius: BorderRadius.circular(16)), child: const Center(child: AIcon('widget', size: 23, color: C.matchaDeep))),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              T('Live readings widget', s: 16, f: 'black', c: C.matchaInk),
              T(widgets == 0 ? 'Temperature, humidity, soil moisture and online status.' : '$widgets on your screens · resize any of them freely', s: 12.5, c: C.mute, f: 'reg'),
            ]),
          ),
        ]),
        const Gap(14),
        ClayButton(icon: 'plus', label: 'Add widget to home screen', onPressed: _addWidget),
        if (widgetMsg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: T(widgetMsg, s: 12.5, c: C.mute, f: 'reg')),
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: T('Drag the widget\'s corners to any size. Long-press it and tap the settings icon to choose which readings to show, and a light, dark or transparent look. On phones and tablets that support lock-screen widgets, add it there too.', s: 12, c: C.faint, f: 'reg'),
        ),
        const Div(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  T('Real-time updates', s: 15, f: 'bold'),
                  T('Keeps the widget fresh every few seconds while the screen is on. Shows a small notification. Without it, widgets refresh about every 15 minutes.', s: 12.5, c: C.mute, f: 'reg'),
                ]),
              ),
            ),
            ClayToggle(value: live, onChanged: _setLive),
          ]),
        ),
        if (live) ...[
          const Gap(10),
          Segmented(
            options: const [('5', '5 s'), ('10', '10 s'), ('30', '30 s'), ('60', '1 min')],
            value: [5, 10, 30, 60].contains(interval) ? '$interval' : '10',
            onChanged: (v) => _setInterval(int.parse(v)),
          ),
          const Padding(padding: EdgeInsets.only(top: 8), child: T('Faster refresh uses more battery. The device itself reports about every 30 seconds.', s: 12, c: C.faint, f: 'reg')),
          const Gap(10),
          ClayButton(kind: BtnKind.soft, icon: 'bolt', label: 'Battery settings', onPressed: Native.openBatterySettings),
        ],
      ]),
    );
  }
}

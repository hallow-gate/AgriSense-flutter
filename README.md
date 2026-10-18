# AgriSense (Flutter)

Flutter port of the AgriSense app (same server, same API), plus an Android **home-screen / lock-screen widget**
that shows live temperature, humidity, soil moisture and device online/offline.

Screens: Login (Turnstile + biometric lock) · Home · Stats (live charts) · Logs · Control · Device.
The `server/`, firmware and Supabase parts of the original project are unchanged — keep using them.

## Build on Codemagic
1. Push this folder to a Git repo and add it in Codemagic. It picks up `codemagic.yaml`.
2. Set `API_URL` (your Render server) as an environment variable, or edit it in `codemagic.yaml`.
3. For a Play-Store-ready build, upload your keystore under Code signing identities with the reference name
   `agrisense_keystore`. Without it, the APK is debug-signed (fine for installing on your own phone).
4. Start the `android-release` workflow. Artifacts: `app-release.apk` and `app-release.aab`.

The server address can also be changed on the sign-in screen ("Server address"), so one build works with any server.
Turnstile: the site key and an allowed hostname are build variables (`TURNSTILE_SITE_KEY`, `TURNSTILE_BASE_URL`),
defaulting to the values in the original `app.json`.

Local build: `flutter pub get && flutter run --dart-define=API_URL=https://your-server`

## The widget
- Long-press the home screen → Widgets → **AgriSense**, or Device tab → *Add widget to home screen*.
- **Any size.** Drag the corners; the layout switches automatically between a wide strip, a grid and a compact stack,
  and every font scales to the space. Works from 1×1 up to full-screen tablets.
- **Settings per widget** (long-press → settings icon): choose which readings to show (temperature, humidity, soil,
  online status), Light / Dark / Auto / Transparent look, and background opacity.
- **Lock screen:** the widget declares itself lock-screen capable. It appears in the lock-screen picker only on devices
  and Android versions that support third-party lock-screen widgets.
- **Real-time:** Device tab → *Real-time updates* starts a small foreground service that refreshes every 5 / 10 / 30 / 60 s
  while the screen is on (a quiet notification shows the latest numbers). Without it, widgets refresh about every
  15 minutes (Android's limit for background work) and instantly whenever the app is open or you tap the refresh button.
  The ESP32 itself reports about every 30 s, so 10 s is plenty.
- Online/offline: online when the server says so **and** the last reading is under 2 minutes old; grey "No connection"
  when the phone can't reach the server (last values stay visible, dimmed).
- The widget signs in with the same session as the app (stored encrypted on the phone) and refreshes its own token.
  Signing out clears it.

## Notes
- Android only for now. An iOS widget needs a separate Swift WidgetKit extension.
- Android 13+: the app asks for notification permission the first time you turn on real-time updates.
  On some phones (Xiaomi, Huawei, Samsung "sleeping apps") exclude AgriSense from battery optimisation or the live
  service may be paused; the Device tab has a *Battery settings* shortcut.
- Package: `com.agrisense.app`, min Android 6.0 (API 23).

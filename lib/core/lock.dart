import 'package:local_auth/local_auth.dart';

import 'bridge.dart';

const _key = 'agrisense.applock';
final _auth = LocalAuthentication();

Future<bool> lockEnabled() async => (await Native.kvGet(_key)) == '1';

Future<bool> biometricsAvailable() async {
  try {
    return await _auth.isDeviceSupported() && (await _auth.getAvailableBiometrics()).isNotEmpty;
  } catch (_) {
    return false;
  }
}

Future<bool> unlock() async {
  try {
    return await _auth.authenticate(
      localizedReason: 'Unlock AgriSense',
      options: const AuthenticationOptions(stickyAuth: true),
    );
  } catch (_) {
    return false;
  }
}

Future<bool> setLockEnabled(bool on) async {
  if (on && !await unlock()) return false; // prove it works before turning it on
  if (on) {
    await Native.kvSet(_key, '1');
  } else {
    await Native.kvDelete(_key);
  }
  return true;
}

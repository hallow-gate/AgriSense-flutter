/// Build-time settings. Override with `--dart-define=NAME=value`
/// (Codemagic: set them as environment variables, see codemagic.yaml).
class Cfg {
  /// Your AgriSense server (the Render service), no trailing slash.
  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://your-agrisense-server.onrender.com',
  );

  /// Cloudflare Turnstile site key (public by design).
  static const String turnstileSiteKey = String.fromEnvironment(
    'TURNSTILE_SITE_KEY',
    defaultValue: '0x4AAAAAAFPyh2X1GS8e-smM',
  );

  /// A hostname that is on the Turnstile widget's allowed-hostnames list.
  static const String turnstileBaseUrl = String.fromEnvironment(
    'TURNSTILE_BASE_URL',
    defaultValue: 'https://agrisense-1-0.onrender.com',
  );
}

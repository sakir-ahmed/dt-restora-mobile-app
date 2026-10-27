/// Build-time configuration. The default is the public demo server.
/// For local development against `php artisan serve`, build with
/// `--dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1`
/// (10.0.2.2 is the Android emulator's alias for the host machine).
class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://dt-restora.datatechbd.com/api/v1',
  );

  static const String appVersion = '1.0.1';
  static const String platform = 'android';
}

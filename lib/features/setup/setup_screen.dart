import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';

/// One-time configuration shown on a fresh install: the app name (used on
/// the splash screen and around the app) and the API server. Saved on the
/// device and never shown again until app storage is cleared.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  bool _ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_ready) {
      _ready = true;
      final app = AppScope.read(context);
      _name.text = app.appName;
      _url.text = app.api.baseUrl;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    final name = _name.text.trim();
    final url = _url.text.trim();
    if (name.isEmpty) {
      snack(context, 'Give the app a name, for example your restaurant\'s name.', error: true);
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      snack(context, 'The server address must start with http:// or https://', error: true);
      return;
    }
    await app.completeSetup(name: name, baseUrl: url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 16),
            const Center(child: BrandLogo(size: 72)),
            const SizedBox(height: 22),
            Text('Welcome',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: context.fg, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('One-time setup: name this app and point it at your server.',
                textAlign: TextAlign.center, style: TextStyle(color: context.muted)),
            const SizedBox(height: 26),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  field(_name, 'App name', hint: 'e.g. Arman\'s Kitchen'),
                  field(_url, 'Server address (API base URL)',
                      hint: 'https://your-server.com/api/v1', type: TextInputType.url),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.brand.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Android emulator: http://10.0.2.2:8000/api/v1\nPhone on the same Wi-Fi: http://<computer-ip>:8000/api/v1',
                      style: TextStyle(fontSize: 12, color: context.muted, height: 1.5),
                    ),
                  ),
                ]),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _url.text = AppConfig.apiBaseUrl,
                icon: const Icon(Icons.cloud_outlined, size: 16),
                label: const Text('Use demo server'),
              ),
            ),
            const SizedBox(height: 4),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Save and continue'),
            ),
            const SizedBox(height: 10),
            Text(
              'The app name appears on the splash screen. You can change the server later from the login screen.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: context.muted),
            ),
          ],
        ),
      ),
    );
  }
}

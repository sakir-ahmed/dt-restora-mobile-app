import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';

/// Staff sign-in. The demo accounts mirror the web app's demo login.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit([String? login, String? password]) async {
    final app = AppScope.read(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await app.login(login ?? _login.text, password ?? _password.text);
    } on ApiException catch (e) {
      setState(() => _error = e.fullMessage);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _serverSettings() async {
    final app = AppScope.read(context);
    final c = TextEditingController(text: app.api.baseUrl);
    await showForm<void>(
      context,
      title: 'Server address',
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        field(c, 'API base URL', type: TextInputType.url),
        Text(
          'Emulator: http://10.0.2.2:8000/api/v1. A phone on the same Wi-Fi: http://<computer-ip>:8000/api/v1.',
          style: TextStyle(color: context.muted, fontSize: 12),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () async {
            await app.api.setBaseUrl(c.text);
            if (ctx.mounted) {
              Navigator.pop(ctx);
            }
          },
          child: const Text('Save'),
        ),
      ]),
    );
    c.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Server address',
                onPressed: _serverSettings,
                icon: const Icon(Icons.settings_ethernet),
              ),
            ),
            const SizedBox(height: 8),
            const BrandLogo(size: 72),
            const SizedBox(height: 20),
            Text('DT Restora',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: context.fg, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Sign in with your username, email or mobile.',
                style: TextStyle(color: context.muted)),
            const SizedBox(height: 24),
            TextField(
              controller: _login,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Username, email or mobile'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: !_showPassword,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Sign in'),
            ),
            const SizedBox(height: 28),
            Row(children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('Demo accounts', style: Theme.of(context).textTheme.labelLarge),
              ),
              const Expanded(child: Divider()),
            ]),
            const SizedBox(height: 4),
            Center(
              child: Text('Tap one to sign in. Password: $demoPassword',
                  style: TextStyle(color: context.muted, fontSize: 12)),
            ),
            const SizedBox(height: 12),
            for (final a in demoAccounts)
              Card(
                child: ListTile(
                  enabled: !_busy,
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: context.pageBg,
                    child: Icon(Icons.person, size: 18, color: context.brand),
                  ),
                  title: Text(a.role, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${a.username}  -  ${a.hint}'),
                  trailing: const Icon(Icons.login, size: 18),
                  onTap: () => _submit(a.username, demoPassword),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/config.dart';
import '../../core/sounds.dart';
import '../../core/theme.dart';
import '../../ui/widgets.dart';
import '../splash/splash_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// Edit the API server from settings, the same form as the login screen.
  Future<void> _editServer(BuildContext context, AppState app) async {
    final c = TextEditingController(text: app.api.baseUrl);
    final go = await showForm<bool>(
      context,
      title: 'Server address',
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        field(c, 'API base URL', type: TextInputType.url),
        Text(
          'Emulator: http://10.0.2.2:8000/api/v1. A phone on the same Wi-Fi: http://<computer-ip>:8000/api/v1.',
          style: TextStyle(color: ctx.muted, fontSize: 12),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () async {
            await app.api.setBaseUrl(c.text);
            if (ctx.mounted) {
              Navigator.pop(ctx, true);
            }
          },
          child: const Text('Save'),
        ),
      ]),
    );
    final text = c.text;
    c.dispose();
    if (go == true && context.mounted) {
      snack(context, text.startsWith('http') ? 'Server saved: $text' : 'Server not changed.');
    }
  }

  Future<void> _pickBranch(BuildContext context) async {    final app = AppScope.read(context);
    final res = await app.cachedGet('/customer/branches');
    if (!context.mounted) {
      return;
    }
    final branches = asRows(res.data);
    final chosen = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final b in branches)
              ListTile(
                leading: Icon(
                  b['id'] == app.branchId
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: context.brand,
                ),
                title: Text('${b['name']}'),
                onTap: () => Navigator.pop(ctx, (b['id'] as num).toInt()),
              ),
          ],
        ),
      ),
    );
    if (chosen != null && chosen != app.branchId) {
      await app.switchBranch(chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final branch =
        (app.bootstrap?['branch'] as Map?)?['name'] ?? 'Branch ${app.branchId}';
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: context.pageBg,
                child: Icon(Icons.person, color: context.brand),
              ),
              title: Text(app.userName),
              subtitle: Text(
                '${app.user?['email'] ?? ''}\n${app.roles.map(titleCase).join(', ')}',
              ),
              isThreeLine: true,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.store),
                  title: const Text('Branch'),
                  subtitle: Text('$branch'),
                  trailing: app.isMultiBranch
                      ? const Icon(Icons.chevron_right)
                      : null,
                  onTap: app.isMultiBranch ? () => _pickBranch(context) : null,
                ),
                ListTile(
                  leading: const Icon(Icons.language),
                  title: const Text('Menu language'),
                  trailing: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'en', label: Text('EN')),
                      ButtonSegment(value: 'bn', label: Text('BN')),
                    ],
                    selected: {app.locale},
                    onSelectionChanged: (s) => app.setLocale(s.first),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.brightness_6),
                  title: const Text('Appearance'),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.settings_suggest),
                          label: Text('Auto'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode),
                          label: Text('Light'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode),
                          label: Text('Dark'),
                        ),
                      ],
                      selected: {app.themeMode},
                      onSelectionChanged: (s) => app.setThemeMode(s.first),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const Text('Refresh menu and settings'),
                  onTap: () async {
                    await app.loadBootstrap();
                    if (context.mounted) {
                      snack(context, 'Reference data refreshed.');
                    }
                  },
                ),
                const _SoundsTile(),
                _BrandingTile(
                  onPreviewSplash: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        body: SplashScreen(onDone: () => Navigator.of(context).pop()),
                      ),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.dns),
                  title: const Text('Server'),
                  subtitle: Text(app.api.baseUrl),
                  trailing: const Icon(Icons.edit_outlined, size: 18),
                  onTap: () => _editServer(context, app),
                ),
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Version'),
                  subtitle: Text(AppConfig.appVersion),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Brand.danger),
            onPressed: () async {
              final waiting = app.pendingCount + app.conflictCount;
              final ok = await confirm(
                context,
                'Sign out?',
                body: waiting > 0
                    ? '$waiting offline items have not been uploaded. Signing out will delete them.'
                    : null,
                action: 'Sign out',
              );
              if (ok) {
                await app.logout();
                if (context.mounted) {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                }
              }
            },
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

/// Branding: rename the app, pick the brand colour that themes the whole
/// app and the splash screen, and preview the splash.
class _BrandingTile extends StatelessWidget {
  const _BrandingTile({required this.onPreviewSplash});

  final VoidCallback onPreviewSplash;

  Future<void> _rename(BuildContext context, AppState app) async {
    final c = TextEditingController(text: app.appName);
    final go = await showForm<bool>(
      context,
      title: 'App name',
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        field(c, 'Shown on the splash screen and headers'),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
      ]),
    );
    final name = c.text;
    c.dispose();
    if (go == true && name.trim().isNotEmpty) {
      await app.setAppName(name);
      if (context.mounted) {
        snack(context, 'App renamed to ${app.appName}.');
      }
    }
  }

  Future<void> _pickColor(BuildContext context, AppState app) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Brand colour', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Applies to buttons, tiles, charts and the splash screen.',
                style: TextStyle(color: ctx.muted, fontSize: 12)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final e in brandPalettes.entries)
                  InkWell(
                    borderRadius: BorderRadius.circular(36),
                    onTap: () {
                      app.setBrand(e.key);
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      width: 72,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: e.value.$1.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: app.brandKey == e.key ? e.value.$1 : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Column(children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [e.value.$1, e.value.$2],
                            ),
                          ),
                          child: app.brandKey == e.key
                              ? const Icon(Icons.check, color: Colors.white, size: 20)
                              : null,
                        ),
                        const SizedBox(height: 6),
                        Text(e.value.$3, style: const TextStyle(fontSize: 11)),
                      ]),
                    ),
                  ),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final (_, brandDark, name) = brandColors(app.brandKey);
    return Column(children: [
      ListTile(
        leading: CircleAvatar(
          backgroundColor: brandDark.withValues(alpha: 0.15),
          child: Text(
            app.appName.isEmpty ? '?' : app.appName[0].toUpperCase(),
            style: TextStyle(color: context.brand, fontWeight: FontWeight.w800),
          ),
        ),
        title: const Text('App name'),
        subtitle: Text(app.appName),
        trailing: const Icon(Icons.edit_outlined, size: 18),
        onTap: () => _rename(context, app),
      ),
      ListTile(
        leading: CircleAvatar(
          backgroundColor: context.brand.withValues(alpha: 0.15),
          child: Icon(Icons.palette_outlined, color: context.brand),
        ),
        title: const Text('Brand colour'),
        subtitle: Text(name),
        trailing: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [context.brand, brandDark]),
          ),
        ),
        onTap: () => _pickColor(context, app),
      ),
      ListTile(
        leading: Icon(Icons.play_circle_outline, color: context.brand),
        title: const Text('Preview splash screen'),
        subtitle: Text('See the splash with this name and colour'),
        onTap: onPreviewSplash,
      ),
    ]);
  }
}

/// Sound effects toggle and volume, like the branch sound settings on the
/// web app. Tapping the volume slider previews the payment chime.
class _SoundsTile extends StatefulWidget {
  const _SoundsTile();

  @override
  State<_SoundsTile> createState() => _SoundsTileState();
}

class _SoundsTileState extends State<_SoundsTile> {
  late bool _on = SoundFx.enabled;
  late double _volume = SoundFx.volume;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          secondary: Icon(
            _on ? Icons.volume_up : Icons.volume_off,
            color: context.brand,
          ),
          title: const Text('Sound effects'),
          subtitle: Text(
            _on ? 'Chimes for orders, payments and the kitchen' : 'Silent',
          ),
          value: _on,
          onChanged: (v) {
            setState(() => _on = v);
            SoundFx.setEnabled(v);
            if (v) {
              SoundFx.play('order_paid');
            }
          },
        ),
        if (_on)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.volume_down, size: 18, color: Brand.slate),
                Expanded(
                  child: Slider(
                    value: _volume,
                    onChanged: (v) {
                      setState(() => _volume = v);
                      SoundFx.setVolume(v);
                    },
                    onChangeEnd: (_) => SoundFx.play('order_paid'),
                  ),
                ),
                const Icon(Icons.volume_up, size: 18, color: Brand.slate),
              ],
            ),
          ),
      ],
    );
  }
}

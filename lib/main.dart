import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'core/api_client.dart';
import 'core/app_state.dart';
import 'core/local_db.dart';
import 'core/sounds.dart';
import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';
import 'features/setup/setup_screen.dart';
import 'features/splash/splash_screen.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A counter device must not sleep mid-shift.
  unawaited(WakelockPlus.enable());
  final state = AppState(api: ApiClient(), db: await LocalDb.open());
  await state.init();
  unawaited(SoundFx.init());
  runApp(DtRestoraApp(state: state));
}

class DtRestoraApp extends StatelessWidget {
  const DtRestoraApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => const _AppShell(),
      ),
    );
  }
}

/// The app shell: every page and every bottom popup lives above one
/// permanent footer, and the splash overlays the whole thing.
class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return MaterialApp(
      scaffoldMessengerKey: rootMessengerKey,
      title: state.appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light, brandKey: state.brandKey),
      darkTheme: buildTheme(Brightness.dark, brandKey: state.brandKey),
      // The device's colour scheme by default, the saved choice once
      // the user picks one in the app bar or drawer.
      themeMode: state.themeMode,
      home: const _Root(),
      // The footer sits below the navigator, so screens, drawers and
      // bottom sheets all stop above it, and the splash covers it all.
      // Both live inside the app so they get its direction, theme and
      // media query.
      builder: (context, child) => Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: child ?? const SizedBox.shrink()),
              const AppFooter(),
            ],
          ),
          if (!_splashDone)
            Positioned.fill(
              child: SplashScreen(onDone: () => setState(() => _splashDone = true)),
            ),
        ],
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final page = !app.configured
        ? const SetupScreen()
        : app.isLoggedIn
            ? const HomeScreen()
            : const LoginScreen();
    return _ConfirmExit(child: page);
  }
}

/// Asks for confirmation before the system back button closes the app.
class _ConfirmExit extends StatefulWidget {
  const _ConfirmExit({required this.child});

  final Widget child;

  @override
  State<_ConfirmExit> createState() => _ConfirmExitState();
}

class _ConfirmExitState extends State<_ConfirmExit> {
  bool _asking = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _asking) {
          return;
        }
        _asking = true;
        final ok = await confirm(context, 'Close DT Restora?',
            body: 'Do you really want to close the app?', action: 'Close app');
        _asking = false;
        if (ok && mounted) {
          SystemNavigator.pop();
        }
      },
      child: widget.child,
    );
  }
}

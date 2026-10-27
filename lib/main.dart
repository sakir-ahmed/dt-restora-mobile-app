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
        builder: (context, _) => MaterialApp(
          title: state.appName,
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          // The device's colour scheme by default, the saved choice once
          // the user picks one in the app bar or drawer.
          themeMode: state.themeMode,
          home: const _Root(),
        ),
      ),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final Widget page;
    if (!app.configured) {
      page = const SetupScreen();
    } else {
      page = app.isLoggedIn ? const HomeScreen() : const LoginScreen();
    }
    return _ConfirmExit(
      child: Stack(children: [
        Positioned.fill(child: page),
        if (!_splashDone)
          Positioned.fill(
            child: SplashScreen(onDone: () => setState(() => _splashDone = true)),
          ),
      ]),
    );
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/config.dart';
import '../../ui/widgets.dart';

/// Branded opening screen, kept deliberately minimal: the logo mark, the
/// app name, and a quiet three-dot loader. Runs once, fades out and hands
/// over to whatever _Root shows underneath (setup, login or home).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((status) async {
      if (status != AnimationStatus.completed) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted) {
        return;
      }
      setState(() => _leaving = true);
      await Future<void>.delayed(const Duration(milliseconds: 320));
      if (mounted) {
        widget.onDone();
      }
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final logoFade = CurvedAnimation(parent: _c, curve: const Interval(0, 0.3, curve: Curves.easeOut));
    final logoScale = CurvedAnimation(parent: _c, curve: const Interval(0, 0.45, curve: Curves.easeOutBack));
    final nameFade = CurvedAnimation(parent: _c, curve: const Interval(0.2, 0.55, curve: Curves.easeOut));
    final footerFade = CurvedAnimation(parent: _c, curve: const Interval(0.55, 0.8, curve: Curves.easeOut));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: AnimatedOpacity(
        opacity: _leaving ? 0 : 1,
        duration: const Duration(milliseconds: 320),
        // Scaffold gives the text a proper Material default style; without
        // it the name would render with Flutter's yellow debug underline.
        child: Scaffold(
          backgroundColor: const Color(0xFF0A1428),
          body: SafeArea(
            child: Column(children: [
              const Spacer(flex: 5),
              ScaleTransition(
                scale: logoScale,
                child: FadeTransition(opacity: logoFade, child: BrandLogo(size: 88)),
              ),
              const SizedBox(height: 26),
              FadeTransition(
                opacity: nameFade,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(nameFade),
                  child: Text(
                    app.appName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
              const Spacer(flex: 6),
              FadeTransition(
                opacity: footerFade,
                child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (var i = 0; i < 3; i++) ...[
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85 - i * 0.3),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 14),
                  Text(
                    'v${AppConfig.appVersion}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 11,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 30),
            ]),
          ),
        ),
      ),
    );
  }
}

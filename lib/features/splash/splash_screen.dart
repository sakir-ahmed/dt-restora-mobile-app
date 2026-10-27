import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../ui/widgets.dart';

/// Branded opening screen. Runs its animation once, fades out and hands
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
    duration: const Duration(milliseconds: 1900),
  );
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((status) async {
      if (status != AnimationStatus.completed) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!mounted) {
        return;
      }
      setState(() => _leaving = true);
      await Future<void>.delayed(const Duration(milliseconds: 350));
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
    final (_, brandDark, _) = brandColors(app.brandKey);
    final logoFade = CurvedAnimation(parent: _c, curve: const Interval(0, 0.28, curve: Curves.easeOut));
    final logoScale = CurvedAnimation(parent: _c, curve: const Interval(0, 0.45, curve: Curves.easeOutBack));
    final nameFade = CurvedAnimation(parent: _c, curve: const Interval(0.22, 0.5, curve: Curves.easeOut));
    final taglineFade = CurvedAnimation(parent: _c, curve: const Interval(0.38, 0.62, curve: Curves.easeOut));
    final progressFade = CurvedAnimation(parent: _c, curve: const Interval(0.6, 0.8, curve: Curves.easeOut));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: AnimatedOpacity(
        opacity: _leaving ? 0 : 1,
        duration: const Duration(milliseconds: 350),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [const Color(0xFF081020), const Color(0xFF0A1428), brandDark],
            ),
          ),
          child: SafeArea(
            child: Column(children: [
              const Spacer(flex: 5),
              // Logo card with a soft brand glow.
              ScaleTransition(
                scale: logoScale,
                child: FadeTransition(
                  opacity: logoFade,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: brandDark.withValues(alpha: 0.45),
                          blurRadius: 40,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset('assets/brand/logo-512.png', width: 84, height: 84),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              FadeTransition(
                opacity: nameFade,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.35), end: Offset.zero).animate(nameFade),
                  child: Column(children: [
                    Text(
                      app.appName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FadeTransition(
                      opacity: taglineFade,
                      child: const Text(
                        'Restaurant operations suite',
                        style: TextStyle(color: Brand.soft, fontSize: 13, letterSpacing: 0.6),
                      ),
                    ),
                  ]),
                ),
              ),
              const Spacer(flex: 6),
              FadeTransition(
                opacity: progressFade,
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(color: brandDark, strokeWidth: 2.4),
                ),
              ),
              const SizedBox(height: 34),
            ]),
          ),
        ),
      ),
    );
  }
}

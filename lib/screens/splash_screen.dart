// lib/screens/splash_screen.dart
import 'package:flutter/material.dart';

import '../widgets/app_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.initialize, this.onWelcomeReady});
  final Future<void> Function()? initialize;
  final Future<void> Function()? onWelcomeReady;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _initializationFailed = false;

  bool _started = false;

  void _welcomeReady() {
    if (_started || !mounted) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await widget.onWelcomeReady?.call();
      if (mounted) _start();
    });
  }

  Future<bool> _initialize() async {
    try {
      await widget.initialize?.call();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _start() async {
    final ready = await _initialize();
    if (!mounted) return;
    if (!ready) {
      setState(() => _initializationFailed = true);
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 2800));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => const AppShell(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFDDF6FC),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 환영 문구는 기존보다 살짝 아래에 배치합니다.
                const SizedBox(height: 1),
                const Text(
                  '환영합니다!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF123A63),
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Welcome!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF27866F),
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                // 로고는 환영 문구와의 간격을 줄여 기존보다 살짝 위로 올립니다.
                const SizedBox(height: 50),
                CompanySplashLogo(onReady: _welcomeReady),
                // 서비스명은 로고 아래로 조금 내려 배치하고 크기를 키웁니다.
                const SizedBox(height: 40),
                const Text(
                  'LK무역 종합 서비스 어플 by LK그룹',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF123A63),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'LK Trading Total Solution app',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF27866F),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'By LK Group',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF27866F),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 55),
                if (!_initializationFailed)
                  const SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Color(0xFF27866F),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  _initializationFailed
                      ? '서비스에 연결하지 못했습니다. 앱을 다시 실행해 주세요.'
                      : 'LK그룹 서비스에 접속 중 입니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF123A63),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CompanySplashLogo extends StatelessWidget {
  const CompanySplashLogo({super.key, this.onReady});
  final VoidCallback? onReady;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // Preserve the supplied LK Group Trading logo ratio and leave enough
      // horizontal safety margin for rounded/cutout displays.
      width: 190,
      height: 148,
      child: Image.asset(
        'assets/images/company_splash_logo.png',
        fit: BoxFit.contain,
        // Release the native splash only after this welcome image is ready.
        frameBuilder: (_, child, frame, synchronous) {
          if (synchronous || frame != null) onReady?.call();
          return child;
        },
        // A missing image must still allow startup and the connection message.
        errorBuilder: (_, __, ___) {
          onReady?.call();
          return const Icon(
            Icons.local_shipping,
            size: 92,
            color: Color(0xFF123A63),
          );
        },
      ),
    );
  }
}

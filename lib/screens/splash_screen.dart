// lib/screens/splash_screen.dart
import 'package:flutter/material.dart';

import '../widgets/app_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.initialize});
  final Future<void> Function()? initialize;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _showGroupLogo = true;
  bool _initializationFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    final initialized = _initialize();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    setState(() => _showGroupLogo = false);
    final ready = await initialized;
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
      body: _showGroupLogo
          ? const SafeArea(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: GroupLaunchLogo(),
                ),
              ),
            )
          : SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 28,
                  ),
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
                      const CompanySplashLogo(),
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

/// The supplied LK GROUP original is drawn as normal content, outside the OS
/// splash icon mask. BoxFit.contain preserves every edge in either orientation.
class GroupLaunchLogo extends StatelessWidget {
  const GroupLaunchLogo({super.key});

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 240, maxHeight: 190),
    child: Image.asset(
      'assets/images/lk_group_logo.png',
      fit: BoxFit.contain,
      semanticLabel: 'LK GROUP',
      filterQuality: FilterQuality.high,
    ),
  );
}

class CompanySplashLogo extends StatelessWidget {
  const CompanySplashLogo({super.key});

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
        // Original logo colors are intentionally preserved on the splash.
        errorBuilder: (_, __, ___) => const Icon(
          Icons.local_shipping,
          size: 92,
          color: Color(0xFF123A63),
        ),
      ),
    );
  }
}

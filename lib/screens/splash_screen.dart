// lib/screens/splash_screen.dart
import 'package:flutter/material.dart';
import '../widgets/app_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    Future.delayed(const Duration(milliseconds: 2800), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, __, ___) => const AppShell(),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFDDF6FC),
      body: FadeTransition(
        opacity: _fade,
        child: SafeArea(
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
                    'LK Trading Total Solution app by LK Group',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF27866F),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 55),
                  const SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Color(0xFF27866F),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'LK그룹 서비스에 접속 중 입니다.',
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
      ),
    );
  }
}

class CompanySplashLogo extends StatelessWidget {
  const CompanySplashLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      height: 130,
      child: Image.asset(
        'assets/images/company_logo_transparent.png',
        fit: BoxFit.contain,
        // Original logo colors are intentionally preserved on the splash.
        errorBuilder: (_, __, ___) => const Icon(Icons.local_shipping, size: 92, color: Color(0xFF123A63)),
      ),
    );
  }
}



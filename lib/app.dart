// lib/app.dart
// Replace this file entirely.
// If your main.dart calls CargoFlowApp() or App(), both are exported below.

import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';

// ── Public entry widgets ────────────────────────────────────────────────────
// main.dart typically calls: runApp(CargoFlowApp()) or runApp(App())
// Both names are provided for compatibility.

class CargoFlowApp extends StatelessWidget {
  const CargoFlowApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => const _RootApp();
}

/// Alias so projects that use App() also compile without changes.
class App extends StatelessWidget {
  const App({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => const _RootApp();
}

// ── Internal root ────────────────────────────────────────────────────────────
class _RootApp extends StatelessWidget {
  const _RootApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CargoFlow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF174B78),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF174B78),
          primary: const Color(0xFF174B78),
          secondary: const Color(0xFF00BCD4),
        ),
        // Must match the family name declared in pubspec.yaml.
        fontFamily: 'NotoSansKR',
        useMaterial3: false,
      ),
      // Always start with SplashScreen so the welcome screen shows on every launch.
      home: const SplashScreen(),
    );
  }
}

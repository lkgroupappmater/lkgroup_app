// lib/widgets/app_shell.dart
import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_language.dart';
import '../models/app_user.dart';
import 'cargo_flow_app_bar.dart';
import '../screens/dashboard_home_screen.dart';
import '../screens/shipment_search_screen.dart';
import '../screens/quote_request_screen.dart';
import '../screens/account_screen.dart';
import '../screens/cargo_management_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;
  AppLanguage _language = AppLanguage.korean;
  AppUser? _currentUser;
  bool get _isLoggedIn => _currentUser != null && _currentUser!.role.isLoggedIn;

  String get _title {
    switch (_currentIndex) {
      case 0: return AppStrings.get(_language, 'home_title');
      case 1: return AppStrings.get(_language, 'tracking_title');
      case 2: return AppStrings.get(_language, 'quote_title');
      case 3: return '화물/입고 관리';
      case 4: return AppStrings.get(_language, 'account_title');
      default: return 'LK Group';
    }
  }

  void _onLanguageChanged(AppLanguage language) {
    setState(() => _language = language);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${language.flag} ${language.label}')));
  }
  void _openAccount() => setState(() => _currentIndex = 4);
  void _onLoggedIn(AppUser user) {
    setState(() { _currentUser = user; _currentIndex = 1; });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${user.name.isEmpty ? '회원' : user.name}님 로그인되었습니다.')));
  }
  void _onLoggedOut() {
    setState(() { _currentUser = null; _currentIndex = 0; });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('로그아웃되었습니다.')));
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      DashboardHomeBody(language: _language),
      ShipmentSearchBody(language: _language, isLoggedIn: _isLoggedIn, onRequireLogin: _openAccount, onEditRequest: () => setState(() => _currentIndex = 3)),
      QuoteRequestBody(language: _language, onRequestLogin: _openAccount),
      if (_isLoggedIn) CargoManagementScreen(user: _currentUser!, onBack: () => setState(() => _currentIndex = 4)) else const SizedBox.shrink(),
      AccountBody(language: _language, currentUser: _currentUser, onLoggedIn: _onLoggedIn, onLoggedOut: _onLoggedOut, onOpenCargoManagement: _isLoggedIn ? () => setState(() => _currentIndex = 3) : null),
    ];
    final labels = <String>[AppStrings.get(_language, 'home'), AppStrings.get(_language, 'tracking'), AppStrings.get(_language, 'quote'), '화물 관리', AppStrings.get(_language, 'account')];
    return Scaffold(
      appBar: CargoFlowAppBar(title: _title, selectedLanguage: _language, onLanguageChanged: _onLanguageChanged, showHomeActions: _currentIndex == 0),
      body: IndexedStack(index: _currentIndex, children: tabs),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) { if (index == 3 && !_isLoggedIn) { _openAccount(); return; } setState(() => _currentIndex = index); },
        type: BottomNavigationBarType.fixed, backgroundColor: AppColors.primary, selectedItemColor: AppColors.tealAccent, unselectedItemColor: Colors.white70, selectedFontSize: 12, unselectedFontSize: 11, iconSize: 28,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: '홈'),
          BottomNavigationBarItem(icon: const Icon(Icons.local_shipping_outlined), activeIcon: const Icon(Icons.local_shipping), label: labels[1]),
          BottomNavigationBarItem(icon: const Icon(Icons.request_quote_outlined), activeIcon: const Icon(Icons.request_quote), label: labels[2]),
          BottomNavigationBarItem(icon: const Icon(Icons.inventory_2_outlined), activeIcon: const Icon(Icons.inventory_2), label: labels[3]),
          BottomNavigationBarItem(icon: const Icon(Icons.person_outline), activeIcon: const Icon(Icons.person), label: labels[4]),
        ],
      ),
    );
  }
}

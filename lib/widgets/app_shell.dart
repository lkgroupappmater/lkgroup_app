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
import '../services/auth_service.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;
  AppLanguage _language = AppLanguage.korean;

  @override
  void initState() {
    super.initState();
    AuthService.instance.restoreSession().then((_) {
      if (mounted && AuthService.instance.currentUser != null) {
        setState(() => _currentUser = AuthService.instance.currentUser);
      }
    });
  }
  AppUser? _currentUser;
  List<String> _cargoSelection = const <String>[];
  bool get _isLoggedIn => _currentUser != null && _currentUser!.role.isLoggedIn;
  String get _title {
    switch (_currentIndex) {
      case 0:
        return AppStrings.get(_language, 'home_title');
      case 1:
        return AppStrings.get(_language, 'tracking_title');
      case 2:
        return AppStrings.get(_language, 'quote_title');
      case 3:
        return _currentUser?.role == UserRole.admin ? '통합 관리' : '화물 관리';
      default:
        return AppStrings.get(_language, 'account_title');
    }
  }

  void _onLanguageChanged(AppLanguage value) {
    setState(() => _language = value);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('${value.flag} ${value.label}')));
  }

  void _openAccount() => setState(() => _currentIndex = 4);
  void _onLoggedIn(AppUser user) {
    setState(() {
      _currentUser = user;
      _currentIndex = 3;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(TextSnackBar('${user.name}님 로그인되었습니다.'));
  }

  Future<void> _onLoggedOut() async {
    await AuthService.instance.signOut();
    if (!mounted) return;
    setState(() {
      _currentUser = null;
      _currentIndex = 0;
    });
  }
  void _selectTab(int index) => setState(() => _currentIndex = index);

  void _openCargoManagement(List<String> invoices) {
    setState(() {
      _cargoSelection = invoices;
      _currentIndex = 3;
    });
  }
  @override
  Widget build(BuildContext context) {
    final tabs = [
      DashboardHomeBody(language: _language, currentUser: _currentUser),
      ShipmentSearchBody(
          language: _language,
          isLoggedIn: _isLoggedIn,
          onRequireLogin: _openAccount,
          onEditRequest: () => _selectTab(3),
          onManageSelected: _openCargoManagement),
      QuoteRequestBody(language: _language, onRequestLogin: _openAccount),
      if (_isLoggedIn)
        CargoManagementScreen(
            key: ValueKey(_cargoSelection.join('|')),
            user: _currentUser!,
            initialSelectedInvoices: _cargoSelection),
      if (!_isLoggedIn) const SizedBox.shrink(),
      AccountBody(
          currentUser: _currentUser,
          onLoggedIn: _onLoggedIn,
          onLoggedOut: _onLoggedOut)
    ];
    final navItems = [
      const BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: '홈'),
      BottomNavigationBarItem(
          icon: const Icon(Icons.local_shipping_outlined),
          activeIcon: const Icon(Icons.local_shipping),
          label: AppStrings.get(_language, 'tracking')),
      BottomNavigationBarItem(
          icon: const Icon(Icons.request_quote_outlined),
          activeIcon: const Icon(Icons.request_quote),
          label: AppStrings.get(_language, 'quote'))
    ];
    final navIndexes = [0, 1, 2];
    if (_isLoggedIn) {
      navItems.add(BottomNavigationBarItem(
          icon: const Icon(Icons.inventory_2_outlined),
          activeIcon: const Icon(Icons.inventory_2),
          label: _currentUser?.role == UserRole.admin ? '통합 관리' : '화물 관리'));
      navIndexes.add(3);
    }
    navItems.add(BottomNavigationBarItem(
        icon: const Icon(Icons.person_outline),
        activeIcon: const Icon(Icons.person),
        label: AppStrings.get(_language, 'account')));
    navIndexes.add(4);
    final selected = navIndexes.indexOf(_currentIndex);
    return Scaffold(
        appBar: CargoFlowAppBar(
            title: _title,
            selectedLanguage: _language,
            onLanguageChanged: _onLanguageChanged,
            showHomeActions: _currentIndex == 0),
        body: IndexedStack(index: _currentIndex, children: tabs),
        bottomNavigationBar: BottomNavigationBar(
            currentIndex: selected < 0 ? 0 : selected,
            onTap: (index) => _selectTab(navIndexes[index]),
            type: BottomNavigationBarType.fixed,
            backgroundColor: AppColors.primary,
            selectedItemColor: AppColors.tealAccent,
            unselectedItemColor: Colors.white70,
            items: navItems));
  }
}

class TextSnackBar extends SnackBar {
  TextSnackBar(String message) : super(content: Text(message));
}

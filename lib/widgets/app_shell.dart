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
import '../services/notification_service.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  AppLanguage _language = AppLanguage.korean;
  AppUser? _currentUser;
  List<String> _cargoSelection = const <String>[];
  List<Map<String, dynamic>> _unreadNotifications = const [];
  bool _popupShownForCurrentBatch = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AuthService.instance.restoreSession().then((_) async {
      if (!mounted) return;
      setState(() => _currentUser = AuthService.instance.currentUser);
      await _refreshNotifications(showPopup: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshUserRole();
      _refreshNotifications(showPopup: false);
    }
  }

  Future<void> _refreshUserRole() async {
    final before = _currentUser;
    if (before == null) return;
    final refreshed = await AuthService.instance.refreshCurrentUser();
    if (!mounted) return;
    setState(() {
      _currentUser = refreshed;
      if (refreshed == null) _currentIndex = 4;
    });
  }

  Future<void> _refreshNotifications({required bool showPopup}) async {
    if (_currentUser == null) {
      if (mounted) setState(() => _unreadNotifications = const []);
      return;
    }
    try {
      final rows = await NotificationService.instance.fetchUnread();
      if (!mounted) return;
      setState(() {
        _unreadNotifications = rows;
        if (rows.isEmpty) _popupShownForCurrentBatch = false;
      });
      if (showPopup && rows.isNotEmpty && !_popupShownForCurrentBatch) {
        _popupShownForCurrentBatch = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showUnreadPopup(rows);
        });
      }
    } catch (_) {
      // Notification failure must not interrupt login or navigation.
    }
  }

  Future<void> _showUnreadPopup(List<Map<String, dynamic>> rows) async {
    if (!mounted || rows.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('알림'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rows
                .take(5)
                .map((n) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text('${n['message'] ?? ''}'),
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _openNotifications() async {
    try {
      final rows = await NotificationService.instance.fetchRecent();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('알림'),
          content: SizedBox(
            width: double.maxFinite,
            child: rows.isEmpty
                ? const Text('새 알림이 없습니다.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (_, index) {
                      final n = rows[index];
                      return Text('${n['message'] ?? ''}');
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('닫기'),
            ),
          ],
        ),
      );
      await NotificationService.instance.markAllRead();
      if (!mounted) return;
      setState(() {
        _unreadNotifications = const [];
        _popupShownForCurrentBatch = false;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('알림 조회 실패: $error')));
    }
  }

  bool get _isLoggedIn => _currentUser != null && _currentUser!.role.isLoggedIn;

  String get _title {
    switch (_currentIndex) {
      case 0:
        return AppStrings.get(_language, 'home_title');
      case 1:
        return AppStrings.get(_language, 'tracking_title');
      case 2:
        return '운임 확인 및 견적 요청';
      case 3:
        return '화물 관리';
      default:
        return '사용자 로그인';
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
      _popupShownForCurrentBatch = false;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(TextSnackBar('${user.name}님 로그인되었습니다.'));
    _refreshNotifications(showPopup: true);
  }

  void _onUserUpdated(AppUser user) => setState(() => _currentUser = user);

  Future<void> _onLoggedOut() async {
    await AuthService.instance.signOut();
    if (!mounted) return;
    setState(() {
      _currentUser = null;
      _currentIndex = 0;
      _unreadNotifications = const [];
      _popupShownForCurrentBatch = false;
    });
  }

  void _selectTab(int index) {
    setState(() => _currentIndex = index);
    if (index == 0) _refreshNotifications(showPopup: false);
  }

  void _openCargoManagement(List<String> ids) {
    setState(() {
      _cargoSelection = ids;
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
        currentUser: _currentUser,
        onRequireLogin: _openAccount,
        onEditRequest: () => _selectTab(3),
        onManageSelected: _openCargoManagement,
      ),
      QuoteRequestBody(
        language: _language,
        onRequestLogin: _openAccount,
        onNotificationsChanged: () {
          _refreshNotifications(showPopup: false);
        },
      ),
      if (_isLoggedIn)
        CargoManagementScreen(
          key: ValueKey(
              '${_currentUser!.id}|${_currentUser!.role}|${_cargoSelection.join('|')}'),
          user: _currentUser!,
          initialSelectedIds: _cargoSelection,
        ),
      if (!_isLoggedIn) const SizedBox.shrink(),
      AccountBody(
        currentUser: _currentUser,
        onLoggedIn: _onLoggedIn,
        onLoggedOut: _onLoggedOut,
        onUserUpdated: _onUserUpdated,
      ),
    ];

    final navItems = <BottomNavigationBarItem>[
      const BottomNavigationBarItem(
        icon: Icon(Icons.home_outlined),
        activeIcon: Icon(Icons.home),
        label: '홈',
      ),
      BottomNavigationBarItem(
        icon: const Icon(Icons.local_shipping_outlined),
        activeIcon: const Icon(Icons.local_shipping),
        label: AppStrings.get(_language, 'tracking'),
      ),
    ];
    final navIndexes = <int>[0, 1];

    if (_isLoggedIn) {
      navItems.add(
        const BottomNavigationBarItem(
          icon: Icon(Icons.inventory_2_outlined),
          activeIcon: Icon(Icons.inventory_2),
          label: '화물 관리',
        ),
      );
      navIndexes.add(3);
    }

    navItems.add(
      BottomNavigationBarItem(
        icon: const Icon(Icons.request_quote_outlined),
        activeIcon: const Icon(Icons.request_quote),
        label: AppStrings.get(_language, 'quote'),
      ),
    );
    navIndexes.add(2);

    navItems.add(
      BottomNavigationBarItem(
        icon: const Icon(Icons.person_outline),
        activeIcon: const Icon(Icons.person),
        label: AppStrings.get(_language, 'account'),
      ),
    );
    navIndexes.add(4);

    final selected = navIndexes.indexOf(_currentIndex);
    return Scaffold(
      appBar: CargoFlowAppBar(
        title: _title,
        selectedLanguage: _language,
        onLanguageChanged: _onLanguageChanged,
        showHomeActions: _currentIndex == 0,
        onNotificationTap: _openNotifications,
        notificationCount: _unreadNotifications.length,
        titleFontSize: _currentIndex == 2 ? 17 : 21,
      ),
      body: IndexedStack(index: _currentIndex, children: tabs),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selected < 0 ? 0 : selected,
        onTap: (index) => _selectTab(navIndexes[index]),
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppColors.primary,
        selectedItemColor: AppColors.tealAccent,
        unselectedItemColor: Colors.white70,
        items: navItems,
      ),
    );
  }
}

class TextSnackBar extends SnackBar {
  TextSnackBar(String message) : super(content: Text(message));
}

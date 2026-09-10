import '../services/app_update_service.dart';
import 'app_update_banner.dart';
import 'auto_refresh_state.dart';
import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_language.dart';
import '../core/ui_localizations.dart';
import '../models/app_user.dart';
import 'cargo_flow_app_bar.dart';
import '../screens/dashboard_home_screen.dart';
import '../screens/shipment_search_screen.dart';
import '../screens/quote_request_screen.dart';
import '../screens/account_screen.dart';
import '../screens/cargo_management_screen.dart';
import '../screens/management_menu_screen.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver, AutoRefreshState<AppShell> {
  @override
  Set<String> get autoRefreshTopics => const {'notifications'};

  @override
  Future<void> refreshAutomatically() async {
    await _refreshNotifications(showPopup: false);
    await AppUpdateService.instance.check();
  }

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
    AppUpdateService.instance.check();
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
      AppUpdateService.instance.check(
        force: AppUpdateService.instance.value == AppUpdateStatus.downloading,
      );
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
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.get(_language, 'notifications')),
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
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppStrings.get(_language, 'confirm')),
          ),
        ],
      ),
    );

    // 로그인 팝업에서 사용자가 실제로 '확인'한 알림은 읽음 처리합니다.
    // 기존에는 팝업만 닫고 is_read=false 상태가 그대로라 다음 로그인 때
    // 같은 알림이 계속 다시 표시되었습니다.
    try {
      await NotificationService.instance.markAllRead();
      if (!mounted) return;
      setState(() {
        _unreadNotifications = const [];
        _popupShownForCurrentBatch = false;
      });
    } catch (_) {
      // 읽음 처리 실패가 앱 사용을 막지는 않도록 합니다.
      // 실패한 경우 DB에는 unread 상태가 남으므로 다음 새로고침에서 다시 확인 가능합니다.
    }
  }

  Future<void> _openNotifications() async {
    try {
      final rows = await NotificationService.instance.fetchRecent();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(AppStrings.get(_language, 'notifications')),
          content: SizedBox(
            width: double.maxFinite,
            child: rows.isEmpty
                ? Text(AppStrings.get(_language, 'no_notifications'))
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
              child: Text(AppStrings.get(_language, 'close')),
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
          .showSnackBar(SnackBar(
        content: Text(UiLocalizations.error(
          _language,
          '알림 조회 실패',
          error,
        )),
      ));
    }
  }

  bool get _isLoggedIn => _currentUser != null && _currentUser!.role.isLoggedIn;
  bool get _hasManagementMenu =>
      _currentUser?.role == UserRole.admin ||
      _currentUser?.role == UserRole.staff ||
      _currentUser?.role == UserRole.partner;


  String get _title {
    switch (_currentIndex) {
      case 0:
        return AppStrings.get(_language, 'home_title');
      case 1:
        return AppStrings.get(_language, 'tracking_title');
      case 2:
        return AppStrings.get(_language, 'quote_title');
      case 3:
        return AppStrings.get(_language, 'cargo_management_title');
      case 4:
        return AppStrings.get(_language, 'management_menu_title');
      default:
        return AppStrings.get(_language, 'login_title');
    }
  }

  void _onLanguageChanged(AppLanguage value) {
    setState(() => _language = value);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('${value.flag} ${value.label}')));
  }

  void _openAccount() => setState(() => _currentIndex = 5);

  void _onLoggedIn(AppUser user) {
    setState(() {
      _currentUser = user;
      _currentIndex = 3;
      _popupShownForCurrentBatch = false;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(TextSnackBar(UiLocalizations.format(
          _language,
          '{name}님 로그인되었습니다.',
          {'name': user.name},
        )));
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
          language: _language,
          initialSelectedIds: _cargoSelection,
        ),
      if (!_isLoggedIn) const SizedBox.shrink(),
      if (_hasManagementMenu)
        ManagementMenuScreen(
          user: _currentUser!,
          language: _language,
          onOpenCargoManagement: () => _selectTab(3),
        ),
      if (!_hasManagementMenu) const SizedBox.shrink(),
      AccountBody(
        currentUser: _currentUser,
        language: _language,
        onLoggedIn: _onLoggedIn,
        onLoggedOut: _onLoggedOut,
        onUserUpdated: _onUserUpdated,
      ),
    ];

    final navItems = <BottomNavigationBarItem>[
      BottomNavigationBarItem(
        icon: const Icon(Icons.home_outlined),
        activeIcon: const Icon(Icons.home),
        label: AppStrings.get(_language, 'home'),
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
        BottomNavigationBarItem(
          icon: const Icon(Icons.inventory_2_outlined),
          activeIcon: const Icon(Icons.inventory_2),
          label: AppStrings.get(_language, 'cargo_management'),
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

    if (_hasManagementMenu) {
      navItems.add(
        BottomNavigationBarItem(
          icon: const Icon(Icons.admin_panel_settings_outlined),
          activeIcon: const Icon(Icons.admin_panel_settings),
          label: AppStrings.get(_language, 'management_menu'),
        ),
      );
      navIndexes.add(4);
    }

    navItems.add(
      BottomNavigationBarItem(
        icon: const Icon(Icons.person_outline),
        activeIcon: const Icon(Icons.person),
        label: AppStrings.get(_language, 'account'),
      ),
    );
    navIndexes.add(5);

    final selected = navIndexes.indexOf(_currentIndex);
    final scaffold = Scaffold(
      appBar: CargoFlowAppBar(
        title: _title,
        selectedLanguage: _language,
        onLanguageChanged: _onLanguageChanged,
        // 알림은 계정별 비공개 데이터입니다. 비회원 홈에서는 회사 소개,
        // 공개 일정·공지만 표시하고 알림 조회 요청 자체를 보내지 않습니다.
        showHomeActions: _currentIndex == 0 && _isLoggedIn,
        onNotificationTap: _openNotifications,
        notificationCount: _unreadNotifications.length,
        titleFontSize: _currentIndex == 2 ? 17 : 21,
      ),
      body: Column(
        children: [
          if (_currentIndex == 0) AppUpdateBanner(language: _language),
          Expanded(child: IndexedStack(
            index: _currentIndex,
            children: [
              for (var i = 0; i < tabs.length; i++)
                AutoRefreshScope(active: _currentIndex == i, child: tabs[i]),
            ],
          )),
        ],
      ),
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
    final laoFont = _language.fontFamily;
    if (laoFont == null) return scaffold;
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: laoFont),
        primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: laoFont),
      ),
      child: scaffold,
    );
  }
}

class TextSnackBar extends SnackBar {
  TextSnackBar(String message) : super(content: Text(message));
}

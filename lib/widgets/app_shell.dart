import 'dart:async';
import '../screens/support_screen.dart';
import '../services/notification_alert.dart';
import '../services/code_update_service.dart';
import 'code_update_panel.dart';
import 'notification_list_dialog.dart';
import '../services/app_update_service.dart';
import 'app_update_banner.dart';
import 'auto_refresh_state.dart';

import 'package:flutter/material.dart';
import 'customer_identity_card.dart';

import '../core/app_colors.dart';
import '../core/app_language.dart';
import '../core/ui_localizations.dart';
import '../models/app_user.dart';
import 'cargo_flow_app_bar.dart';
import '../screens/dashboard_home_screen.dart';
import '../screens/shipment_search_screen.dart';
import '../screens/domestic_tracking_screen.dart';
import '../core/domestic_tracking_text.dart';
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

class _AppShellState extends State<AppShell>
    with WidgetsBindingObserver, AutoRefreshState<AppShell> {
  @override
  Set<String> get autoRefreshTopics => const {'notifications'};

  @override
  Future<void> refreshAutomatically() async {
    await _refreshNotifications(showPopup: false);
    await AppUpdateService.instance.check();
    await _codeUpdates.check();
    _scheduleUpdatePopup();
  }

  int _currentIndex = 0;
  AppLanguage _language = AppLanguage.korean;
  AppUser? _currentUser;
  List<String> _cargoSelection = const <String>[];
  final _seenNotifications = <String>{};
  String? _noticeOwner;
  int _notificationCount = 0;
  bool _notificationFetching = false;
  Timer? _notificationPoll;
  final _codeUpdates = CodeUpdateService.instance;
  bool _updatePopupOpen = false;
  bool _notificationPopupOpen = false;
  bool _accountPopupDeferred = false;
  bool _startupNotificationsReady = false;

  void _onCodeUpdate() {
    if (!mounted) return;
    setState(() {});
    _scheduleUpdatePopup();
  }

  void _scheduleUpdatePopup() {
    if (!mounted || !_startupNotificationsReady || !_codeUpdates.needsPopup)
      return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          _currentIndex != 0 ||
          _updatePopupOpen ||
          _notificationPopupOpen ||
          !_codeUpdates.needsPopup ||
          !canApplyAutoRefresh) return;
      _updatePopupOpen = true;
      try {
        await showCodeUpdateNotice(context, _codeUpdates, _language);
      } finally {
        _updatePopupOpen = false;
        if (mounted) {
          if (_accountPopupDeferred) {
            _accountPopupDeferred = false;
            _refreshNotifications(showPopup: true);
          }
          _scheduleUpdatePopup();
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppUpdateService.instance.check();
    _codeUpdates.addListener(_onCodeUpdate);
    _codeUpdates.check();
    _notificationPoll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed)
        _refreshNotifications(showPopup: true);
    });
    AuthService.instance.restoreSession().then((_) async {
      if (!mounted) return;
      setState(() => _currentUser = AuthService.instance.currentUser);
      await _refreshNotifications(showPopup: true);
    }).whenComplete(() {
      _startupNotificationsReady = true;
      _scheduleUpdatePopup();
    });
  }

  @override
  void dispose() {
    _notificationPoll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _codeUpdates.removeListener(_onCodeUpdate);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AppUpdateService.instance.check(
        force: AppUpdateService.instance.value == AppUpdateStatus.downloading,
      );
      _codeUpdates.check();
      _scheduleUpdatePopup();
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
    final userId = _currentUser?.id;
    if (_noticeOwner != userId) {
      _noticeOwner = userId;
      _seenNotifications.clear();
      _notificationCount = 0;
    }
    if (userId == null) {
      return;
    }
    if (_notificationFetching) return;
    _notificationFetching = true;
    try {
      final data = await NotificationService.instance.feed();
      if (!mounted || _currentUser?.id != userId) return;
      final rows = List<Map<String, dynamic>>.from(data['rows'] as List)
          .where((r) => r['is_read'] != true)
          .toList();
      final fresh = rows
          .where((r) => !_seenNotifications.contains('${r['id']}'))
          .toList();
      setState(() {
        _notificationCount = (data['unread_count'] as num?)?.toInt() ?? 0;
      });
      if (fresh.isNotEmpty &&
          (showPopup || _seenNotifications.isNotEmpty) &&
          !_notificationPopupOpen &&
          !_updatePopupOpen) {
        _seenNotifications.addAll(fresh.map((r) => '${r['id']}'));
        await NotificationAlert.play();
        if (mounted && ModalRoute.of(context)?.isCurrent != false)
          {
          _notificationFetching = false;
          await _showUnreadPopup(data);
        }
      }
    } catch (_) {
      /* Notification failure must not interrupt navigation. */
    } finally {
      _notificationFetching = false;
    }
  }

  Future<void> _showUnreadPopup(Map<String, dynamic> data) async {
    if (!mounted || _notificationPopupOpen || _updatePopupOpen) return;
    await _showNotificationList(data);
  }

  Future<void> _showNotificationList(Map<String, dynamic> data, {bool includeUpdates = false}) async {
    final owner = _currentUser?.id;
    _notificationPopupOpen = true;
    try {
      await showDialog<void>(context: context, builder: (_) => NotificationListDialog(
        language: _language, initial: data,
        header: includeUpdates ? CodeUpdatePanel(language: _language, service: _codeUpdates) : null,
        isCurrentOwner: () => mounted && _currentUser?.id == owner,
        loadPage: (offset) async {
          if (_currentUser?.id != owner) throw StateError('Account changed');
          final result = await NotificationService.instance.feed(offset: offset);
          if (mounted && _currentUser?.id == owner) setState(() => _notificationCount = (result['unread_count'] as num?)?.toInt() ?? 0);
          return result;
        },
        onReadAll: (id, at) async {
          if (_currentUser?.id != owner) throw StateError('Account changed');
          final result = await NotificationService.instance.readAll(id, at);
          if (mounted && _currentUser?.id == owner) setState(() => _notificationCount = (result['unread_count'] as num?)?.toInt() ?? 0);
          return result;
        },
        onOpen: _openNotificationTarget,
      ));
      if (includeUpdates) await _codeUpdates.acknowledge();
    } finally {
      _notificationPopupOpen = false;
      _scheduleUpdatePopup();
    }
  }

  Future<void> _openNotificationTarget(Map<String, dynamic> row) async {
    final owner = _currentUser?.id;
    if (owner == null) return;
    if (row['related_quote_id'] != null) {
      await showDialog<void>(context: context, builder: (c) => Dialog(
        child: SizedBox(width: 860, height: MediaQuery.sizeOf(c).height * .82,
          child: Column(children: [
            Align(alignment: Alignment.centerRight, child: TextButton(
              onPressed: () => Navigator.pop(c), child: Text(AppStrings.get(_language, 'close')))),
            Expanded(child: SupportDetailScreen(
              id: (row['related_quote_id'] as num).toInt(), language: _language,
              manager: const [UserRole.admin, UserRole.staff].contains(_currentUser?.role))),
          ])),
      ));
    } else {
      final related = row['request_details'] ?? (row['related_request_id'] == null ? null :
          await NotificationService.instance.relatedRequest((row['id'] as num).toInt()));
      if (!mounted || _currentUser?.id != owner) return;
      await NotificationService.instance.read((row['id'] as num).toInt());
      if (!mounted || _currentUser?.id != owner) return;
      row['is_read'] = true;
      await showDialog<void>(context: context, builder: (c) => AlertDialog(
        title: Text('${row['title'] ?? ''}'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${row['message'] ?? ''}'), const Divider(),
            for (final line in notificationDetails({...row, 'request_details': related}, _language)) Text(line),
          ])),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(AppStrings.get(_language, 'close')))],
      ));
    }
    if (mounted && _currentUser?.id == owner) await _refreshNotifications(showPopup: false);
  }

  Future<void> _openNotifications() async {
    if (_notificationPopupOpen || _updatePopupOpen) return;
    final owner = _currentUser?.id;
    _notificationPopupOpen = true;
    try {
      final data = await NotificationService.instance.feed();
      if (!mounted || _currentUser?.id != owner) return;
      await _showNotificationList(data, includeUpdates: true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      _notificationPopupOpen = false;
      _scheduleUpdatePopup();
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
    });
    ScaffoldMessenger.of(context).showSnackBar(
      TextSnackBar(
        UiLocalizations.format(_language, '{name}님 로그인되었습니다.', {
          'name': user.name,
        }),
      ),
    );
    _refreshNotifications(showPopup: true);
  }

  void _onUserUpdated(AppUser user) => setState(() => _currentUser = user);

  Future<void> _onLoggedOut() async {
    await AuthService.instance.signOut();
    if (!mounted) return;
    setState(() {
      _currentUser = null;
      _currentIndex = 0;
      _notificationCount = 0;
      _seenNotifications.clear();
      _noticeOwner = null;
    });
  }

  void _selectTab(int index) {
    setState(() => _currentIndex = index);
    if (index == 0) {
      _refreshNotifications(showPopup: false);
      _scheduleUpdatePopup();
    }
  }

  Future<void> _chooseTracking() async {
    final domestic = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.local_shipping_outlined),
            title: Text(AppStrings.get(_language, 'tracking_title')),
            onTap: () => Navigator.pop(sheetContext, false),
          ),
          ListTile(
            leading: const Icon(Icons.local_shipping_outlined),
            title: Text(domesticText(
                _language, _hasManagementMenu ? 'title' : 'publicTitle')),
            onTap: () => Navigator.pop(sheetContext, true),
          ),
        ]),
      ),
    );
    if (!mounted || domestic == null) return;
    if (!domestic) {
      _selectTab(1);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            DomesticTrackingScreen(language: _language, user: _currentUser)));
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
            '${_currentUser!.id}|${_currentUser!.role}|${_cargoSelection.join('|')}',
          ),
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
        customerIdentity: _isLoggedIn
            ? CustomerIdentityCard(
                key: ValueKey(
                    'header-id-${_currentUser!.id}-${_currentUser!.name}-${_currentUser!.phone}'),
                userId: _currentUser!.id,
                language: _language,
                compact: true,
                foregroundColor: Colors.white)
            : null,
        title: _title,
        selectedLanguage: _language,
        onLanguageChanged: _onLanguageChanged,
        // Device update notices are public to this device; account notices are
        // fetched only when logged in inside _openNotifications.
        showHomeActions: _currentIndex == 0,
        onNotificationTap: _openNotifications,
        notificationCount:
            _notificationCount + (_codeUpdates.hasUnread ? 1 : 0),
        titleFontSize: _currentIndex == 2 ? 17 : 21,
      ),
      body: Column(
        children: [
          if (_currentIndex == 0) ...[
            AppUpdateBanner(language: _language),
            CodeUpdateBanner(
              language: _language,
              service: _codeUpdates,
              onDetails: _openNotifications,
            ),
          ],
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: [
                for (var i = 0; i < tabs.length; i++)
                  AutoRefreshScope(active: _currentIndex == i, child: tabs[i]),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selected < 0 ? 0 : selected,
        onTap: (index) {
          if (navIndexes[index] == 1) {
            _chooseTracking();
          } else {
            _selectTab(navIndexes[index]);
          }
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppColors.primary,
        selectedItemColor: AppColors.tealAccent,
        unselectedItemColor: Colors.white70,
        items: navItems,
      ),
    );
    final laoFont = _language.fontFamily;
    final theme = Theme.of(context);
    return Theme(
      data: laoFont == null ? theme : theme.copyWith(
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


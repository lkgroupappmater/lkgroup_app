import 'dart:async';
import '../screens/support_screen.dart';
import '../services/notification_alert.dart';
import '../services/code_update_service.dart';
import 'code_update_panel.dart';
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
          await _showUnreadPopup(fresh);
      }
    } catch (_) {
      /* Notification failure must not interrupt navigation. */
    } finally {
      _notificationFetching = false;
    }
  }

  Widget _notificationTile(
          Map<String, dynamic> row, BuildContext dialogContext) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(row['is_read'] == true
            ? Icons.notifications_none
            : Icons.notifications_active_outlined),
        title: Text('${row['title'] ?? ''}'),
        subtitle: Text('${row['message'] ?? ''}'),
        onTap: () => Navigator.pop(dialogContext, row),
      );

  Future<void> _showUnreadPopup(List<Map<String, dynamic>> rows) async {
    if (!mounted || rows.isEmpty || _notificationPopupOpen || _updatePopupOpen)
      return;
    _notificationPopupOpen = true;
    final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (c) => AlertDialog(
              title: Text(
                  '${AppStrings.get(_language, 'notifications')} ($_notificationCount)'),
              content: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: rows
                              .take(5)
                              .map((r) => _notificationTile(r, c))
                              .toList()))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: Text(supportText(
                        _language, '나중에 확인', 'Later', 'ກວດພາຍຫຼັງ')))
              ],
            ));
    _notificationPopupOpen = false;
    if (selected != null && mounted) await _openNotificationTarget(selected);
    _scheduleUpdatePopup();
  }

  Future<void> _openNotificationTarget(Map<String, dynamic> row) async {
    try {
      if (row['related_quote_id'] != null) {
        await Navigator.push(
            context,
            MaterialPageRoute<void>(
                builder: (_) => SupportDetailScreen(
                    id: (row['related_quote_id'] as num).toInt(),
                    language: _language,
                    manager: const [UserRole.admin, UserRole.staff]
                        .contains(_currentUser?.role))));
      } else {
        final related = row['related_request_id'] == null
            ? null
            : await NotificationService.instance
                .relatedRequest((row['id'] as num).toInt());
        if (!mounted) return;
        await NotificationService.instance.read((row['id'] as num).toInt());
        if (!mounted) return;
        await showDialog<void>(
            context: context,
            builder: (c) => AlertDialog(
                    title: Text('${row['title'] ?? ''}'),
                    content: SingleChildScrollView(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('${row['message'] ?? ''}'),
                          if (related != null) ...[
                            const Divider(),
                            Text(
                                '${related['receipt_number'] ?? ''} · ${related['invoice_number'] ?? ''}'),
                            Text(
                                '${related['consignee_name'] ?? ''} · ${related['status'] ?? ''}'),
                            for (final entry in Map<String, dynamic>.from(
                                    related['admin_changes'] ??
                                        related['changes'] ??
                                        {})
                                .entries)
                              Text('${entry.key}: ${entry.value}')
                          ]
                        ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: Text(AppStrings.get(_language, 'close')))
                    ]));
      }
      if (mounted) await _refreshNotifications(showPopup: false);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _openNotifications() async {
    if (_notificationPopupOpen || _updatePopupOpen) return;
    _notificationPopupOpen = true;
    final userId = _isLoggedIn ? _currentUser?.id : null;
    var rows = <Map<String, dynamic>>[], offset = 0;
    var more = false, loading = false;
    String? error;
    try {
      if (userId != null) {
        try {
          final data = await NotificationService.instance.feed();
          rows = List<Map<String, dynamic>>.from(data['rows'] as List);
          more = rows.length == 50;
        } catch (e) {
          error = '$e';
        }
      }
      if (!mounted) return;
      if (_currentUser?.id != userId) {
        rows = [];
        more = false;
      }
      final selected = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (c) => StatefulBuilder(
              builder: (c, update) => AlertDialog(
                    title: Text(AppStrings.get(_language, 'notifications')),
                    content: SizedBox(
                        width: double.maxFinite,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              CodeUpdatePanel(
                                  language: _language, service: _codeUpdates),
                              if (userId != null) ...[
                                const Divider(),
                                Text(supportText(
                                    _language,
                                    '미확인 알림은 계속 보관되며, 요청 내용을 확인한 뒤 24시간 동안 표시됩니다.',
                                    'Unread alerts stay until reviewed, then for 24 hours.',
                                    'ແຈ້ງເຕືອນຢູ່ຈົນກວດແລ້ວ ແລະ ອີກ 24 ຊົ່ວໂມງ.')),
                                if (error != null) Text(error!),
                                if (rows.isEmpty && error == null)
                                  Text(AppStrings.get(
                                      _language, 'no_notifications')),
                                for (final row in rows)
                                  _notificationTile(row, c),
                                if (more)
                                  TextButton(
                                      onPressed: loading
                                          ? null
                                          : () async {
                                              update(() => loading = true);
                                              try {
                                                final data =
                                                    await NotificationService
                                                        .instance
                                                        .feed(
                                                            offset:
                                                                offset + 50);
                                                if (!c.mounted ||
                                                    _currentUser?.id != userId)
                                                  return;
                                                final page = List<
                                                        Map<String,
                                                            dynamic>>.from(
                                                    data['rows'] as List);
                                                update(() {
                                                  offset += 50;
                                                  rows.addAll(page);
                                                  more = page.length == 50;
                                                });
                                              } catch (e) {
                                                if (c.mounted)
                                                  update(() => error = '$e');
                                              } finally {
                                                if (c.mounted)
                                                  update(() => loading = false);
                                              }
                                            },
                                      child: Text(supportText(_language, '더 보기',
                                          'Load more', 'ເບິ່ງເພີ່ມ')))
                              ]
                            ]))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: Text(AppStrings.get(_language, 'close')))
                    ],
                  )));
      await _codeUpdates.acknowledge();
      _notificationPopupOpen = false;
      if (selected != null && mounted && _currentUser?.id == userId)
        await _openNotificationTarget(selected);
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

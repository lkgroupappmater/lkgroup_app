import 'dart:async';

import 'package:flutter/material.dart';

import '../services/live_data_service.dart';

final autoRefreshRouteObserver = RouteObserver<ModalRoute<dynamic>>();

/// IndexedStack keeps hidden tabs mounted, so visibility must be explicit.
class AutoRefreshScope extends InheritedWidget {
  const AutoRefreshScope({super.key, required this.active, required super.child});
  final bool active;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AutoRefreshScope>()?.active ?? true;

  @override
  bool updateShouldNotify(AutoRefreshScope oldWidget) => active != oldWidget.active;
}

/// Refreshes data without remounting a screen or replacing editor controllers.
/// Subclasses must check [canApplyAutoRefresh] after asynchronous reads too.
mixin AutoRefreshState<T extends StatefulWidget> on State<T> implements RouteAware {
  Set<String> get autoRefreshTopics;
  bool get autoRefreshAllowed => true;
  Future<void> refreshAutomatically();

  ModalRoute<dynamic>? _observedRoute;
  bool _active = false;
  bool _pendingRefresh = false;
  bool _refreshing = false;
  Timer? _refreshTimer;

  bool get canApplyAutoRefresh {
    if (!mounted || !_active || !LiveDataService.instance.foreground ||
        !autoRefreshAllowed || _observedRoute?.isCurrent == false) return false;
    final focus = FocusManager.instance.primaryFocus;
    final editing = focus?.context?.findAncestorStateOfType<EditableTextState>() != null;
    return !editing && (MediaQuery.maybeOf(context)?.viewInsets.bottom ?? 0) == 0;
  }

  @override
  void initState() {
    super.initState();
    LiveDataService.instance.addListener(_onDataChanged);
    FocusManager.instance.addListener(_tryRefresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _observedRoute) {
      autoRefreshRouteObserver.unsubscribe(this);
      _observedRoute = route;
      if (route != null) autoRefreshRouteObserver.subscribe(this, route);
    }
    final active = AutoRefreshScope.of(context);
    if (active && !_active) _pendingRefresh = true;
    _active = active;
    _tryRefresh();
  }

  void _onDataChanged() {
    final topics = LiveDataService.instance.topics;
    if (topics.contains('*') || topics.any(autoRefreshTopics.contains)) {
      _pendingRefresh = true;
      _tryRefresh();
    }
  }

  void _tryRefresh() {
    if (!_pendingRefresh || _refreshing || _refreshTimer != null || !mounted) return;
    // Run outside widget build / dependency updates.
    _refreshTimer = Timer(const Duration(milliseconds: 350), () async {
      _refreshTimer = null;
      if (!canApplyAutoRefresh) return;
      _pendingRefresh = false;
      _refreshing = true;
      try {
        await refreshAutomatically();
      } catch (_) {
        // Keep displayed data on transient network errors; retry on next signal.
      } finally {
        _refreshing = false;
        if (mounted) _tryRefresh();
      }
    });
  }

  @override
  void didPopNext() {
    _pendingRefresh = true;
    _tryRefresh();
  }

  @override
  void didPush() {}
  @override
  void didPop() {}
  @override
  void didPushNext() {}

  @override
  void dispose() {
    _refreshTimer?.cancel();
    autoRefreshRouteObserver.unsubscribe(this);
    LiveDataService.instance.removeListener(_onDataChanged);
    FocusManager.instance.removeListener(_tryRefresh);
    super.dispose();
  }
}

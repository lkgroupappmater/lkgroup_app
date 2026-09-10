// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lkgroup_app/services/live_data_service.dart';
import 'package:lkgroup_app/widgets/auto_refresh_state.dart';

class Probe extends StatefulWidget {
  const Probe({super.key, required this.refresh, this.allowed = true});
  final Future<void> Function() refresh;
  final bool allowed;
  @override
  State<Probe> createState() => _ProbeState();
}

class _ProbeState extends State<Probe> with AutoRefreshState<Probe> {
  @override
  Set<String> get autoRefreshTopics => const {'content'};
  @override
  bool get autoRefreshAllowed => widget.allowed;
  @override
  Future<void> refreshAutomatically() => widget.refresh();
  @override
  Widget build(BuildContext context) => const Scaffold(body: TextField());
}

void signal([String topic = 'content']) {
  LiveDataService.instance.topics = {topic};
  LiveDataService.instance.notifyListeners();
}

void main() {
  setUp(() => LiveDataService.instance.foreground = true);

  testWidgets('hidden tabs defer requests and refresh when visible', (tester) async {
    var count = 0;
    Widget app(bool active) => MaterialApp(
      navigatorObservers: [autoRefreshRouteObserver],
      home: AutoRefreshScope(active: active, child: Probe(refresh: () async { count++; })),
    );
    await tester.pumpWidget(app(false));
    signal();
    await tester.pump(const Duration(seconds: 1));
    expect(count, 0);
    await tester.pumpWidget(app(true));
    await tester.pump(const Duration(seconds: 1));
    expect(count, 1);
    signal('shipments');
    await tester.pump(const Duration(seconds: 1));
    expect(count, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('typing and an editor lock defer refresh without losing the event', (tester) async {
    var count = 0;
    Widget app(bool allowed) => MaterialApp(
      navigatorObservers: [autoRefreshRouteObserver],
      home: Probe(allowed: allowed, refresh: () async { count++; }),
    );
    await tester.pumpWidget(app(false));
    await tester.pump(const Duration(seconds: 1));
    expect(count, 0);
    await tester.pumpWidget(app(true));
    await tester.tap(find.byType(TextField));
    signal();
    await tester.pump(const Duration(seconds: 1));
    expect(count, 0);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(count, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dialogs defer refresh and closing them catches up', (tester) async {
    var count = 0;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      navigatorObservers: [autoRefreshRouteObserver],
      home: Probe(refresh: () async { count++; }),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(count, 1);
    unawaited(showDialog<void>(context: tester.element(find.byType(Probe)),
      builder: (_) => const AlertDialog(content: Text('Editing'))));
    await tester.pumpAndSettle();
    signal();
    await tester.pump(const Duration(seconds: 1));
    expect(count, 1);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(count, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('coalesces concurrent signals, pauses in background and disposes', (tester) async {
    var count = 0;
    final pending = Completer<void>();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [autoRefreshRouteObserver],
      home: Probe(refresh: () async {
        count++;
        if (count == 1) await pending.future;
      }),
    ));
    await tester.pump(const Duration(seconds: 1));
    signal(); signal(); signal();
    await tester.pump(const Duration(seconds: 1));
    expect(count, 1);
    pending.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(count, 2);
    LiveDataService.instance.foreground = false;
    signal();
    await tester.pump(const Duration(seconds: 1));
    expect(count, 2);
    await tester.pumpWidget(const SizedBox());
    LiveDataService.instance.foreground = true;
    signal();
    await tester.pump(const Duration(seconds: 1));
    expect(count, 2);
  });
}

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lkgroup_app/core/app_language.dart';
import 'package:lkgroup_app/core/cargo_tracking.dart';
import 'package:lkgroup_app/core/route_map_geometry.dart';
import 'package:lkgroup_app/widgets/cargo_tracking_dialog.dart';
import 'package:lkgroup_app/widgets/route_overview.dart';

void main() {
  test('overview uses visible actual schedules in the same newest-first order as web', () {
    Map<String, dynamic> row(String date, {bool visible = true}) => {'route': '한국->라오스 해상', 'booking_close_date': date, 'is_visible': visible};
    final rows = RouteOverview.visibleRows([row('2026-09-01'), row('2026-10-01'), row('2027-01-01', visible: false), {'route': 'unknown'}, {...row('2026-12-01'), 'deleted_at': '2026-01-01'}]);
    expect(rows.map((r) => r['booking_close_date']), ['2026-10-01', '2026-09-01']);
  });
  test('Lao display text does not change the underlying route or transport status', () {
    final row = <String, dynamic>{'route': 'ຂົນສົ່ງ', 'tracking_route': '한국->라오스 항공', 'status': 'ຮອດ', 'tracking_status': 'arrived'};
    expect(CargoTracking.modeOf(row), CargoTrackingMode.air);
    expect(CargoTracking.progress(row), 1);
  });
  test('sea leg avoids Taiwan including visible route stroke', () {
    final island = Path()..moveTo(492.9,264.2)..lineTo(483.5,284.7)..lineTo(476.9,295.2)..lineTo(468.7,284.4)..lineTo(467,274.9)..lineTo(476.1,262.3)..lineTo(488.5,252.6)..lineTo(495.6,256.4)..close();
    final metric = sharedSeaRoutePath().computeMetrics().single;
    for (double i=0; i<metric.length; i+=.5) {
      final point = metric.getTangentForOffset(i)!.position;
      for (var j=0; j<16; j++) {
        expect(island.contains(point + Offset(math.cos(j*math.pi/8), math.sin(j*math.pi/8))*6), isFalse);
      }
    }
  });
  testWidgets('map appears in all languages with multiple voyages, zoom and no overflow', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final language in AppLanguage.values) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: RouteOverview(language: language, schedules: [
        {'route':'한국->라오스 해상','year':'2026','voyage':'09','booking_close_date':'2026-09-09','estimated_arrival_date':'2026-09-24'},
        {'route':'한국->라오스 항공','year':'2026','voyage':'18','booking_close_date':'2026-09-17','estimated_arrival_date':'2026-09-18'},
      ]))))));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(CargoRouteMap), findsOneWidget);
      expect(find.text(CargoTrackingLabels.text(language, 'mapTitle')), findsOneWidget);
      await tester.tap(find.byTooltip(CargoTrackingLabels.text(language, 'zoomIn')));
      await tester.pump();
      await tester.tap(find.byTooltip(CargoTrackingLabels.text(language, 'reset')));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });
}

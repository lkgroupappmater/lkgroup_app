import 'package:flutter/material.dart';
import '../core/app_language.dart';
import '../core/cargo_tracking.dart';
import '../core/route_catalog.dart';
import '../core/shipment_period_labels.dart';
import 'cargo_tracking_dialog.dart';

/// Uses the same visible shipping_schedules rows as the web overview.
class RouteOverview extends StatelessWidget {
  const RouteOverview({super.key, required this.schedules, required this.language});
  final List<Map<String, dynamic>> schedules;
  final AppLanguage language;

  static List<Map<String, dynamic>> visibleRows(List<Map<String, dynamic>> rows) {
    final visible = rows.where((row) =>
      CargoTracking.modeOf(row) != null && row['is_visible'] != false &&
      row['deleted_at'] == null &&
      (row['deletion_status'] ?? 'active') == 'active').toList();
    visible.sort((a, b) => '${b['booking_close_date'] ?? ''}'.compareTo('${a['booking_close_date'] ?? ''}'));
    return visible.take(4).toList();
  }

  @override
  Widget build(BuildContext context) {
    final rows = visibleRows(schedules);
    String label(String key) => CargoTrackingLabels.text(language, key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label('mapTitle'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Semantics(
          label: label('mapTitle'),
          child: CargoRouteMap(mode: CargoTrackingMode.sea, progress: null, language: language, schedules: rows),
        ),
        const SizedBox(height: 8),
        Text(label('note'), style: Theme.of(context).textTheme.bodySmall),
        if (rows.isEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(label('missing'))),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${RouteCatalog.localizedLabel('${row['tracking_route'] ?? row['route'] ?? ''}', language)} · ${ShipmentPeriodLabels.year(row['year'] ?? row['shipment_year'], language)} / ${ShipmentPeriodLabels.voyage(row['voyage'], language)}', style: const TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w600)),
              Text(CargoTrackingLabels.summary(language, row), style: const TextStyle(fontSize: 13, height: 1.4)),
            ]),
          ),
      ],
    );
  }
}


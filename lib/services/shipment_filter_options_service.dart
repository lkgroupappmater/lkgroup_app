import '../config/supabase_config.dart';
import 'supabase_service.dart';

class ShipmentBatchOption {
  const ShipmentBatchOption({
    required this.route,
    required this.year,
    required this.voyage,
  });

  final String route;
  final int year;
  final String voyage;
}

class ShipmentFilterOptionsService {
  ShipmentFilterOptionsService._();
  static final instance = ShipmentFilterOptionsService._();

  Future<List<ShipmentBatchOption>> listBatches() async {
    if (!SupabaseConfig.isConfigured) return const [];
    final raw =
        await SupabaseService.client.rpc('list_shipment_filter_batches') as List;

    final rows = raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .map((row) {
          final year = (row['shipment_year'] as num?)?.toInt();
          final route = '${row['route'] ?? ''}'.trim();
          final voyage = '${row['voyage'] ?? ''}'.trim();
          if (route.isEmpty || year == null || voyage.isEmpty) return null;
          return ShipmentBatchOption(
            route: route,
            year: year,
            voyage: voyage,
          );
        })
        .whereType<ShipmentBatchOption>()
        .toList(growable: false);

    return rows;
  }

  List<int> yearsFor(
    List<ShipmentBatchOption> rows,
    String route,
  ) {
    final result = rows
        .where((e) => e.route == route)
        .map((e) => e.year)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return result;
  }

  List<String> voyagesFor(
    List<ShipmentBatchOption> rows,
    String route,
    int year,
  ) {
    final result = rows
        .where((e) => e.route == route && e.year == year)
        .map((e) => e.voyage)
        .toSet()
        .toList();

    int number(String value) =>
        int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) ?? -1;
    result.sort((a, b) => number(b).compareTo(number(a)));
    return result;
  }
}

import '../config/supabase_config.dart';
import '../core/route_catalog.dart';
import 'exchange_rate_service.dart';
import 'supabase_service.dart';

class FreightLineResult {
  const FreightLineResult({
    required this.shipmentId,
    required this.boxNumber,
    required this.invoiceNumber,
    required this.route,
    required this.actualWeight,
    required this.volumeWeight,
    required this.chargeableWeight,
    required this.rate,
    required this.amountUsd,
  });

  final String shipmentId;
  final String boxNumber;
  final String invoiceNumber;
  final String route;
  final double actualWeight;
  final double volumeWeight;
  final double chargeableWeight;
  final double rate;
  final double amountUsd;
}

class FreightCalculation {
  const FreightCalculation({
    required this.lines,
    required this.totalUsd,
    required this.totalKip,
    required this.totalThb,
    required this.totalKrw,
    required this.rates,
  });

  final List<FreightLineResult> lines;
  final double totalUsd;
  final double totalKip;
  final double totalThb;
  final double totalKrw;
  final ExchangeRateSettings rates;
}

class FreightService {
  FreightService._();
  static final FreightService instance = FreightService._();

  Future<FreightCalculation> calculate(List<Map<String, dynamic>> shipments) async {
    final exchange = await ExchangeRateService.instance.fetch();
    final lines = <FreightLineResult>[];

    for (final row in shipments) {
      final routeLabel = '${row['route'] ?? ''}';
      final routeKey = RouteCatalog.keyFor(routeLabel);
      final quantity = _d(row['quantity'], 1).clamp(1, 999999).toDouble();
      final actual = _d(row['weight_kg']) * quantity;
      final volume = _d(row['length_cm']) *
          _d(row['width_cm']) *
          _d(row['height_cm']) *
          0.00022 *
          quantity;
      final chargeable = actual > volume ? actual : volume;

      final policy = await _policy(routeKey, chargeable);
      double rate = _d(policy['rate_per_kg']);
      double minimum = _d(policy['minimum_charge']);
      double amount = chargeable * rate;
      if (amount > 0 && amount < minimum) amount = minimum;

      final override = await _customerOverride(
        routeKey: routeKey,
        name: '${row['consignee_name'] ?? ''}',
        phone: '${row['consignee_phone'] ?? ''}',
      );
      final overrideRate = _nullableD(override?['rate_override']);
      if (overrideRate != null) {
        rate = overrideRate;
        amount = chargeable * rate;
        if (amount > 0 && amount < minimum) amount = minimum;
      }
      final discount = _d(override?['discount_percent']);
      if (discount > 0) amount *= (1 - discount);

      lines.add(FreightLineResult(
        shipmentId: '${row['id'] ?? ''}',
        boxNumber: '${row['box_number'] ?? ''}',
        invoiceNumber: '${row['invoice_number'] ?? ''}',
        route: routeLabel,
        actualWeight: actual,
        volumeWeight: volume,
        chargeableWeight: chargeable,
        rate: rate,
        amountUsd: amount,
      ));
    }

    final totalUsd = lines.fold<double>(0, (sum, line) => sum + line.amountUsd);
    return FreightCalculation(
      lines: lines,
      totalUsd: totalUsd,
      totalKip: totalUsd * exchange.appliedKip,
      totalThb: totalUsd * exchange.appliedThb,
      totalKrw: totalUsd * exchange.appliedKrw,
      rates: exchange,
    );
  }

  Future<Map<String, dynamic>> _policy(String routeKey, double weight) async {
    if (!SupabaseConfig.isConfigured) return const {};
    final rows = await SupabaseService.client
        .from('freight_rate_tiers')
        .select()
        .eq('route_key', routeKey)
        .lte('min_weight_kg', weight)
        .order('min_weight_kg', ascending: false)
        .limit(1);
    if (rows.isEmpty) {
      final fallback = await SupabaseService.client
          .from('freight_rate_tiers')
          .select()
          .eq('route_key', routeKey)
          .order('min_weight_kg', ascending: true)
          .limit(1);
      return fallback.isEmpty ? const {} : Map<String, dynamic>.from(fallback.first);
    }
    return Map<String, dynamic>.from(rows.first);
  }

  Future<Map<String, dynamic>?> _customerOverride({
    required String routeKey,
    required String name,
    required String phone,
  }) async {
    if (!SupabaseConfig.isConfigured || name.trim().isEmpty) return null;
    var query = SupabaseService.client
        .from('customer_rate_overrides')
        .select()
        .eq('active', true)
        .ilike('customer_name', name.trim());
    final rows = await query.limit(30);
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw);
      final route = '${row['route_key'] ?? ''}';
      final savedPhone = _digits('${row['phone'] ?? ''}');
      if (route != 'all' && route != routeKey) continue;
      if (savedPhone.isNotEmpty && _digits(phone) != savedPhone) continue;
      return row;
    }
    return null;
  }

  static String _digits(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');
  static double _d(dynamic value, [double fallback = 0]) =>
      double.tryParse('${value ?? ''}'.trim()) ?? fallback;
  static double? _nullableD(dynamic value) =>
      value == null ? null : double.tryParse('$value');
}

import '../config/supabase_config.dart';
import '../core/route_catalog.dart';
import 'exchange_rate_service.dart';
import 'freight_policy_service.dart';
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

  Future<FreightCalculation> calculate(
    List<Map<String, dynamic>> shipments,
  ) async {
    final exchange = await ExchangeRateService.instance.fetch();
    final lines = <FreightLineResult>[];
    final policyCache = <String, FreightPolicy>{};

    for (final row in shipments) {
      final routeLabel = '${row['route'] ?? ''}';
      final routeKey = RouteCatalog.keyFor(routeLabel);
      final policy = policyCache[routeKey] ??=
          await FreightPolicyService.instance.fetch(routeKey);

      final quantity = _d(row['quantity'], 1).clamp(1, 999999).toDouble();
      final actual = _d(row['weight_kg']) * quantity;
      final volume = _d(row['length_cm']) *
          _d(row['width_cm']) *
          _d(row['height_cm']) *
          policy.volumetricFactor *
          quantity;
      final chargeable = actual > volume ? actual : volume;

      double rate = policy.rateFor(chargeable);
      final minimum = policy.minimumCharge;
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

      lines.add(
        FreightLineResult(
          shipmentId: '${row['id'] ?? ''}',
          boxNumber: '${row['box_number'] ?? ''}',
          invoiceNumber: '${row['invoice_number'] ?? ''}',
          route: routeLabel,
          actualWeight: actual,
          volumeWeight: volume,
          chargeableWeight: chargeable,
          rate: rate,
          amountUsd: amount,
        ),
      );
    }

    final totalUsd =
        lines.fold<double>(0, (sum, line) => sum + line.amountUsd);

    return FreightCalculation(
      lines: lines,
      totalUsd: totalUsd,
      totalKip: totalUsd * exchange.appliedKip,
      totalThb: totalUsd * exchange.appliedThb,
      totalKrw: totalUsd * exchange.appliedKrw,
      rates: exchange,
    );
  }

  Future<Map<String, dynamic>?> _customerOverride({
    required String routeKey,
    required String name,
    required String phone,
  }) async {
    final normalizedPhone = _digits(phone);
    if (!SupabaseConfig.isConfigured ||
        name.trim().isEmpty ||
        normalizedPhone.isEmpty) {
      return null;
    }

    final rows = await SupabaseService.client
        .from('customer_rate_overrides')
        .select()
        .eq('active', true)
        .ilike('customer_name', name.trim())
        .eq('phone', normalizedPhone)
        .limit(30);

    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw);
      final route = '${row['route_key'] ?? ''}';
      if (route != 'all' && route != routeKey) continue;
      return row;
    }
    return null;
  }

  static String _digits(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');

  static double _d(dynamic value, [double fallback = 0]) =>
      double.tryParse('${value ?? ''}'.trim()) ?? fallback;

  static double? _nullableD(dynamic value) =>
      value == null ? null : double.tryParse('$value');
}
